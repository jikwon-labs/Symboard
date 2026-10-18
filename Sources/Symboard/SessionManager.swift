import AppKit
import SymboardCore

extension Notification.Name {
    /// 1초마다 노드 상태를 다시 계산한 뒤 보낸다.
    static let statusTick = Notification.Name("symboard.statusTick")
}

/// 노드 id 별 터미널 세션. 작업공간을 바꿔도 프로세스는 계속 돈다.
@MainActor
final class SessionManager {
    unowned let model: AppModel
    private(set) var sessions: [UUID: TerminalSession] = [:]
    private(set) var statuses: [UUID: NodeStatus] = [:]
    private var timer: Timer?
    let shell = ProcessEnvironment.userShell

    init(model: AppModel) {
        self.model = model
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
        launch(s, spec: spec)
        return s
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
