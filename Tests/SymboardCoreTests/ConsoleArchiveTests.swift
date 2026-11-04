import Foundation
import Testing
@testable import SymboardCore

@Suite struct ConsoleArchiveTests {
    @Test func reportDropsClaudeInputBox() {
        let screen = """
            ⏺ Done. Tests pass (42).

              Report: fixed the parser, verified with swift test.

            ────────────────────────────────────────
            ❯
            ────────────────────────────────────────
              ? for shortcuts
            """
        let r = ConsoleArchive.report(fromTranscript: screen)
        #expect(r.hasPrefix("⏺ Done."))
        #expect(r.hasSuffix("verified with swift test."))
        #expect(!r.contains("❯") && !r.contains("shortcuts"))
    }

    @Test func reportKeepsBordersFarFromTheBottom() {
        // 보고 안의 표 경계선(아래 12줄 밖)은 자르지 않는다.
        let body = ["────────────────────"] + (1...20).map { "line \($0)" }
        let r = ConsoleArchive.report(fromTranscript: body.joined(separator: "\n"))
        #expect(r.hasPrefix("────") && r.hasSuffix("line 20"))
    }

    @Test func reportKeepsOnlyTheLastLines() {
        let text = (1...500).map { "l\($0)" }.joined(separator: "\n")
        let r = ConsoleArchive.report(fromTranscript: text)
        #expect(r.components(separatedBy: "\n").count == ConsoleArchive.reportLines)
        #expect(r.hasSuffix("l500"))
    }

    @Test func autoArchiveNeedsAFinishedQuietWorker() {
        let since = Date(timeIntervalSince1970: 1000)
        let later = since.addingTimeInterval(11 * 60)
        func ok(agent: Bool = true, status: NodeStatus? = .done, finished: Int = 1, rest: Date? = since,
                key: Date? = nil, pending: Bool = false, now: Date = later) -> Bool {
            ConsoleArchive.shouldAutoArchive(openedByAgent: agent, status: status, finishedCount: finished,
                                             restSince: rest, lastUserKey: key, leadPending: pending, now: now, minutes: 10)
        }
        #expect(ok())
        #expect(ok(status: .idle))
        #expect(!ok(agent: false))                                  // 사람이 연 콘솔
        #expect(!ok(status: .working))
        #expect(!ok(status: .waiting))
        #expect(!ok(finished: 0))                                   // 일을 받은 적 없음
        #expect(!ok(rest: nil))
        #expect(!ok(now: since.addingTimeInterval(9 * 60)))        // 아직 시간이 안 됨
        #expect(!ok(key: since.addingTimeInterval(60)))             // 쉬는 동안 사용자가 쳤다
        #expect(ok(key: since.addingTimeInterval(-60)))             // 쉬기 전에 친 것은 상관없다
        #expect(!ok(pending: true))                                 // lead 에 아직 못 알렸다
    }

    @Test func childrenFollowSpawnAndHandoffThroughCards() {
        let lead = UUID(), a = UUID(), card = UUID(), b = UUID(), grand = UUID(), other = UUID()
        let consoles: Set<UUID> = [lead, a, b, grand, other]
        let links = [
            NodeLink(from: lead, to: a, style: NodeLink.spawnedStyle),
            NodeLink(from: lead, to: card, style: NodeLink.handoffStyle),
            NodeLink(from: card, to: b, style: NodeLink.handoffStyle),
            NodeLink(from: a, to: grand, style: NodeLink.spawnedStyle),   // 손주는 a 의 하위
            NodeLink(from: lead, to: other),                              // 보통 선은 세지 않는다
        ]
        let kids = ConsoleArchive.children(of: lead, links: links) { consoles.contains($0) }
        #expect(Set(kids) == [a, b])
        #expect(ConsoleArchive.children(of: a, links: links) { consoles.contains($0) } == [grand])
    }

    @Test func summaryCountsEachKind() {
        let s = ConsoleArchive.summarize([(false, .working), (false, .starting), (false, .done), (false, .idle),
                                          (false, .waiting), (true, nil), (false, nil)])
        #expect(s == ConsoleArchive.ChildSummary(working: 2, finished: 3, archived: 1, needsYou: 1))
        #expect(s.total == 7)
    }

    @Test func archivedConsoleIsNotResumedAtLaunchAndDecodesOldState() throws {
        var spec = TerminalSpec(agent: .claude, cwd: "/tmp", sessionID: "abc", hasLaunched: true)
        #expect(ResumePolicy.canResume(spec))
        spec.archived = ArchivedConsole(at: Date(), report: "done", width: 640, height: 400)
        #expect(!ResumePolicy.canResume(spec))
        let back = try JSONDecoder().decode(TerminalSpec.self, from: JSONEncoder().encode(spec))
        #expect(back.archived?.report == "done" && back.archived?.width == 640)
        // 예전 상태 파일(archived 없음)도 읽힌다.
        let old = #"{"agent":"claude","extraArgs":[],"cwd":"/tmp","hasLaunched":true}"#
        #expect(try JSONDecoder().decode(TerminalSpec.self, from: Data(old.utf8)).archived == nil)
    }

    @Test func autoArchivePrefs() {
        let prefs = Prefs(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(ConsoleArchive.autoEnabled(prefs))
        #expect(ConsoleArchive.minutes(prefs) == ConsoleArchive.defaultMinutes)
        ConsoleArchive.setAutoEnabled(false, prefs)
        ConsoleArchive.setMinutes(30, prefs)
        #expect(!ConsoleArchive.autoEnabled(prefs) && ConsoleArchive.minutes(prefs) == 30)
        ConsoleArchive.setMinutes(ConsoleArchive.defaultMinutes, prefs)
        #expect(prefs.string(ConsoleArchive.minutesKey) == nil)
    }
}
