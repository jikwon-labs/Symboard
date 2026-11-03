import Foundation
import Testing
@testable import SymboardCore

@Suite struct ConsoleWebLinksTests {
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
