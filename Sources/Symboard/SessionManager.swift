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
    private var timer: Timer?
    let shell = ProcessEnvironment.userShell

    /// 다시 열었을 때 이어 할지 답을 기다리는 콘솔. 답할 때까지 띄우지 않는다.
    private(set) var pendingResume: Set<UUID> = []

    init(model: AppModel) {
        self.model = model
        pendingResume = Set(ResumePolicy.candidates(in: model.state))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func session(for nodeID: UUID) -> TerminalSession? { sessions[nodeID] }

    /// 세션이 없으면 만들고 프로세스를 띄운다.
    func ensureSession(for node: BoardNode) -> TerminalSession? {
        if let s = sessions[node.id] { return s }
        guard let spec = node.terminal else { return nil }
        let s = TerminalSession(nodeID: node.id, statusDirectory: model.statusDirectory, usesHooks: spec.agent.supportsHooks)
        sessions[node.id] = s
        if !pendingResume.contains(node.id) { launch(s, spec: spec) }
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
        s.terminate()
        launch(s, spec: spec)
    }

    private func launch(_ s: TerminalSession, spec: TerminalSpec) {
        let profile = spec.profileID.flatMap { id in model.state.profiles.first { $0.id == id } }
        let configDir = profile?.agent == .claude ? profile?.configDir : nil
        let exists = spec.sessionID.map {
            LaunchPlanner.claudeSessionExists(sessionID: $0, cwd: spec.cwd, configDir: configDir)
        } ?? false
        let plan = LaunchPlanner.plan(for: spec, nodeID: s.nodeID, statusFile: s.statusFile.path,
                                      profile: profile, claudeSessionExists: exists, defaultShell: shell)
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

    func terminate(_ nodeID: UUID) {
        sessions[nodeID]?.terminate()
        sessions[nodeID] = nil
        statuses[nodeID] = nil
    }

    func terminateAll() {
        for s in sessions.values { s.terminate() }
    }

    private func tick() {
        let now = Date()
        for (id, s) in sessions { statuses[id] = s.currentStatus(now: now) }
        NotificationCenter.default.post(name: .statusTick, object: nil)
    }

    func status(of nodeID: UUID) -> NodeStatus? { statuses[nodeID] }

    /// 프로세스가 살아 있는 콘솔 수.
    var liveCount: Int { sessions.values.filter(\.running).count }

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
