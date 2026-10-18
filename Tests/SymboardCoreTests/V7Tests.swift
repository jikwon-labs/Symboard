import Foundation
import Testing
@testable import SymboardCore

/// 7차: 입력칸 @ 자동완성(좁히기·넣기·색칠 범위)과 빈칸 든 그룹 이름 대상.
@Suite struct MentionTests {
    let names = ["Ada", "Pip", "Maya", "Iris", "all", "group 1"]

    @Test func atAloneOpensWithEmptyQuery() {
        #expect(Mention.active(in: "@", cursor: 1, names: names) == .init(range: NSRange(location: 0, length: 1), query: ""))
        #expect(Mention.filter(names, query: "") == names)
    }

    @Test func narrowsByPrefixIgnoringCase() {
        #expect(Mention.filter(names, query: "p") == ["Pip"])
        #expect(Mention.filter(names, query: "MA") == ["Maya"])
        #expect(Mention.filter(names, query: "a") == ["Ada", "all"])
        #expect(Mention.filter(names, query: "zz").isEmpty)
    }

    @Test func activeOnlyInLeadingTargetRun() {
        // 두 번째 @ 도 맨 앞 대상 줄이면 목록을 띄운다.
        #expect(Mention.active(in: "@Ada @p", cursor: 7, names: names)?.query == "p")
        // 본문이 시작된 뒤의 @ 는 대상이 아니다.
        #expect(Mention.active(in: "@Ada echo @p", cursor: 12, names: names) == nil)
        #expect(Mention.active(in: "echo @p", cursor: 7, names: names) == nil)
        // 이름 뒤에 빈칸을 친 뒤에는 목록이 없다.
        #expect(Mention.active(in: "@Pip ", cursor: 5, names: names) == nil)
        // 커서가 토큰 가운데여도 커서 앞까지가 질문이다.
        #expect(Mention.active(in: "@Pip", cursor: 2, names: names)?.query == "P")
    }

    @Test func groupNameWithSpaceStaysActive() {
        #expect(Mention.active(in: "@group ", cursor: 7, names: names)?.query == "group ")
        #expect(Mention.filter(names, query: "group ") == ["group 1"])
        #expect(Mention.active(in: "@foo ", cursor: 5, names: names) == nil)
    }

    @Test func insertReplacesTokenAndAddsOneSpace() {
        let r = Mention.insert("Pip", into: "@p", replacing: NSRange(location: 0, length: 2))
        #expect(r.text == "@Pip " && r.cursor == 5)
        let r2 = Mention.insert("Maya", into: "@Ada @ echo", replacing: NSRange(location: 5, length: 1))
        #expect(r2.text == "@Ada @Maya echo" && r2.cursor == 11)
        // 커서 뒤에 붙은 같은 토큰 나머지도 바꾼다.
        let r3 = Mention.insert("Pip", into: "@Pxx", replacing: NSRange(location: 0, length: 2))
        #expect(r3.text == "@Pip " && r3.cursor == 5)
        let r4 = Mention.insert("group 1", into: "@gr", replacing: NSRange(location: 0, length: 3))
        #expect(r4.text == "@group 1 ")
    }

    @Test func highlightsKnownLeadingNamesOnly() {
        #expect(Mention.highlights(in: "@Pip echo hi", names: names) == [NSRange(location: 0, length: 4)])
        #expect(Mention.highlights(in: "@ada @Maya echo two", names: names) == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 5)])
        // 없는 이름은 칠하지 않고, 거기서 대상 줄이 끝난다.
        #expect(Mention.highlights(in: "@Bob @Ada x", names: names).isEmpty)
        // 앞부분만 같은 다른 낱말은 아니다.
        #expect(Mention.highlights(in: "@Adam hi", names: names).isEmpty)
        // 본문 중간의 @ 는 칠하지 않는다.
        #expect(Mention.highlights(in: "echo @Ada", names: names).isEmpty)
        #expect(Mention.highlights(in: "@group 1 ls", names: names) == [NSRange(location: 0, length: 8)])
        #expect(Mention.highlights(in: "@all, hi", names: names) == [NSRange(location: 0, length: 4)])
    }

    @Test func hangulAfterMentionUsesUTF16Ranges() {
        let t = "@Iris 안녕"
        #expect(Mention.highlights(in: t, names: names) == [NSRange(location: 0, length: 5)])
        #expect(Mention.active(in: t, cursor: (t as NSString).length, names: names) == nil)
    }
}

@Suite struct MultiWordTargetTests {
    let a = UUID(), b = UUID(), c = UUID()
    var cands: [CommandTargets.Candidate] {
        [.init(id: a, name: "Ada", team: "Group 1"), .init(id: b, name: "Pip", team: "Group 1"), .init(id: c, name: "Iris", team: nil)]
    }

    @Test func groupWithSpace() {
        let r = CommandTargets.parse("@group 1 ls -la", candidates: cands)
        #expect(r.nodeIDs == [a, b] && r.body == "ls -la" && r.unknown.isEmpty)
    }

    @Test func severalTargets() {
        let r = CommandTargets.parse("@Ada @Iris echo two", candidates: cands)
        #expect(r.nodeIDs == [a, c] && r.body == "echo two")
    }

    @Test func groupWithTrailingComma() {
        let r = CommandTargets.parse("@Group 1, @Iris hi", candidates: cands)
        #expect(r.nodeIDs == [a, b, c] && r.body == "hi")
    }
}
