import AppKit
import SymboardCore

/// 보드 도구 처리(8차 3번): list_consoles, spawn_console, send_to_console, read_console, close_console.
/// 부른 콘솔(caller)이 든 작업공간에서 일한다.
extension MainWindowController {
    func startBoardTools() {
        let server = model.boardTools
        server.handler = { [weak self] caller, tool, args, reply in
            guard let self else { reply("Symboard window is gone", true); return }
            self.handleBoardTool(caller: UUID(uuidString: caller), tool: tool, args: args, reply: reply)
        }
        server.start()
    }

    private func consoles(in wsID: UUID) -> [BoardNode] {
        model.state.workspaces.first { $0.id == wsID }?.nodes.filter { $0.kind == .terminal } ?? []
    }

    private func console(named name: String, in wsID: UUID) -> BoardNode? {
        let n = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        return consoles(in: wsID).first { $0.title.lowercased() == n }
    }

    private func statusText(_ id: UUID) -> String {
        model.sessions.status(of: id)?.pillText.lowercased() ?? "stopped"
    }

    func handleBoardTool(caller: UUID?, tool: String, args: [String: Any], reply: @escaping (String, Bool) -> Void) {
        let wsID = caller.flatMap { model.workspaceID(containing: $0) } ?? model.selectedWorkspace.id
        let ws = model.state.workspaces.first { $0.id == wsID } ?? model.selectedWorkspace
        func str(_ k: String) -> String { (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        switch tool {
        case "list_consoles":
            let rows = consoles(in: wsID).map { n -> String in
                let agent = AgentCatalog.choice(for: n.terminal).id
                let group = n.teamID.flatMap { t in ws.teams.first { $0.id == t }?.name }.map { " · group \($0)" } ?? ""
                return "\(n.title) · \(agent) · \(statusText(n.id))\(group)\(n.id == caller ? " · (you)" : "")"
            }
            reply(rows.isEmpty ? "No consoles on this board." : rows.joined(separator: "\n"), false)

        case "spawn_console":
            let agent = str("agent").lowercased()
            guard ["claude", "codex", "shell"].contains(agent), let choice = AgentCatalog.choice(id: agent) else {
                reply("agent must be claude, codex or shell", true); return
            }
            guard agent == "shell" || AgentCatalog.shared.installed.contains(agent) else {
                reply("\(agent) is not installed on this Mac", true); return
            }
            if model.selectedWorkspace.id != wsID { model.selectWorkspace(wsID) }
            let callerNode = caller.flatMap { model.node($0) }
            let cwd = callerNode?.terminal?.cwd ?? projectPath
            let used = Set(consoles(in: wsID).map { $0.title.lowercased() })
            let wanted = str("name")
            let name = !wanted.isEmpty && !used.contains(wanted.lowercased()) ? wanted : nextName()
            var teamID: UUID?
            let g = str("group")
            if !g.isEmpty {
                if let t = ws.teams.first(where: { $0.name.lowercased() == g.lowercased() }) { teamID = t.id }
                else {
                    let t = Team(name: g, colorHex: Composer.teamColors[ws.teams.count % Composer.teamColors.count])
                    model.mutateWorkspace(wsID) { $0.teams.append(t) }
                    teamID = t.id
                }
            }
            let node = addTerminal(spec: choice.spec(cwd: cwd), at: nil, title: name, teamID: teamID, near: caller)
            if let caller {
                model.mutateWorkspace(wsID) { w in
                    w.links = (w.links ?? []) + [NodeLink(from: caller, to: node.id, style: NodeLink.spawnedStyle)]
                }
                // 고른 것은 부른 콘솔에 그대로 둔다(명령 바 대상이 바뀌지 않게).
                currentCanvas?.select(caller)
            }
            currentCanvas?.layoutGroups()
            currentCanvas?.layoutLinks()
            let prompt = args["prompt"] as? String ?? ""
            let opened = "Opened console \(node.title) (\(agent))\(callerNode.map { " next to \($0.title)" } ?? "")."
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reply(opened, false); return }
            whenReady(node.id, timeout: 45) { [weak self] status in
                guard let self, let s = self.model.sessions.session(for: node.id) else { reply(opened + " It closed before the prompt was sent.", true); return }
                if status == .waiting {
                    reply(opened + " It is waiting for the user (for example a folder trust question), so the prompt was not sent. Try send_to_console later.", false)
                    return
                }
                s.sendText(prompt, submit: true)
                reply(opened + " Sent the prompt. Use read_console(\"\(node.title)\") to see progress.", false)
            }

        case "send_to_console":
            guard let n = console(named: str("name"), in: wsID) else { reply("No console named \(str("name"))", true); return }
            guard n.id != caller else { reply("That is your own console", true); return }
            let text = args["text"] as? String ?? ""
            guard !text.isEmpty, let s = model.sessions.session(for: n.id) else { reply("Nothing to send or console not running", true); return }
            s.sendText(text, submit: true)
            reply("Sent to \(n.title).", false)

        case "read_console":
            guard let n = console(named: str("name"), in: wsID) else { reply("No console named \(str("name"))", true); return }
            let lines = min(400, max(1, (args["lines"] as? Int) ?? Int(str("lines")) ?? 40))
            let body = model.sessions.session(for: n.id)?.transcript(lastLines: lines) ?? ""
            reply("\(n.title) · status: \(statusText(n.id))\n---\n\(body)", false)

        case "close_console":
            guard let n = console(named: str("name"), in: wsID) else { reply("No console named \(str("name"))", true); return }
            guard n.id != caller else { reply("You cannot close your own console", true); return }
            if model.selectedWorkspace.id == wsID { removeNodes([n.id]) } else { model.removeNode(n.id) }
            reply("Closed \(n.title).", false)

        default:
            reply("Unknown tool \(tool)", true)
        }
    }

    /// 콘솔이 입력을 받을 수 있게 되면(시작 중이 아니면) 부른다. 셸은 프롬프트, claude·codex 는 첫 화면이 뜬 뒤.
    private func whenReady(_ id: UUID, timeout: TimeInterval, started: Date = Date(), _ then: @escaping (NodeStatus?) -> Void) {
        let st = model.sessions.status(of: id)
        let waited = Date().timeIntervalSince(started)
        if model.node(id) == nil { then(nil); return }
        if waited > 1.2, let st, st != .starting { then(st); return }
        if waited > timeout { then(st); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.whenReady(id, timeout: timeout, started: started, then)
        }
    }
}
