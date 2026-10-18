import AppKit
import SymboardCore

/// 넘겨주기 진행. 요청을 보낸 뒤 보내는 노드가 다시 쉬면 답을 읽어 받는 노드에 넣는다.
@MainActor
final class HandoffCoordinator {
    unowned let model: AppModel

    struct Job {
        var source: UUID
        var target: UUID
        var startedAt: Date
        var sawWork = false
        /// 확인 창 없이 바로 보낸다(자동 확인용).
        var autoSend: Bool
    }

    private var jobs: [Job] = []
    private var observer: NSObjectProtocol?
    /// 마지막 결과를 사람이 읽을 수 있게 남긴다.
    private(set) var lastResult = ""

    init(model: AppModel) {
        self.model = model
        observer = NotificationCenter.default.addObserver(forName: .statusTick, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// 노드 메뉴에서 부른다: 받을 노드를 고르고 요청을 보낸다.
    func begin(from source: UUID) {
        guard let src = model.node(source) else { return }
        let targets = model.state.workspaces.flatMap(\.nodes).filter { $0.kind == .terminal && $0.id != source }
        guard !targets.isEmpty else {
            let a = NSAlert()
            a.messageText = "Add another terminal node to hand off to."
            a.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Hand off \"\(src.title)\""
        alert.informativeText = "Symboard asks this node's CLI to summarize its work, then types the summary into the node you pick. You can edit it before it is sent."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItems(withTitles: targets.map { n in n.role.map { "\($0) - \(n.title)" } ?? n.title })
        let note = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        note.placeholderString = "Extra instruction for the summary (optional)"
        let stack = NSStackView(views: [popup, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Ask for Summary")
        alert.addButton(withTitle: "Cancel")
        guard Prompt.run(alert, focus: note) == .alertFirstButtonReturn else { return }
        start(source: source, target: targets[popup.indexOfSelectedItem].id, note: note.stringValue, autoSend: false)
    }

    func start(source: UUID, target: UUID, note: String, autoSend: Bool) {
        guard let s = model.sessions.session(for: source), s.running else { return }
        s.clearRecentText()
        s.sendText(Handoff.request(note: note), submit: true)
        jobs.removeAll { $0.source == source }
        jobs.append(Job(source: source, target: target, startedAt: Date(), autoSend: autoSend))
        lastResult = "waiting"
    }

    private func tick() {
        let now = Date()
        var keep: [Job] = []
        for var job in jobs {
            guard let s = model.sessions.session(for: job.source) else { continue }
            let status = s.currentStatus(now: now)
            if status == .working { job.sawWork = true }
            let age = now.timeIntervalSince(job.startedAt)
            if age > 600 { lastResult = "timeout"; continue }
            // 일을 시작했다가 다시 쉬거나 입력을 기다리면 답이 끝난 것으로 본다.
            let finished = age > 4 && job.sawWork && (status == .idle || status == .waiting || status == .exited)
            guard finished else { keep.append(job); continue }
            // 기록 파일이 늦게 써질 수 있어 한 번 더 기다렸다가 읽는다.
            let j = job
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.deliver(j) }
        }
        jobs = keep
    }

    private func readSummary(_ job: Job) -> String? {
        guard let node = model.node(job.source), let spec = node.terminal else { return nil }
        var reply: String?
        let profile = spec.profileID.flatMap { id in model.state.profiles.first { $0.id == id } }
        switch spec.agent {
        case .claude:
            if let sid = spec.sessionID {
                let base = (profile?.agent == .claude ? profile?.configDir : nil) ?? NSHomeDirectory() + "/.claude"
                let path = "\(base)/projects/\(LaunchPlanner.claudeProjectDirName(for: LaunchPlanner.resolvedPath(spec.cwd)))/\(sid).jsonl"
                reply = (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(Handoff.claudeLastReply)
            }
        case .codex:
            if let sid = spec.sessionID {
                let root = CodexSessions.sessionsRoot(configDir: profile?.agent == .codex ? profile?.configDir : nil)
                reply = CodexSessions.file(root: root, id: sid)
                    .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.flatMap(Handoff.codexLastReply)
            }
        default:
            break
        }
        // 기록이 없으면 화면 출력에서 표시 사이를 찾는다.
        let screen = model.sessions.session(for: job.source)?.recentText ?? ""
        if let r = reply { return Handoff.extractMarked(r) ?? r }
        return Handoff.extractMarked(screen)
    }

    private func deliver(_ job: Job) {
        guard let src = model.node(job.source) else { return }
        guard let summary = readSummary(job) else {
            lastResult = "no summary found"
            let a = NSAlert()
            a.messageText = "Could not read a summary from \"\(src.title)\"."
            a.informativeText = "The node finished replying but no summary text was found. You can copy it by hand."
            if !job.autoSend { a.runModal() }
            return
        }
        var text = Handoff.message(from: src.title, summary: summary)
        if !job.autoSend {
            guard let edited = Prompt.multiline(title: "Send handoff", message: "Edit before sending to \"\(model.node(job.target)?.title ?? "")\".", value: text) else {
                lastResult = "cancelled"
                return
            }
            text = edited
        }
        guard let target = model.sessions.session(for: job.target), target.running else { lastResult = "target not running"; return }
        target.sendText(text, submit: true)
        lastResult = "sent: \(summary.prefix(200))"
    }
}
