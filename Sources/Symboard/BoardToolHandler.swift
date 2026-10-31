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

        case "spawn_console", "hand_off":
            let handoff = tool == "hand_off"
            let agent = str("agent").isEmpty && handoff ? "claude" : str("agent").lowercased()
            guard ["claude", "codex", "shell"].contains(agent), let choice = AgentCatalog.choice(id: agent) else {
                reply("agent must be claude, codex or shell", true); return
            }
            guard agent == "shell" || AgentCatalog.shared.installed.contains(agent) else {
                reply("\(agent) is not installed on this Mac", true); return
            }
            let prompt = args["prompt"] as? String ?? ""
            if handoff, prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reply("hand_off needs a prompt", true); return }
            let callerNode = caller.flatMap { model.node($0) }
            let cwd = callerNode?.terminal?.cwd ?? projectPath
            guard SessionManager.folderExists(cwd) else {
                reply("The folder \(cwd) does not exist, so no console was opened. Ask the user to open a folder in Symboard.", true); return
            }
            let open = { [weak self] in
                guard let self else { return }
                self.openAgentConsole(caller: caller, wsID: wsID, choice: choice, agent: agent, cwd: cwd, name: str("name"), group: str("group"),
                                      prompt: prompt, card: handoff ? (str("title"), prompt) : nil, reply: reply)
            }
            // 9차 5번: 이어 띄우기 단계·개수 제한. 넘으면 사용자에게 묻는다.
            let links = ws.links ?? []
            let consoleIDs = Set(consoles(in: wsID).map(\.id))
            let depth = caller.map { AgentLimits.depth(of: $0, links: links, isConsole: { consoleIDs.contains($0) }) } ?? 0
            let opened = AgentLimits.openedCount(consoles: Array(consoleIDs), links: links)
            guard let why = AgentLimits.exceeded(callerDepth: depth, opened: opened,
                                                 maxDepth: AgentLimits.maxDepth(Prefs.shared), maxOpened: AgentLimits.maxOpened(Prefs.shared)) else {
                open(); return
            }
            let shown = AgentLimits.exceeded(callerDepth: depth, opened: opened, maxDepth: AgentLimits.maxDepth(Prefs.shared),
                                             maxOpened: AgentLimits.maxOpened(Prefs.shared), localized: true) ?? why
            askToExceed(L("%@ wants to open another console: %@.", callerNode?.title ?? L("An agent"), shown), allow: open) {
                reply("The user did not allow another console (\(why)). Do not retry; tell the user.", true)
            }

        case "add_note":
            let text = args["text"] as? String ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reply("add_note needs text", true); return }
            if model.selectedWorkspace.id != wsID { model.selectWorkspace(wsID) }
            let id = placeCard(text: text, title: str("title").isEmpty ? "Note" : str("title"),
                               colorHex: Self.noteColors[str("color").lowercased()] ?? Self.noteColors["yellow"]!, near: caller)
            if let caller { currentCanvas?.select(caller) }
            reply("Added a note\(caller.flatMap { model.node($0) }.map { " next to \($0.title)" } ?? "") (\(id.uuidString.prefix(8))).", false)

        case "draw_diagram":
            guard let data = try? JSONSerialization.data(withJSONObject: args),
                  let spec = DiagramSpec.parse(String(decoding: data, as: UTF8.self)) else {
                reply("draw_diagram needs title, nodes [{id, label}] and edges [{from, to}]", true); return
            }
            if model.selectedWorkspace.id != wsID { model.selectWorkspace(wsID) }
            // 부른 콘솔 옆 빈 칸에 그리고, 다 그린 뒤 답한다(곧이어 hand_off 가 와도 상자와 겹치지 않게).
            let size = DiagramMaker.footprint(spec)
            let area = besideFrame(w: size.width, h: size.height, near: caller)
            diagrams.draw(spec, center: scrollView.visibleCenter, area: area) { [weak self] in
                if let caller { self?.currentCanvas?.select(caller) }
                reply("Drew \"\(spec.title)\": \(spec.nodes.count) boxes, \(spec.edges.count) arrows.", false)
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

    static let noteColors = ["yellow": "#C9A227", "blue": "#3D7DCA", "green": "#3E9B63", "pink": "#C2577F", "purple": "#7F5BC2", "gray": "#6B6560"]

    /// 부른 콘솔 옆에 콘솔을 연다(spawn_console·hand_off). card 가 있으면 먼저 프롬프트 카드를 놓고 부른 콘솔 → 카드 → 새 콘솔로 잇는다.
    private func openAgentConsole(caller: UUID?, wsID: UUID, choice: AgentChoice, agent: String, cwd: String, name wanted: String, group g: String,
                                  prompt: String, card: (title: String, prompt: String)?, reply: @escaping (String, Bool) -> Void) {
        guard let ws = model.state.workspaces.first(where: { $0.id == wsID }) else { reply("That board is gone", true); return }
        if model.selectedWorkspace.id != wsID { model.selectWorkspace(wsID) }
        let callerNode = caller.flatMap { model.node($0) }
        let used = Set(consoles(in: wsID).map { $0.title.lowercased() })
        let name = !wanted.isEmpty && !used.contains(wanted.lowercased()) ? wanted : nextName()
        var teamID: UUID?
        if !g.isEmpty {
            if let t = ws.teams.first(where: { $0.name.lowercased() == g.lowercased() }) { teamID = t.id }
            else {
                let t = Team(name: g, colorHex: Composer.teamColors[ws.teams.count % Composer.teamColors.count])
                model.mutateWorkspace(wsID) { $0.teams.append(t) }
                teamID = t.id
            }
        }
        // 카드와 새 콘솔은 한 덩어리로 같은 줄에 놓는다(카드 왼쪽, 콘솔 오른쪽). 따로 자리를 찾으면 줄이 바뀌어 멀리 떨어졌다.
        var cardID: UUID?
        let node: BoardNode
        if let card {
            let pair = besideFrame(w: Self.cardSize.width + 40 + 640, h: 400, near: caller)
            let title = card.title.isEmpty ? "Handoff" : card.title
            cardID = placeCard(text: "\(title) → \(name)\n\n\(card.prompt)", title: title, colorHex: Self.noteColors["yellow"]!,
                               at: Point(x: pair.x, y: pair.y))
            node = addTerminal(spec: choice.spec(cwd: cwd), at: Point(x: pair.x + Self.cardSize.width + 40, y: pair.y), title: name, teamID: teamID)
            glideReveal([pair], zoomIn: true)
        } else {
            node = addTerminal(spec: choice.spec(cwd: cwd), at: nil, title: name, teamID: teamID, near: caller)
        }
        model.mutateWorkspace(wsID) { w in
            var links = w.links ?? []
            if let cardID {
                if let caller { links.append(NodeLink(from: caller, to: cardID, style: NodeLink.handoffStyle)) }
                links.append(NodeLink(from: cardID, to: node.id, style: NodeLink.handoffStyle))
            } else if let caller {
                links.append(NodeLink(from: caller, to: node.id, style: NodeLink.spawnedStyle))
            }
            w.links = links
        }
        // 고른 것은 부른 콘솔에 그대로 둔다(명령 바 대상이 바뀌지 않게).
        if let caller { currentCanvas?.select(caller) }
        currentCanvas?.layoutGroups()
        currentCanvas?.layoutLinks()
        let opened = "Opened console \(node.title) (\(agent))\(callerNode.map { " next to \($0.title)" } ?? "")\(cardID == nil ? "" : " with a handoff card")."
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reply(opened, false); return }
        whenReady(node.id, timeout: 45) { [weak self] status in
            guard let self, let s = self.model.sessions.session(for: node.id) else { reply(opened + " It closed before the prompt was sent.", true); return }
            if status == .waiting {
                reply(opened + " It is waiting for the user (for example a folder trust question), so the prompt was not sent. Try send_to_console later.", false)
                return
            }
            if status == .exited {
                reply(opened + " It did not start, so the prompt was not sent.", true)
                return
            }
            s.sendText(prompt, submit: true)
            reply(opened + " Sent the prompt. Use read_console(\"\(node.title)\") to see progress.", false)
        }
    }

    static let cardSize = CGSize(width: 300, height: 240)

    /// 메모 카드(스티커)를 놓는다. 자리를 주지 않으면 기준 노드 옆 빈 칸.
    @discardableResult
    private func placeCard(text: String, title: String, colorHex: String, near: UUID? = nil, at point: Point? = nil) -> UUID {
        let f = point.map { Rect(x: $0.x, y: $0.y, w: Self.cardSize.width, h: Self.cardSize.height) }
            ?? besideFrame(w: Self.cardSize.width, h: Self.cardSize.height, near: near)
        var id = UUID()
        addNode(kind: .sticky, size: CGSize(width: f.w, height: f.h), title: title, at: Point(x: f.x, y: f.y)) {
            $0.text = text
            $0.colorHex = colorHex
            id = $0.id
        }
        if point == nil { glideReveal([f]) }
        return id
    }

    /// 제한을 넘는 요청을 사용자에게 묻는다. 2분 안에 답이 없으면 거절로 본다. 다른 확인이 떠 있으면 바로 거절.
    private func askToExceed(_ message: String, allow: @escaping () -> Void, deny: @escaping () -> Void) {
        guard chrome.confirm == nil else { deny(); return }
        var answered = false
        let cf = PendingConfirm(message: message, button: L("Allow once"), action: {
            guard !answered else { return }
            answered = true; allow()
        }, onCancel: {
            guard !answered else { return }
            answered = true; deny()
        })
        chrome.confirm = cf
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard !answered else { return }
            answered = true
            if self?.chrome.confirm?.id == cf.id { self?.chrome.confirm = nil }
            deny()
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
