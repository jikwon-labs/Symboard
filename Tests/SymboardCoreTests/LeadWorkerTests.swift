import Foundation
import Testing
@testable import SymboardCore

@Suite struct LeadWorkerTests {
    @Test func roleFollowsOpenerAndSetting() {
        #expect(BoardTools.role(openedByAgent: false, leadDelegates: true) == .lead)
        #expect(BoardTools.role(openedByAgent: true, leadDelegates: true) == .worker)
        #expect(BoardTools.role(openedByAgent: true, leadDelegates: false) == .worker)
        #expect(BoardTools.role(openedByAgent: false, leadDelegates: false) == .plain)
    }

    @Test func leadDelegatesPrefDefaultsOn() {
        let prefs = Prefs(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(BoardTools.leadDelegates(prefs))
        BoardTools.setLeadDelegates(false, prefs)
        #expect(!BoardTools.leadDelegates(prefs))
        BoardTools.setLeadDelegates(true, prefs)
        #expect(prefs.string(BoardTools.leadKey) == nil)
    }

    @Test func promptsSayWhoDoesTheWork() {
        let lead = BoardTools.systemPrompt(for: .lead)
        #expect(lead.contains("lead console") && lead.contains("spawn_console") && lead.contains("built-in subagents"))
        let worker = BoardTools.systemPrompt(for: .worker)
        #expect(worker.contains("Do the work yourself") && worker.contains("Do not open more consoles"))
        #expect(BoardTools.systemPrompt(for: .plain) == BoardTools.systemPrompt)
        for p in [lead, worker, BoardTools.systemPrompt] { #expect(p.contains("add_note") && p.contains("limit") && !p.contains("\\\n")) }
    }

    @Test func launchArgsCarryRolePrompt() {
        let c = BoardTools.claudeArgs(configPath: "/tmp/x.json", role: .worker)
        #expect(c.last == BoardTools.workerPrompt)
        let x = BoardTools.codexArgs(serverPath: "/a", socketPath: "/s", nodeID: UUID(), role: .lead)
        #expect(x[1] == "developer_instructions=\(BoardTools.tomlString(BoardTools.leadPrompt))")
    }

    @Test func openedByAgentDecodesFromOldState() throws {
        let old = #"{"agent":"claude","extraArgs":[],"cwd":"/tmp","hasLaunched":true}"#
        let spec = try JSONDecoder().decode(TerminalSpec.self, from: Data(old.utf8))
        #expect(spec.openedByAgent == nil)
        var s = spec; s.openedByAgent = true
        let back = try JSONDecoder().decode(TerminalSpec.self, from: JSONEncoder().encode(s))
        #expect(back.openedByAgent == true)
    }

    @Test func belowSlotFillsRowUnderReference() {
        let lead = Rect(x: 0, y: 0, w: 640, h: 400)
        let first = CanvasLayout.belowSlot(w: 640, h: 400, reference: lead, obstacles: [lead])
        #expect(first.x == 0 && first.y == 440)
        let second = CanvasLayout.belowSlot(w: 640, h: 400, reference: lead, obstacles: [lead, first])
        #expect(second.y == 440 && second.x == 680)
        // 줄이 차면 그 아래 줄 왼쪽부터.
        let row = (0..<3).map { Rect(x: Double($0) * 680, y: 440, w: 640, h: 400) }
        let next = CanvasLayout.belowSlot(w: 640, h: 400, reference: lead, obstacles: [lead] + row, maxRowWidth: 2100)
        #expect(next.x == 0 && next.y == 880)
    }

    @Test func quitConfirmPrefDefaultsOn() {
        let prefs = Prefs(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(UIPrefs.confirmQuit(prefs))
        UIPrefs.setConfirmQuit(false, prefs)
        #expect(!UIPrefs.confirmQuit(prefs))
    }

    @Test func resumeAskPrefDefaultsOff() {
        let prefs = Prefs(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(!UIPrefs.askResume(prefs))
        UIPrefs.setAskResume(true, prefs)
        #expect(UIPrefs.askResume(prefs))
        UIPrefs.setAskResume(false, prefs)
        #expect(!UIPrefs.askResume(prefs))
    }

    // MARK: worker 가 끝나면 lead 에 알리기

    @Test func finishedCountCountsEvenWhenSeenAtOnce() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var t = StatusTracker(usesHooks: true, startedAt: t0)
        t.noteHook(.working, at: t0)
        _ = t.resolve(now: t0.addingTimeInterval(1))
        t.noteHook(.idle, at: t0.addingTimeInterval(2))
        // 사용자가 그 콘솔을 보고 있어 Done 이 바로 풀려도 끝난 횟수는 남는다.
        t.acknowledge()
        _ = t.resolve(now: t0.addingTimeInterval(3))
        #expect(t.finishedCount == 1)
        _ = t.resolve(now: t0.addingTimeInterval(4))
        #expect(t.finishedCount == 1)
        t.noteHook(.working, at: t0.addingTimeInterval(5))
        _ = t.resolve(now: t0.addingTimeInterval(6))
        t.noteHook(.waiting, at: t0.addingTimeInterval(7))
        _ = t.resolve(now: t0.addingTimeInterval(8))
        #expect(t.finishedCount == 1)
        t.noteHook(.idle, at: t0.addingTimeInterval(9))
        _ = t.resolve(now: t0.addingTimeInterval(10))
        #expect(t.finishedCount == 2)
    }

    @Test func parentConsoleSkipsCards() {
        let lead = UUID(), card = UUID(), a = UUID(), b = UUID(), orphan = UUID()
        let links = [
            NodeLink(from: lead, to: a, style: NodeLink.spawnedStyle),
            NodeLink(from: a, to: card, style: NodeLink.handoffStyle),
            NodeLink(from: card, to: b, style: NodeLink.handoffStyle),
            NodeLink(from: lead, to: orphan, style: "arrow"),
        ]
        let consoles: Set<UUID> = [lead, a, b, orphan]
        #expect(WorkerReport.parentConsole(of: a, links: links) { consoles.contains($0) } == lead)
        #expect(WorkerReport.parentConsole(of: b, links: links) { consoles.contains($0) } == a)
        #expect(WorkerReport.parentConsole(of: lead, links: links) { consoles.contains($0) } == nil)
        #expect(WorkerReport.parentConsole(of: orphan, links: links) { consoles.contains($0) } == nil)
        let loop = [NodeLink(from: a, to: b, style: NodeLink.spawnedStyle), NodeLink(from: b, to: a, style: NodeLink.spawnedStyle)]
        #expect(WorkerReport.parentConsole(of: a, links: loop) { _ in false } == nil)
    }

    @Test func noticeNamesWorkersAndTellsLeadToRead() {
        let one = WorkerReport.notice(workers: ["api-fix"])
        #expect(one.hasPrefix(WorkerReport.tag) && one.contains("read_console(\"api-fix\")") && !one.contains("\n"))
        let two = WorkerReport.notice(workers: ["a", "b"])
        #expect(two.contains("\"a\", \"b\"") && two.contains("Consoles"))
        #expect(BoardTools.leadPrompt.contains(WorkerReport.tag) && BoardTools.workerPrompt.contains("tells the lead"))
    }

    @Test func deliverOnlyWhenLeadIsFreeAndHasNoDraft() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorkerReport.canDeliver(leadStatus: .idle, leadIdleSince: t, lastUserKey: nil))
        #expect(WorkerReport.canDeliver(leadStatus: .done, leadIdleSince: t, lastUserKey: t.addingTimeInterval(-5)))
        // 쉬기 시작한 뒤에 쳤으면 쓰다 만 글이 있을 수 있다.
        #expect(!WorkerReport.canDeliver(leadStatus: .idle, leadIdleSince: t, lastUserKey: t.addingTimeInterval(5)))
        for st: NodeStatus? in [.working, .waiting, .starting, .exited, nil] {
            #expect(!WorkerReport.canDeliver(leadStatus: st, leadIdleSince: t, lastUserKey: nil))
        }
    }

    @Test func queueGroupsPerLeadOnce() {
        let lead = UUID(), other = UUID(), a = UUID(), b = UUID()
        var q = WorkerReport.Queue()
        q.add(worker: a, lead: lead)
        q.add(worker: b, lead: lead)
        q.add(worker: a, lead: lead)
        q.add(worker: b, lead: other)
        #expect(q.pending[lead] == [a, b])
        q.prune { $0 != other }
        #expect(q.pending[other] == nil)
        #expect(q.take(lead: lead) == [a, b])
        #expect(q.take(lead: lead).isEmpty && q.isEmpty)
    }

    @Test func reportPrefDefaultsOn() {
        let prefs = Prefs(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(WorkerReport.enabled(prefs))
        WorkerReport.setEnabled(false, prefs)
        #expect(!WorkerReport.enabled(prefs))
        WorkerReport.setEnabled(true, prefs)
        #expect(prefs.string(WorkerReport.prefKey) == nil)
    }
}
