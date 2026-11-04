import Testing
@testable import SymboardCore

/// 콘솔 위에 끌어다 놓은 파일 경로를 터미널 입력으로 바꾸기.
@Suite struct DroppedPathsTests {
    @Test func plainPathGetsTrailingSpace() {
        #expect(DroppedPaths.terminalText(["/tmp/a.png"]) == "/tmp/a.png ")
    }

    @Test func specialCharactersAreEscaped() {
        #expect(DroppedPaths.escape("/Users/me/스크린샷 2026-11-05 (1).png") == "/Users/me/스크린샷\\ 2026-11-05\\ \\(1\\).png")
        #expect(DroppedPaths.escape("/a/it's.png") == "/a/it\\'s.png")
    }

    @Test func severalPathsJoinWithSpace() {
        #expect(DroppedPaths.terminalText(["/a b", "/c"]) == "/a\\ b /c ")
        #expect(DroppedPaths.terminalText([]) == "")
    }
}
