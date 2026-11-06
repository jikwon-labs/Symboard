import AppKit
import SymboardCore

/// 오른쪽 위에 뜨는 "작업 끝남" 알림 하나.
struct WorkerDoneNotice: Identifiable, Equatable {
    let id = UUID()
    let workerID: UUID
    var workerName: String
    var leadName: String?
    /// lead 에 알림을 넣었는가(아직이면 lead 가 쉴 때 넣는다).
    var delivered: Bool
    /// lead 는 쉬는데 사용자가 lead 에 쓰다 만 글이 있어 알림을 미루는 중.
    var waitingOnDraft = false
}

/// 에이전트가 연 콘솔이 일을 끝내면 연 콘솔(lead)에 한 줄 알리고, 오른쪽 위에 알림을 띄운다.
/// 상태 틱(1초)마다 MainWindowController.refreshStatuses 에서 부른다.
@MainActor
final class WorkerReporter {
    unowned let model: AppModel
    let chrome: ChromeModel
    /// 콘솔별로 마지막으로 본 끝낸 횟수. 세션을 다시 띄우면 0부터 다시 센다.
    private var seenFinished: [UUID: Int] = [:]
    private var queue = WorkerReport.Queue()
    /// 콘솔이 쉬기(idle·done) 시작한 시각. Done 이 Idle 로 풀려도(사용자가 쳐서) 다시 찍지 않는다.
    private var restSince: [UUID: Date] = [:]
    /// 알림이 저절로 닫히는 시간.
    static let noticeSeconds: TimeInterval = 12
    static let maxNotices = 3
    /// lead 에 알림 줄을 넣은 뒤 부른다(캔버스가 lead 뒤로 파동을 친다).
    var onDelivered: ((UUID) -> Void)?

    init(model: AppModel, chrome: ChromeModel) {
        self.model = model
        self.chrome = chrome
    }

    func tick() {
        let sessions = model.sessions.sessions
        let now = Date()
        for id in sessions.keys {
            let st = model.sessions.status(of: id)
            if st == .idle || st == .done {
                if restSince[id] == nil { restSince[id] = now }
            } else {
                restSince[id] = nil
            }
        }
        restSince = restSince.filter { sessions[$0.key] != nil }
        for (id, s) in sessions {
            let count = s.finishedCount
            let before = seenFinished[id] ?? 0
            seenFinished[id] = count
            guard count > before else { continue }
            finished(worker: id)
        }
        seenFinished = seenFinished.filter { sessions[$0.key] != nil }
        queue.prune { [model] in model.node($0) != nil && model.sessions.session(for: $0) != nil }
        flush()
        autoArchive(now: now)
    }

    /// 일을 끝내고 정해 둔 시간 동안 아무도 건드리지 않은 worker 를 보관한다(17차).
    private func autoArchive(now: Date) {
        guard ConsoleArchive.autoEnabled(Prefs.shared) else { return }
        let minutes = ConsoleArchive.minutes(Prefs.shared)
        let pendingWorkers = Set(queue.pending.values.joined())
        for (id, s) in model.sessions.sessions {
            guard let spec = model.node(id)?.terminal, spec.archived == nil else { continue }
            let ok = ConsoleArchive.shouldAutoArchive(openedByAgent: spec.openedByAgent == true,
                                                      status: model.sessions.status(of: id),
                                                      finishedCount: s.finishedCount,
                                                      restSince: restSince[id],
                                                      lastUserKey: s.lastUserKey,
                                                      leadPending: pendingWorkers.contains(id),
                                                      now: now, minutes: minutes)
            guard ok else { continue }
            // 사용자가 지금 그 콘솔에 글자 입력 초점을 두고 있으면 접지 않는다.
            if let w = NSApp.keyWindow, let fr = w.firstResponder as? NSView, fr === s.view || fr.isDescendant(of: s.view) { continue }
            model.sessions.archive(id, auto: true, now: now)
        }
    }

    private func finished(worker id: UUID) {
        guard let node = model.node(id), node.terminal?.openedByAgent == true,
              let wsID = model.workspaceID(containing: id),
              let ws = model.state.workspaces.first(where: { $0.id == wsID }) else { return }
        let lead = WorkerReport.parentConsole(of: id, links: ws.links ?? []) { [model] in model.node($0)?.kind == .terminal }
        let leadNode = lead.flatMap { model.node($0) }
        // 셸은 알림 글을 명령으로 돌려 버리므로 claude·codex lead 에만 넣는다.
        let leadIsAgent = leadNode?.terminal.map { $0.agent == .claude || $0.agent == .codex } ?? false
        let tell = WorkerReport.enabled(Prefs.shared) && leadIsAgent && lead.flatMap { model.sessions.session(for: $0) }?.running == true
        if tell, let lead { queue.add(worker: id, lead: lead) }
        var n = WorkerDoneNotice(workerID: id, workerName: node.title, leadName: tell ? leadNode?.title : nil, delivered: !tell)
        if tell, let lead { n.waitingOnDraft = draftBlocks(lead) }
        show(n)
        if !NSApp.isActive {
            SystemNotices.shared.post(title: L("%@ finished", n.workerName), body: Self.subtitle(n), nodeID: id)
        }
    }

    /// lead 가 쉬는데도 사용자가 쓰다 만 글 때문에 알림을 넣지 못하는가.
    private func draftBlocks(_ lead: UUID) -> Bool {
        guard let s = model.sessions.session(for: lead), s.running else { return false }
        let st = model.sessions.status(of: lead)
        guard st == .idle || st == .done else { return false }
        return !WorkerReport.canDeliver(leadStatus: st, leadIdleSince: restSince[lead], lastUserKey: s.lastUserKey)
    }

    /// 알림 둘째 줄(오른쪽 위 알림·macOS 알림 같이 쓴다).
    static func subtitle(_ n: WorkerDoneNotice) -> String {
        guard let lead = n.leadName else { return L("Click to see the report") }
        if n.delivered { return L("Told %@", lead) }
        if n.waitingOnDraft { return L("%@ has unsent text. It will be told after you send it", lead) }
        return L("Will tell %@ when it is free", lead)
    }

    private func flush() {
        for lead in queue.pending.keys {
            guard let s = model.sessions.session(for: lead), s.running else { continue }
            let ok = WorkerReport.canDeliver(leadStatus: model.sessions.status(of: lead),
                                             leadIdleSince: restSince[lead],
                                             lastUserKey: s.lastUserKey)
            guard ok else { continue }
            let workers = queue.take(lead: lead)
            let names = workers.compactMap { model.node($0)?.title }
            guard !names.isEmpty else { continue }
            s.sendText(WorkerReport.notice(workers: names), submit: true)
            onDelivered?(lead)
            for i in chrome.workerNotices.indices where workers.contains(chrome.workerNotices[i].workerID) {
                chrome.workerNotices[i].delivered = true
                chrome.workerNotices[i].waitingOnDraft = false
            }
        }
    }

    private func show(_ n: WorkerDoneNotice) {
        var list = chrome.workerNotices.filter { $0.workerID != n.workerID }
        list.append(n)
        chrome.workerNotices = Array(list.suffix(Self.maxNotices))
        let id = n.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.noticeSeconds) { [weak chrome] in
            chrome?.workerNotices.removeAll { $0.id == id }
        }
    }
}
