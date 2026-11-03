import AppKit
import SymboardCore

extension Notification.Name {
    /// 1초마다 노드 상태를 다시 계산한 뒤 보낸다.
    static let statusTick = Notification.Name("symboard.statusTick")
    /// 이어하기 대기 콘솔이 답을 받았을 때. object 는 노드 id.
    static let resumeChanged = Notification.Name("symboard.resumeChanged")
}

/// 노드 id 별 터미널 세션. 작업공간을 바꿔도 프로세스는 계속 돈다.
@MainActor
final class SessionManager {
    unowned let model: AppModel
    private(set) var sessions: [UUID: TerminalSession] = [:]
    private(set) var statuses: [UUID: NodeStatus] = [:]
    /// 지금 상태가 시작된 시각(미션 맵의 "For").
    private(set) var statusSince: [UUID: Date] = [:]
    private var timer: Timer?
    let shell = ProcessEnvironment.userShell

    /// 다시 열었을 때 이어 할지 답을 기다리는 콘솔. 답할 때까지 띄우지 않는다.
    private(set) var pendingResume: Set<UUID> = []
    /// 묻지 않고 바로 이어 가는 콘솔. 처음 띄울 때 "이어 가는 중" 한 줄을 보여 주고 뺀다.
    private var autoResume: Set<UUID> = []

    /// 콘솔을 앱 밖에서 돌리는 agentd(13차). nil 이면 예전처럼 앱 안에서 돌린다.
    let agentd: AgentdHost?
    /// 켤 때 agentd 에서 아직 돌고 있던(또는 앱이 꺼진 사이 끝난) 콘솔. 노드가 보이면 새로 띄우지 않고 붙는다.
    private var adoptable: [UUID: AgentdSessionInfo] = [:]

    init(model: AppModel) {
        self.model = model
        if !AgentdHost.disabledByEnv, KeepConsolesPrefs.enabled(Prefs.shared) {
            let host = AgentdHost(directory: model.store.directory)
            agentd = host.ensureConnected() ? host : nil
        } else {
            agentd = nil
        }
        if let agentd {
            for info in agentd.initialSessions {
                if model.node(info.id)?.terminal != nil {
                    adoptable[info.id] = info
                } else {
                    // 보드에 없는 콘솔(다른 곳에서 지워진 노드)은 끈다.
                    agentd.send(AgentdFrame(.kill, id: info.id))
                }
            }
        }
        // 아직 돌고 있는 콘솔은 이어 하기를 묻지도, 새로 띄우지도 않는다. 그대로 붙는다.
        let candidates = Set(ResumePolicy.candidates(in: model.state)).subtracting(adoptable.keys)
        if UIPrefs.askResume(Prefs.shared) { pendingResume = candidates } else { autoResume = candidates }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // 설정에서 터미널 글꼴을 바꾸면 떠 있는 콘솔 모두에 바로 적용한다.
        NotificationCenter.default.addObserver(forName: .terminalFontChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let font = TerminalFont.current
                for s in self.sessions.values { s.view.font = font }
            }
        }
    }

    func session(for nodeID: UUID) -> TerminalSession? { sessions[nodeID] }

    /// 폴더가 없어 콘솔을 띄우지 않았을 때(창이 알림을 띄운다).
    var onMissingFolder: ((String) -> Void)?

    static func folderExists(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    /// 세션이 없으면 만들고 프로세스를 띄운다.
    func ensureSession(for node: BoardNode) -> TerminalSession? {
        if let s = sessions[node.id] { return s }
        guard let spec = node.terminal else { return nil }
        let link: ConsoleLink = agentd.map { RemoteLink(id: node.id, host: $0) } ?? LocalLink()
        let s = TerminalSession(nodeID: node.id, statusDirectory: model.statusDirectory, usesHooks: spec.agent.supportsHooks, link: link)
        s.isPlainShell = spec.agent == .shell
        s.alwaysBracketedPaste = spec.agent == .claude || spec.agent == .codex
        sessions[node.id] = s
        if let info = adoptable.removeValue(forKey: node.id) {
            s.attach(info, plan: nil)
            if spec.agent == .claude { watchSessionID(s) }
        } else if !pendingResume.contains(node.id) {
            if autoResume.remove(node.id) != nil {
                s.view.feed(text: "\u{1b}[2mRestored - picking up the last conversation...\u{1b}[0m\r\n")
            }
            launch(s, spec: spec)
        }
        return s
    }

    /// 기다리던 콘솔을 띄운다. yes 면 지난 대화를 이어 가고, 아니면 새로 시작한다.
    /// 여러 개면 조금씩 간격을 두고 차례로 띄운다.
    func answerResume(_ ids: [UUID], resume yes: Bool, completion: (() -> Void)? = nil) {
        let list = ids.filter { pendingResume.contains($0) }
        for (i, id) in list.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(i)) { [weak self] in
                guard let self, self.pendingResume.contains(id) else { return }
                self.pendingResume.remove(id)
                if !yes { self.model.mutateNode(id) { $0.terminal?.sessionID = nil } }
                if let s = self.sessions[id], let spec = self.model.node(id)?.terminal {
                    s.view.feed(text: yes ? "\u{1b}[2mRestored - picking up the last conversation...\u{1b}[0m\r\n"
                                          : "\u{1b}[2mStarting a new conversation...\u{1b}[0m\r\n")
                    self.launch(s, spec: spec)
                }
                NotificationCenter.default.post(name: .resumeChanged, object: id)
                if i == list.count - 1 { completion?() }
            }
        }
        if list.isEmpty { completion?() }
    }

    func restart(_ nodeID: UUID) {
        guard let s = sessions[nodeID], let spec = model.node(nodeID)?.terminal else { return }
        s.restart { [weak self] in
            // 기다리는 동안 바뀐 설정(권한 모드 등)을 반영한다.
            guard let self, let spec = self.model.node(nodeID)?.terminal else { return }
            self.launch(s, spec: spec)
        }
    }

    private func launch(_ s: TerminalSession, spec: TerminalSpec) {
        // 폴더가 없으면(지워진 /tmp 시험 폴더 등) 띄우지 않는다. 예전에는 홈 폴더에서 띄워 claude 가 홈 폴더 신뢰를 묻고,
        // 홈 아래 음악·사진 폴더를 훑어 macOS 가 Symboard 에 접근 허용을 물었다(9차 4번).
        guard Self.folderExists(spec.cwd) else {
            s.showMissingFolder(spec.cwd)
            onMissingFolder?(spec.cwd)
            return
        }
        let profile = spec.profileID.flatMap { id in model.state.profiles.first { $0.id == id } }
        let configDir = profile?.agent == .claude ? profile?.configDir : nil
        let exists = spec.sessionID.map {
            LaunchPlanner.claudeSessionExists(sessionID: $0, cwd: spec.cwd, configDir: configDir)
        } ?? false
        // 사람이 연 콘솔은 lead(일을 아래 새 콘솔에 나눠 맡김), 다른 콘솔이 연 콘솔은 worker(직접 함).
        // 플래그가 없던 예전 콘솔은 들어오는 spawned·handoff 선으로 가린다.
        let links = model.workspaceID(containing: s.nodeID).flatMap { id in model.state.workspaces.first { $0.id == id }?.links } ?? []
        let openedByAgent = spec.openedByAgent == true
            || links.contains { $0.to == s.nodeID && AgentLimits.chainStyles.contains($0.style ?? "") }
        let role = BoardTools.role(openedByAgent: openedByAgent, leadDelegates: BoardTools.leadDelegates(Prefs.shared))
        // 설정이 켜져 있으면 claude 에 보드 도구(MCP)와 짧은 안내를 인자로만 붙인다(8차 3번). 사용자 ~/.claude 는 그대로.
        var claudeArgs: [String] = []
        if spec.agent == .claude, BoardTools.enabled(Prefs.shared), let exe = BoardToolServer.serverExecutable {
            let cfg = model.statusDirectory.appendingPathComponent("\(s.nodeID.uuidString).mcp.json")
            try? FileManager.default.createDirectory(at: model.statusDirectory, withIntermediateDirectories: true)
            let json = BoardTools.mcpConfigJSON(serverPath: exe, socketPath: model.boardTools.socketPath, nodeID: s.nodeID)
            if (try? json.write(to: cfg, atomically: true, encoding: .utf8)) != nil { claudeArgs = BoardTools.claudeArgs(configPath: cfg.path, role: role) }
        }
        // codex 에도 같은 안내와 도구를 -c 인자로만 붙인다. 사용자 ~/.codex 는 그대로.
        var codexArgs: [String] = []
        if spec.agent == .codex, BoardTools.enabled(Prefs.shared), let exe = BoardToolServer.serverExecutable {
            codexArgs = BoardTools.codexArgs(serverPath: exe, socketPath: model.boardTools.socketPath, nodeID: s.nodeID, role: role)
        }
        let plan = LaunchPlanner.plan(for: spec, nodeID: s.nodeID, statusFile: s.statusFile.path,
                                      profile: profile, claudeSessionExists: exists, defaultShell: shell,
                                      claudeExtraArgs: claudeArgs, codexExtraArgs: codexArgs)
        if spec.agent == .claude { watchSessionID(s) }
        s.start(plan: plan, shell: shell)
        model.mutateNode(s.nodeID) { node in
            node.terminal?.hasLaunched = true
            if let sid = plan.sessionID { node.terminal?.sessionID = sid }
        }
        if spec.agent == .codex && spec.sessionID == nil {
            CodexSessionFinder.watch(for: s.nodeID, cwd: spec.cwd, startedAfter: Date().addingTimeInterval(-2), configDir: profile?.agent == .codex ? profile?.configDir : nil) { [weak self] sid in
                self?.model.mutateNode(s.nodeID) { $0.terminal?.sessionID = sid }
            }
        }
    }

    /// 훅이 알려 준 claude 세션 id 를 노드에 남긴다(이어 하기가 그 id 를 쓴다).
    private func watchSessionID(_ s: TerminalSession) {
        s.onSessionID = { [weak self] sid in
            guard let self, self.model.node(s.nodeID)?.terminal?.sessionID != sid else { return }
            self.model.mutateNode(s.nodeID) { $0.terminal?.sessionID = sid }
        }
    }

    func terminate(_ nodeID: UUID) {
        sessions[nodeID]?.terminate()
        sessions[nodeID] = nil
        statuses[nodeID] = nil
    }

    func terminateAll() {
        for s in sessions.values { s.terminate() }
        // 아직 붙지 않은(다른 작업공간에 있는) agentd 콘솔도 끈다.
        for id in adoptable.keys { agentd?.send(AgentdFrame(.kill, id: id)) }
        adoptable = [:]
        agentd?.closeConnection()
    }

    /// 앱을 끌 때. 설정이 켜져 있고 agentd 가 있으면 콘솔은 두고 연결만 닫는다. 아니면 모두 끈다.
    func quit() {
        guard let agentd, KeepConsolesPrefs.enabled(Prefs.shared) else { terminateAll(); return }
        for s in sessions.values { s.detach() }
        agentd.closeConnection()
    }

    /// 앱을 꺼도 계속 도는 콘솔인지(설정·agentd 둘 다).
    var keepsRunningAfterQuit: Bool { agentd != nil && KeepConsolesPrefs.enabled(Prefs.shared) }

    private func tick() {
        let now = Date()
        for (id, s) in sessions {
            let st = s.resolveStatus(now: now)
            if statuses[id] != st { statusSince[id] = now }
            statuses[id] = st
        }
        NotificationCenter.default.post(name: .statusTick, object: nil)
    }

    func status(of nodeID: UUID) -> NodeStatus? { statuses[nodeID] }

    /// 프로세스가 살아 있는 콘솔 수.
    var liveCount: Int { sessions.values.filter(\.running).count }

    /// 지금 일하는 콘솔 수.
    var workingCount: Int { statuses.values.filter { $0 == .working }.count }

    /// 살아 있는 모든 콘솔의 프로세스 그룹에 신호를 보낸다. 보낸 개수를 돌려준다.
    @discardableResult
    func signalAll(_ sig: Int32) -> Int {
        var n = 0
        for s in sessions.values where s.running {
            if s.signal(sig) { n += 1 }
        }
        return n
    }
}
