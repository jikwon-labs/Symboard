import Foundation
import Testing
@testable import SymboardCore

/// 성능 점검에서 바꾼 길이 예전과 같은 결과를 내는지.
@Suite struct PerfPathTests {
    static func claudeLine(_ id: String, _ req: String, input: Int, ts: String = "2026-10-30T01:02:03.000Z") -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"\#(req)","sessionId":"s1","message":{"id":"\#(id)","model":"m","usage":{"input_tokens":\#(input),"output_tokens":1}}}"#
    }

    @Test func claudeParseFromOffsetReadsOnlyNewLines() {
        let first = [Self.claudeLine("a", "r1", input: 10), Self.claudeLine("b", "r2", input: 20)].joined(separator: "\n") + "\n"
        let more = Self.claudeLine("c", "r3", input: 30) + "\n"
        let data = Data((first + more).utf8)
        var seen = Set<String>()
        let all = UsageParser.claude(data: data, fallbackDay: "x", seen: &seen)
        #expect(all.map(\.counts.input) == [10, 20, 30])
        var seen2 = Set<String>()
        let tail = UsageParser.claude(data: data, fallbackDay: "x", seen: &seen2, from: first.utf8.count)
        #expect(tail.map(\.counts.input) == [30])
        // 줄 중간을 가리키면 그 줄 처음부터 읽는다.
        var seen3 = Set<String>()
        let mid = UsageParser.claude(data: data, fallbackDay: "x", seen: &seen3, from: first.utf8.count + 5)
        #expect(mid.map(\.counts.input) == [30])
    }

    @Test func cacheUpdateGetsPreviousEntryAndRoundTrips() throws {
        let cache = UsageFileCache()
        let t = Date(timeIntervalSince1970: 1000)
        let r1 = UsageRecord(day: "2026-10-30", agent: .claude, counts: TokenCounts(input: 1), key: "a|r1")
        _ = cache.records(path: "/a", stamp: .init(modified: t, size: 10)) { prev in
            #expect(prev == nil)
            return [r1]
        }
        var sawPrev = false
        let out = cache.records(path: "/a", stamp: .init(modified: t.addingTimeInterval(5), size: 20)) { prev in
            sawPrev = prev?.records == [r1] && prev?.stamp.size == 10
            return (prev?.records ?? []) + [UsageRecord(day: "2026-10-30", agent: .claude, counts: TokenCounts(input: 2), key: "b|r2")]
        }
        #expect(sawPrev)
        #expect(out.count == 2)
        #expect(cache.dirty)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try cache.save(to: url)
        #expect(!cache.dirty)
        let loaded = UsageFileCache()
        loaded.load(from: url)
        var reads = 0
        let again = loaded.records(path: "/a", stamp: .init(modified: t.addingTimeInterval(5), size: 20)) { _ in reads += 1; return [] }
        #expect(reads == 0)
        #expect(again == out)
    }

    @Test func stripperConcreteAndGenericAgree() {
        let bytes = Array("\u{1b}[32m안녕\u{1b}[0m hi\r\n\u{1b}]0;title\u{07}done\n\n\n\nend".utf8)
        var a = ANSIStripper(), b = ANSIStripper()
        let viaSlice = a.feed(bytes[...])
        let viaGeneric = b.feed(bytes.lazy.map { $0 })
        #expect(viaSlice == viaGeneric)
        #expect(viaSlice == "안녕 hi\n\ndone\n\n\nend")
        // 조각 경계에 걸친 한글(3바이트)도 이어 붙는다.
        var c = ANSIStripper()
        let k = Array("가".utf8)
        #expect(c.feed(k[0..<2]) == "")
        #expect(c.feed(k[2...]) == "가")
    }

    @Test func claudeReplyWithoutHumanTurnKeepsAllAssistantText() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"one"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"..."}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"two"},{"type":"text","text":"three"}]}}"#,
        ].joined(separator: "\n")
        #expect(Handoff.claudeLastReply(jsonl: lines) == "one\n\ntwo\n\nthree")
    }

    @Test func pillFormatterIsReusedPerTimeZone() {
        let tz = TimeZone(identifier: "Asia/Seoul")!
        let end = Date(timeIntervalSince1970: 1_793_433_600)  // 2026-11-01 08:00 KST 근처
        let now = end.addingTimeInterval(-60)
        let a = UsagePill.text(blockEnds: [end], now: now, timeZone: tz)
        let b = UsagePill.text(blockEnds: [end], now: now, timeZone: tz)
        #expect(a == b)
        #expect(UsagePill.formatter(tz) === UsagePill.formatter(tz))
        #expect(UsagePill.text(blockEnds: [end], now: now, timeZone: TimeZone(identifier: "UTC")!) != a)
    }
}
