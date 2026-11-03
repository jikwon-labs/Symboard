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
}
