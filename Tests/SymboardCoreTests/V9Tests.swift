import Foundation
import Testing
@testable import SymboardCore

@Suite struct ShiftEnterTests {
    func bytes(_ code: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false) -> [UInt8]? {
        KeyInput.editBytes(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
    }

    @Test func shiftEnterIsNewline() {
        #expect(bytes(36, shift: true) == [0x1b, 0x0d])
        #expect(bytes(76, shift: true) == [0x1b, 0x0d])     // 키패드 Enter
        #expect(bytes(36) == nil)                           // 그냥 Enter 는 보내기
        #expect(bytes(36, opt: true) == nil)                // Option+Enter 는 SwiftTerm(Meta) 그대로
        #expect(bytes(36, cmd: true, shift: true) == nil)
        #expect(bytes(36, ctrl: true, shift: true) == nil)
    }
}

@Suite struct CodexBoardToolsTests {
    @Test func codexLaunchGetsConfigOverrides() {
        let id = UUID()
        let extra = BoardTools.codexArgs(serverPath: "/A B/symboard-mcp", socketPath: "/Library/Application Support/s.sock", nodeID: id)
        #expect(extra.count == 6)
        #expect(stride(from: 0, to: extra.count, by: 2).allSatisfy { extra[$0] == "-c" })
        #expect(extra[1].hasPrefix("developer_instructions=\"You are running in a console on Symboard"))
        #expect(extra[3] == "mcp_servers.symboard.command=\"/A B/symboard-mcp\"")
        #expect(extra[5] == "mcp_servers.symboard.env={SYMBOARD_SOCKET=\"/Library/Application Support/s.sock\", SYMBOARD_CALLER=\"\(id.uuidString)\"}")
        let fresh = LaunchPlanner.plan(for: TerminalSpec(agent: .codex, cwd: "/tmp"), nodeID: id, statusFile: "/tmp/s", profile: nil,
                                       claudeSessionExists: false, defaultShell: "/bin/zsh", codexExtraArgs: extra)
        #expect(Array(fresh.command.suffix(6)) == extra)
        var resumed = TerminalSpec(agent: .codex, cwd: "/tmp")
        resumed.hasLaunched = true
        let again = LaunchPlanner.plan(for: resumed, nodeID: id, statusFile: "/tmp/s", profile: nil,
                                       claudeSessionExists: false, defaultShell: "/bin/zsh", codexExtraArgs: extra)
        #expect(again.command.starts(with: ["codex", "resume"]))
        #expect(Array(again.command.suffix(6)) == extra)
        // claude·셸에는 붙지 않는다.
        let shell = LaunchPlanner.plan(for: TerminalSpec(agent: .shell, cwd: "/tmp"), nodeID: id, statusFile: "/tmp/s", profile: nil,
                                       claudeSessionExists: false, defaultShell: "/bin/zsh", codexExtraArgs: extra)
        #expect(!shell.command.contains("-c"))
    }

    @Test func tomlStringEscapes() {
        #expect(BoardTools.tomlString("a \"b\" \\ c\nd") == "\"a \\\"b\\\" \\\\ c\\nd\"")
    }
}

@Suite struct SocketPathTests {
    @Test func shortDirectoryKeepsBridgeSock() {
        #expect(BoardTools.socketPath(directory: "/Users/a/Library/Application Support/Symboard", temporary: "/tmp/")
                == "/Users/a/Library/Application Support/Symboard/bridge.sock")
    }

    @Test func longDirectoryMovesToTemporaryWithStableName() {
        let long = "/private/tmp/" + String(repeating: "x", count: 120)
        let a = BoardTools.socketPath(directory: long, temporary: "/var/folders/T/")
        #expect(a.hasPrefix("/var/folders/T/symboard-") && a.hasSuffix(".sock"))
        #expect(a.utf8.count < 104)
        #expect(a == BoardTools.socketPath(directory: long, temporary: "/var/folders/T/"))
        #expect(a != BoardTools.socketPath(directory: long + "y", temporary: "/var/folders/T/"))
    }
}
