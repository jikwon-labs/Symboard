import AppKit
import SwiftUI
import SymboardCore

/// 루프 규칙을 1초마다 확인해서 정해진 문장을 대상 콘솔에 보낸다.
/// 목표 판정이 명령·에이전트면 보내기 직전에 먼저 확인하고, 달성됐으면 보내지 않고 끈다.
@MainActor
final class LoopRunner: ObservableObject {
    unowned let model: AppModel
    private struct Key: Hashable { var rule: UUID; var node: UUID }
    private var runtimes: [Key: LoopRuntime] = [:]
    private var ruleStarted: [UUID: Date] = [:]
    private var lastRound: [UUID: Date] = [:]
    private var checking: Set<UUID> = []
    private var observer: NSObjectProtocol?
    private var notes: [UUID: String] = [:]
    /// 모달 목록 줄. 1초마다 갱신.
    @Published private(set) var rows: [LoopRow] = []

    struct LoopRow: Identifiable, Equatable {
        var id: UUID
        var name: String
        var nodeTitle: String
        var message: String
        var trigger: String
        var summary: String
        var enabled: Bool
        var runs: String
        var runCount: Int
        var note: String
        /// 다음 실행까지 남은 초(간격 조건일 때).
        var nextIn: Int?
        var checking: Bool
    }

    init(model: AppModel) {
        self.model = model
        observer = NotificationCenter.default.addObserver(forName: .statusTick, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: 규칙 편집

    func add(_ rule: LoopRule, to wsID: UUID? = nil) {
        guard let wsID = wsID ?? model.workspaceID(containing: rule.nodeID) ?? Optional(model.selectedWorkspace.id) else { return }
        model.mutateWorkspace(wsID) { $0.loops.append(rule) }
        ruleStarted[rule.id] = Date()
        refreshRows()
    }

    func replace(_ rule: LoopRule) {
        mutate(rule.id) { $0 = rule }
        reset(rule.id)
        refreshRows()
    }

    func rule(_ id: UUID) -> LoopRule? {
        for ws in model.state.workspaces { if let r = ws.loops.first(where: { $0.id == id }) { return r } }
        return nil
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        mutate(id) { r in
            r.enabled = on
            if on { r.runCount = 0 }
        }
        if on { reset(id); notes[id] = nil }
        refreshRows()
    }

    func remove(_ id: UUID) {
        for ws in model.state.workspaces where ws.loops.contains(where: { $0.id == id }) {
            model.mutateWorkspace(ws.id) { $0.loops.removeAll { $0.id == id } }
        }
        reset(id)
        refreshRows()
    }

    private func reset(_ id: UUID) {
        for k in runtimes.keys where k.rule == id { runtimes[k] = nil }
        ruleStarted[id] = Date()
        lastRound[id] = nil
    }

    private func mutate(_ id: UUID, _ body: (inout LoopRule) -> Void) {
        for ws in model.state.workspaces {
            if let i = ws.loops.firstIndex(where: { $0.id == id }) {
                model.mutateWorkspace(ws.id) { body(&$0.loops[i]) }
                return
            }
        }
    }

    private func workspace(of id: UUID) -> Workspace? { model.state.workspaces.first { $0.loops.contains { $0.id == id } } }

    /// 지금 바로 한 번 보낸다(목록의 ▶). 명령·에이전트 목표가 있으면 타이머 때와 같이 먼저 판정한다.
    func runNow(_ id: UUID) {
        guard let r = rule(id), let ws = workspace(of: id), !checking.contains(id) else { return }
        let targets = r.targets(in: ws)
        switch r.goalMode ?? "text" {
        case "command", "agent":
            check(r, ws: ws) { [weak self] met in
                guard let self else { return }
                if met {
                    self.mutate(id) { $0.enabled = false }
                    self.notes[id] = "goal met at \(Self.time(Date()))"
                } else {
                    self.deliver(r, to: targets, at: Date())
                }
                self.refreshRows()
            }
        default:
            deliver(r, to: targets, at: Date())
        }
    }

    // MARK: 실행

    private func tick() {
        let now = Date()
        for ws in model.state.workspaces {
            for rule in ws.loops {
                let targets = rule.targets(in: ws)
                for nid in targets { attachListener(rule.id, nid) }
                guard rule.enabled else { continue }
                if rule.background == false && ws.id != model.selectedWorkspace.id { continue }
                if checking.contains(rule.id) { continue }
                let started = ruleStarted[rule.id] ?? now
                ruleStarted[rule.id] = started
                var fired: [UUID] = []
                var stop: String?
                for nid in targets {
                    guard let session = model.sessions.session(for: nid) else { continue }
                    let key = Key(rule: rule.id, node: nid)
                    var rt = runtimes[key] ?? LoopRuntime(startedAt: started)
                    let d = LoopEngine.evaluate(rule: rule, runtime: &rt, now: now, idleSeconds: session.idleSeconds(now: now),
                                                lastOutputAt: session.tracker.lastOutput)
                    runtimes[key] = rt
                    switch d {
                    case .fire: if session.running { fired.append(nid) }
                    case .stop(let reason): stop = reason
                    case .none: break
                    }
                }
                if let reason = stop {
                    mutate(rule.id) { $0.enabled = false }
                    notes[rule.id] = reason == "goal" ? "goal reached at \(Self.time(now))" : "stopped: \(reason)"
                    continue
                }
                guard !fired.isEmpty else { continue }
                switch rule.goalMode ?? "text" {
                case "command", "agent":
                    check(rule, ws: ws) { [weak self] met in
                        guard let self else { return }
                        if met {
                            self.mutate(rule.id) { $0.enabled = false }
                            self.notes[rule.id] = "goal met at \(Self.time(Date()))"
                        } else {
                            self.deliver(rule, to: fired, at: Date())
                        }
                        self.refreshRows()
                    }
                default:
                    deliver(rule, to: fired, at: now)
                }
            }
        }
        refreshRows()
    }

    private func attachListener(_ ruleID: UUID, _ nid: UUID) {
        guard let session = model.sessions.session(for: nid), session.outputListeners[ruleID] == nil else { return }
        session.outputListeners[ruleID] = { [weak self] text in
            guard let self else { return }
            let key = Key(rule: ruleID, node: nid)
            guard var rt = self.runtimes[key] else { return }
            rt.pending += text
            if rt.pending.count > 8000 { rt.pending = String(rt.pending.suffix(4000)) }
            self.runtimes[key] = rt
        }
    }

    private func deliver(_ rule: LoopRule, to ids: [UUID], at now: Date) {
        var sent = 0
        for id in ids {
            guard let s = model.sessions.session(for: id), s.running else { continue }
            s.sendText(rule.message, submit: true)
            sent += 1
        }
        guard sent > 0 else { return }
        mutate(rule.id) { $0.runCount += 1 }
        lastRound[rule.id] = now
        notes[rule.id] = "sent to \(sent) at \(Self.time(now))"
    }

    /// 목표 판정. 명령은 프로젝트 폴더에서 돌려 종료 코드 0 이면 달성, 에이전트는 CLI 에 YES/NO 를 묻는다.
    private func check(_ rule: LoopRule, ws: Workspace, done: @escaping (Bool) -> Void) {
        checking.insert(rule.id)
        notes[rule.id] = "checking goal..."
        let cwd = ws.projectPath ?? NSHomeDirectory()
        let finish: (Bool) -> Void = { [weak self] met in
            self?.checking.remove(rule.id)
            done(met)
        }
        if rule.goalMode == "command" {
            let cmd = rule.goalCommand ?? ""
            guard !cmd.isEmpty else { finish(false); return }
            let shell = ProcessEnvironment.userShell
            Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: shell)
                p.arguments = ["-lc", cmd]
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                var code: Int32 = -1
                if (try? p.run()) != nil { p.waitUntilExit(); code = p.terminationStatus }
                let passed = code == 0
                await MainActor.run { finish(passed) }
            }
            return
        }
        let screens = rule.targets(in: ws).compactMap { id -> String? in
            guard let s = model.sessions.session(for: id), let n = model.node(id) else { return nil }
            return "### \(n.title)\n" + String(s.recentText.suffix(3000))
        }.joined(separator: "\n\n")
        let prompt = """
        Decide whether this goal has been met, judging only from the recent terminal output below.
        Goal: \(rule.goal)

        \(screens)

        Answer with YES or NO as the first word, then one short reason.
        """
        let job = AgentJob(.init(agent: rule.goalAgent ?? "claude", prompt: prompt, cwd: cwd, tools: ""))
        job.onDone = { text, ok in finish(ok && AgentStreamParser.verdict(text) == true) }
        jobs[rule.id] = job
        job.start()
    }

    private var jobs: [UUID: AgentJob] = [:]

    func refreshRows() {
        let now = Date()
        var out: [LoopRow] = []
        for ws in model.state.workspaces {
            for r in ws.loops {
                let targets = r.targets(in: ws)
                let title = r.targetAll == true ? "All consoles" : targets.compactMap { id in ws.nodes.first { $0.id == id }?.title }.joined(separator: ", ")
                let next = LoopSummary.secondsUntilNext(r, startedAt: ruleStarted[r.id] ?? now, lastFired: lastRound[r.id], now: now)
                out.append(LoopRow(id: r.id, name: r.name ?? "Loop", nodeTitle: title, message: r.message, trigger: LoopSummary.when(r.trigger),
                                   summary: LoopSummary.sentence(r, consoleCount: targets.count), enabled: r.enabled,
                                   runs: "\(r.runCount)/\(r.maxRuns)", runCount: r.runCount, note: notes[r.id] ?? "",
                                   nextIn: next.map { Int($0.rounded(.up)) }, checking: checking.contains(r.id)))
            }
        }
        if out != rows { rows = out }
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
