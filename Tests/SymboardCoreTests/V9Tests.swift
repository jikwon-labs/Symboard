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

@Suite struct AgentLimitsTests {
    let a = UUID(), b = UUID(), card = UUID(), c = UUID(), d = UUID()

    @Test func depthCountsConsolesNotCards() {
        // a(사람이 연) → b(spawned) → 카드 → c(handoff) → d(spawned)
        let links = [NodeLink(from: a, to: b, style: NodeLink.spawnedStyle),
                     NodeLink(from: b, to: card, style: NodeLink.handoffStyle),
                     NodeLink(from: card, to: c, style: NodeLink.handoffStyle),
                     NodeLink(from: c, to: d, style: NodeLink.spawnedStyle),
                     NodeLink(from: d, to: a, style: "arrow")]          // 다이어그램 화살표는 세지 않는다
        let consoles: Set<UUID> = [a, b, c, d]
        let depth = { (id: UUID) in AgentLimits.depth(of: id, links: links, isConsole: { consoles.contains($0) }) }
        #expect(depth(a) == 0)
        #expect(depth(b) == 1)
        #expect(depth(c) == 2)
        #expect(depth(d) == 3)
        #expect(AgentLimits.openedCount(consoles: Array(consoles), links: links) == 3)
    }

    @Test func cycleStops() {
        let links = [NodeLink(from: a, to: b, style: NodeLink.spawnedStyle), NodeLink(from: b, to: a, style: NodeLink.spawnedStyle)]
        #expect(AgentLimits.depth(of: a, links: links, isConsole: { _ in true }) == 1)
    }

    @Test func exceeded() {
        #expect(AgentLimits.exceeded(callerDepth: 3, opened: 0, maxDepth: 4, maxOpened: 12) == nil)
        #expect(AgentLimits.exceeded(callerDepth: 4, opened: 0, maxDepth: 4, maxOpened: 12)?.contains("chain step 5") == true)
        #expect(AgentLimits.exceeded(callerDepth: 0, opened: 12, maxDepth: 4, maxOpened: 12)?.contains("12 consoles") == true)
    }

    @Test func prefsDefaultAndChange() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefs = Prefs(directory: dir)
        #expect(AgentLimits.maxDepth(prefs) == 4 && AgentLimits.maxOpened(prefs) == 12)
        AgentLimits.setMaxDepth(7, prefs); AgentLimits.setMaxOpened(3, prefs)
        #expect(AgentLimits.maxDepth(prefs) == 7 && AgentLimits.maxOpened(prefs) == 3)
        AgentLimits.setMaxDepth(4, prefs)
        #expect(prefs.string(AgentLimits.depthKey) == nil)
    }
}

@Suite struct BoardToolsV9Tests {
    @Test func newToolsListed() {
        let names = BoardTools.toolDefinitions.compactMap { $0["name"] as? String }
        #expect(names == ["list_consoles", "spawn_console", "send_to_console", "read_console", "close_console", "hand_off", "add_note", "draw_diagram"])
        let handoff = BoardTools.toolDefinitions.first { $0["name"] as? String == "hand_off" }!
        #expect((handoff["inputSchema"] as! [String: Any])["required"] as? [String] == ["prompt"])
    }

    @Test func instructionsCoverRelayAndDrawing() {
        for word in ["hand_off", "add_note", "draw_diagram", "limit"] { #expect(BoardTools.systemPrompt.contains(word)) }
    }

    @Test func diagramArgumentsParse() throws {
        let args: [String: Any] = ["title": "Flow", "nodes": [["id": "a", "label": "A"], ["id": "b", "label": "B"]], "edges": [["from": "a", "to": "b"]]]
        let data = try JSONSerialization.data(withJSONObject: args)
        let spec = DiagramSpec.parse(String(decoding: data, as: UTF8.self))
        #expect(spec?.nodes.count == 2 && spec?.edges.count == 1)
    }
}
