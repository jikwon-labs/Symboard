import Foundation
import Testing
@testable import SymboardCore

@Suite struct ConsoleWebLinksTests {
    @Test func leadDoesNotReopenAPageItsWorkerAlreadyShows() {
        let lead = UUID(), card = UUID(), worker = UUID(), stranger = UUID()
        let workerTile = UUID(), strangerTile = UUID()
        let url = "https://claude.ai/artifact/abc"
        let links = [
            NodeLink(from: lead, to: card, style: NodeLink.handoffStyle),
            NodeLink(from: card, to: worker, style: NodeLink.handoffStyle),
            NodeLink(from: worker, to: workerTile, style: ConsoleWebLinks.linkStyle),
            NodeLink(from: stranger, to: strangerTile, style: ConsoleWebLinks.linkStyle),
        ]
        let tabs: (UUID) -> [String]? = { id in
            id == workerTile ? ["http://localhost:3000", url + "/"] : id == strangerTile ? ["https://example.com/only"] : nil
        }
        #expect(ConsoleWebLinks.family(of: lead, links: links) == [lead, card, worker])
        // 하위 콘솔이 띄운 주소를 부모가 다시 말하면 그 타일의 그 탭을 가리킨다(끝의 / 차이는 같은 주소).
        let hit = ConsoleWebLinks.familyTile(showing: url, from: lead, links: links, tabs: tabs)
        #expect(hit?.tile == workerTile && hit?.tab == 1)
        // 자기 타일은 여기서 보지 않는다(원래 길로 같은 탭을 고른다). 무리 밖 콘솔의 타일도 보지 않는다.
        #expect(ConsoleWebLinks.familyTile(showing: url, from: worker, links: links, tabs: tabs) == nil)
        #expect(ConsoleWebLinks.familyTile(showing: "https://example.com/only", from: lead, links: links, tabs: tabs) == nil)
        #expect(ConsoleWebLinks.familyTile(showing: "https://claude.ai/artifact/other", from: lead, links: links, tabs: tabs) == nil)
        #expect(!ConsoleWebLinks.sameAddress("", ""))
    }

    @Test func findsURLsAndTrimsPunctuation() {
        let text = """
        서버를 띄웠습니다: http://localhost:3000/dashboard.
        PR 은 **https://github.com/a/b/pull/12** 입니다, 문서는 [여기](https://docs.example.com/x?y=1) 참고.
        위키 https://en.wikipedia.org/wiki/Swift_(language) 와 (https://example.com/p) 도.
        다시 http://localhost:3000/dashboard
        """
        #expect(ConsoleWebLinks.urls(in: text) == [
            "http://localhost:3000/dashboard",
            "https://github.com/a/b/pull/12",
            "https://docs.example.com/x?y=1",
            "https://en.wikipedia.org/wiki/Swift_(language)",
            "https://example.com/p",
        ])
        #expect(ConsoleWebLinks.urls(in: "https:// 만 있음") == [])
    }

    @Test func clickOnURLInLine() {
        let line = "  ⏺ 열기: http://localhost:5173/app 확인"
        let i = Array(line).firstIndex(of: "5")!
        #expect(ConsoleWebLinks.url(at: i, in: line, known: []) == "http://localhost:5173/app")
        // 주소 밖 글자.
        #expect(ConsoleWebLinks.url(at: 3, in: line, known: []) == nil)
        #expect(ConsoleWebLinks.url(at: 100, in: line, known: []) == nil)
    }

    @Test func clickOnWrappedPieceUsesKnownURL() {
        let full = "https://github.com/someone/some-repo/pull/1234/files"
        let known = ["https://other.example.com", full]
        // 줄 끝에서 잘린 앞부분.
        let first = "    https://github.com/someone/some-r"
        #expect(ConsoleWebLinks.url(at: 10, in: first, known: known) == full)
        // 다음 줄로 넘어간 뒷부분.
        let second = "    epo/pull/1234/files"
        #expect(ConsoleWebLinks.url(at: 6, in: second, known: known) == full)
        // 너무 짧은 조각은 추측하지 않는다.
        #expect(ConsoleWebLinks.url(at: 0, in: "s", known: known) == nil)
    }

    @Test func bareLocalhost() {
        let line = "Local: localhost:8080/admin"
        #expect(ConsoleWebLinks.url(at: 10, in: line, known: []) == "http://localhost:8080/admin")
    }

    @Test func rememberKeepsRecentLast() {
        var known = ["a", "b"]
        ConsoleWebLinks.remember(["a", "c"], in: &known)
        #expect(known == ["b", "a", "c"])
        var many: [String] = []
        ConsoleWebLinks.remember((0..<(ConsoleWebLinks.knownLimit + 5)).map(String.init), in: &many)
        #expect(many.count == ConsoleWebLinks.knownLimit)
        #expect(many.first == "5")
    }
}
