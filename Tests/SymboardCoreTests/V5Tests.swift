import Foundation
import Testing
@testable import SymboardCore

@Suite struct LoginPathTests {
    let b = LoginPath.beginMarker, e = LoginPath.endMarker

    @Test func parsesPathBetweenMarkersIgnoringNoise() {
        let out = "Last login: Sun\n[ERROR]: gitstatus failed to initialize.\n\u{1B}[32mexec zsh\u{1B}[39m\n"
            + "\(b)/Users/me/.nvm/versions/node/v24.17.0/bin:/usr/bin:/bin\(e)\nbye\n"
        #expect(LoginPath.parse(out) == "/Users/me/.nvm/versions/node/v24.17.0/bin:/usr/bin:/bin")
    }

    @Test func takesLastMarkedBlockWhenRcEchoesMarkers() {
        let out = "\(b)junk\(e)\n\(b)/opt/homebrew/bin:/usr/bin\(e)"
        #expect(LoginPath.parse(out) == "/opt/homebrew/bin:/usr/bin")
    }

    @Test func rejectsMissingOrEmptyOrBrokenOutput() {
        #expect(LoginPath.parse("") == nil)
        #expect(LoginPath.parse("no markers here /usr/bin") == nil)
        #expect(LoginPath.parse("\(b)\(e)") == nil)
        #expect(LoginPath.parse("\(b)/usr/bin") == nil)               // 끝 표식 없음(잘림)
        #expect(LoginPath.parse("\(b)/usr/bin\nsomething\(e)") == nil) // 줄바꿈이 섞임
    }

    @Test func mergeKeepsOrderAndDropsDuplicates() {
        #expect(LoginPath.merge(["/a:/b::/a", "/c:/b"]) == "/a:/b:/c")
    }

    @Test func shellSuccessPutsShellPathFirst() {
        let r = LoginPath.resolve(shellOutput: "\(b)/n/bin:/usr/bin\(e)", currentPath: "/usr/bin:/bin:/usr/sbin:/sbin",
                                  home: "/h", nvmBin: nil) { _ in true }
        #expect(r.fromShell)
        #expect(r.path == "/n/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func timeoutOrFailureFallsBackToExistingCommonDirs() {
        let present: Set<String> = ["/h/.nvm/versions/node/v24.17.0/bin", "/opt/homebrew/bin", "/h/.local/bin"]
        let r = LoginPath.resolve(shellOutput: nil, currentPath: "/usr/bin:/bin", home: "/h",
                                  nvmBin: "/h/.nvm/versions/node/v24.17.0/bin") { present.contains($0) }
        #expect(!r.fromShell)
        #expect(r.path == "/h/.nvm/versions/node/v24.17.0/bin:/h/.local/bin:/opt/homebrew/bin:/usr/bin:/bin")
        // 표식 없는 잡음만 온 경우도 실패로 본다.
        let r2 = LoginPath.resolve(shellOutput: "zsh: command not found: compdef", currentPath: "/usr/bin", home: "/h",
                                   nvmBin: nil) { $0 == "/h/.volta/bin" }
        #expect(!r2.fromShell)
        #expect(r2.path == "/h/.volta/bin:/usr/bin")
    }

    @Test func nvmPicksDefaultAliasOrNewest() {
        let vs = ["v18.20.1", "v24.17.0", "v24.9.0", "v20.1.0", ".DS_Store"]
        #expect(LoginPath.nvmBin(home: "/h", defaultAlias: "24\n", versions: vs) == "/h/.nvm/versions/node/v24.17.0/bin")
        #expect(LoginPath.nvmBin(home: "/h", defaultAlias: "v18", versions: vs) == "/h/.nvm/versions/node/v18.20.1/bin")
        #expect(LoginPath.nvmBin(home: "/h", defaultAlias: "lts/*", versions: vs) == "/h/.nvm/versions/node/v24.17.0/bin")
        #expect(LoginPath.nvmBin(home: "/h", defaultAlias: nil, versions: []) == nil)
    }

    @Test func whichSearchesPathInOrder() {
        let exe: Set<String> = ["/b/claude", "/c/claude"]
        #expect(LoginPath.which("claude", path: "/a:/b:/c", isExecutable: exe.contains) == "/b/claude")
        #expect(LoginPath.which("codex", path: "/a:/b", isExecutable: exe.contains) == nil)
    }

    @Test func probeReturnsNoisyOutputFromRealShell() {
        let out = LoginPath.runProbe(shell: "/bin/sh",
                                     arguments: ["-c", "echo noise; echo err >&2; printf '%s%s%s' '\(b)' '/x/bin:/usr/bin' '\(e)'; echo trailing"],
                                     timeout: 5)
        #expect(out.flatMap(LoginPath.parse) == "/x/bin:/usr/bin")
    }

    @Test func probeStopsAtMarkerEvenIfShellKeepsRunning() {
        let t = Date()
        let out = LoginPath.runProbe(shell: "/bin/sh", arguments: ["-c", "printf '%s/y%s' '\(b)' '\(e)'; sleep 10"], timeout: 5)
        #expect(out.flatMap(LoginPath.parse) == "/y")
        #expect(Date().timeIntervalSince(t) < 3)
    }

    @Test func probeTimesOutWhenShellHangs() {
        let t = Date()
        let out = LoginPath.runProbe(shell: "/bin/sh", arguments: ["-c", "echo hello; sleep 10"], timeout: 0.5)
        #expect(out == nil)
        #expect(Date().timeIntervalSince(t) < 3)
    }

    @Test func probeFailsForMissingShell() {
        #expect(LoginPath.runProbe(shell: "/nonexistent/shell", arguments: [], timeout: 1) == nil)
    }
}
