import Foundation
import Testing
@testable import SymboardCore

@Suite struct BesideSlotTests {
    @Test func emptyBoardHasNoSlot() {
        #expect(CanvasLayout.besideSlot(w: 640, h: 400, reference: nil, obstacles: []) == nil)
    }

    @Test func goesRightOfReferenceOnSameRow() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: a, obstacles: [a])
        #expect(r == Rect(x: 680, y: 0, w: 640, h: 400))
    }

    @Test func skipsPastNodesAlreadyOnTheRight() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400), b = Rect(x: 680, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: a, obstacles: [a, b])
        #expect(r == Rect(x: 1360, y: 0, w: 640, h: 400))
    }

    @Test func fullRowWrapsToNextRowLeft() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400), b = Rect(x: 680, y: 0, w: 640, h: 400), c = Rect(x: 1360, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: c, obstacles: [a, b, c])
        #expect(r == Rect(x: 0, y: 440, w: 640, h: 400))
    }

    @Test func resultNeverOverlaps() {
        let obs = [Rect(x: 0, y: 0, w: 640, h: 400), Rect(x: 700, y: 100, w: 300, h: 300), Rect(x: 0, y: 450, w: 2000, h: 200)]
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: obs[0], obstacles: obs)!
        for o in obs {
            #expect(!(r.x < o.x + o.w && o.x < r.x + r.w && r.y < o.y + o.h && o.y < r.y + r.h))
        }
    }
}

@Suite struct TerminalEditKeyTests {
    func bytes(_ code: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false) -> [UInt8]? {
        KeyInput.editBytes(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
    }

    @Test func optionArrowsMoveByWord() {
        #expect(bytes(123, opt: true) == [0x1b, 0x62])
        #expect(bytes(124, opt: true) == [0x1b, 0x66])
    }

    @Test func commandArrowsGoToLineEnds() {
        #expect(bytes(123, cmd: true) == [0x01])
        #expect(bytes(124, cmd: true) == [0x05])
    }

    @Test func deletes() {
        #expect(bytes(51, opt: true) == [0x1b, 0x7f])
        #expect(bytes(51, cmd: true) == [0x15])
    }

    @Test func otherCombinationsPassThrough() {
        #expect(bytes(123) == nil)                          // 그냥 ←
        #expect(bytes(51) == nil)                           // 그냥 Backspace
        #expect(bytes(123, cmd: true, opt: true) == nil)    // 둘 다
        #expect(bytes(123, cmd: true, shift: true) == nil)  // 선택 확장 키
        #expect(bytes(123, opt: true, ctrl: true) == nil)
        #expect(bytes(8, cmd: true) == nil)                 // Cmd+C
        #expect(bytes(0, cmd: true) == nil)                 // Cmd+A
    }
}

@Suite struct ConsoleOrderTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    @Test func rowsTopToBottomThenLeftToRight() {
        let items: [(id: UUID, frame: Rect)] = [
            (c, Rect(x: 0, y: 500, w: 640, h: 400)),
            (b, Rect(x: 700, y: 30, w: 640, h: 400)),   // 윗변이 조금 달라도 같은 줄
            (a, Rect(x: 0, y: 0, w: 640, h: 400)),
            (d, Rect(x: 700, y: 480, w: 640, h: 400)),
        ]
        #expect(ConsoleOrder.order(items) == [a, b, c, d])
    }

    @Test func stepWrapsAround() {
        let ids = [a, b, c, d, e]
        var cur: UUID? = a
        var seen: [UUID] = []
        for _ in 0..<5 { cur = ConsoleOrder.step(from: cur, in: ids, forward: true); seen.append(cur!) }
        #expect(seen == [b, c, d, e, a])
        #expect(ConsoleOrder.step(from: a, in: ids, forward: false) == e)
        #expect(ConsoleOrder.step(from: nil, in: ids, forward: true) == a)
        #expect(ConsoleOrder.step(from: nil, in: ids, forward: false) == e)
        #expect(ConsoleOrder.step(from: a, in: [], forward: true) == nil)
    }

    @Test func digitKeys() {
        #expect(ConsoleOrder.digit(keyCode: 18) == 1)
        #expect(ConsoleOrder.digit(keyCode: 20) == 3)
        #expect(ConsoleOrder.digit(keyCode: 25) == 9)
        #expect(ConsoleOrder.digit(keyCode: 29) == nil)   // 0 은 Actual Size
    }
}

@Suite struct TargetSplitTests {
    let ada = UUID(), pip = UUID(), maya = UUID()
    var cands: [CommandTargets.Candidate] {
        [.init(id: ada, name: "Ada", team: "Group 1"), .init(id: pip, name: "Pip", team: "Group 1"), .init(id: maya, name: "Maya", team: nil)]
    }

    @Test func eachTargetGetsItsOwnText() {
        let s = CommandTargets.split("@Ada 로그인 버그 고쳐 @Pip 테스트 돌려", candidates: cands)!
        #expect(s.deliveries == [.init(names: ["Ada"], nodeIDs: [ada], body: "로그인 버그 고쳐"),
                                 .init(names: ["Pip"], nodeIDs: [pip], body: "테스트 돌려")])
        #expect(s.missingBody.isEmpty)
    }

    @Test func adjacentNamesShareText() {
        let s = CommandTargets.split("@Ada @Maya echo two", candidates: cands)!
        #expect(s.deliveries == [.init(names: ["Ada", "Maya"], nodeIDs: [ada, maya], body: "echo two")])
        let t = CommandTargets.split("@Ada @Pip 테스트", candidates: cands)!
        #expect(t.deliveries.map(\.nodeIDs) == [[ada, pip]])
    }

    @Test func trailingNameWithoutTextIsReported() {
        let s = CommandTargets.split("@Ada 고쳐 @Pip", candidates: cands)!
        #expect(s.deliveries == [.init(names: ["Ada"], nodeIDs: [ada], body: "고쳐")])
        #expect(s.missingBody == ["Pip"])
        #expect(CommandTargets.split("@Ada", candidates: cands)!.missingBody == ["Ada"])
    }

    @Test func unknownAtStaysInText() {
        let s = CommandTargets.split("@Ada mail a@b.com and install @types/node", candidates: cands)!
        #expect(s.deliveries.map(\.body) == ["mail a@b.com and install @types/node"])
        // 알려진 이름이라도 낱말 중간(앞이 빈칸이 아님)이면 글이다.
        #expect(CommandTargets.split("@Ada ping x@Pip", candidates: cands)!.deliveries.map(\.body) == ["ping x@Pip"])
        // @Adam 은 Ada 가 아니다.
        #expect(CommandTargets.split("@Ada hi @Adam", candidates: cands)!.deliveries.map(\.body) == ["hi @Adam"])
    }

    @Test func notStartingWithKnownNameFallsBack() {
        #expect(CommandTargets.split("echo hi @Ada", candidates: cands) == nil)
        #expect(CommandTargets.split("@nobody hi", candidates: cands) == nil)
    }

    @Test func multilineTextStaysTogetherUntilNextName() {
        let s = CommandTargets.split("@Ada first line\nsecond line\n@Pip\nrun tests\n", candidates: cands)!
        #expect(s.deliveries.map(\.body) == ["first line\nsecond line", "run tests"])
    }

    @Test func groupsAllAndPunctuation() {
        let s = CommandTargets.split("@group 1, build @maya: lint", candidates: cands)!
        #expect(s.deliveries == [.init(names: ["group 1"], nodeIDs: [ada, pip], body: "build"),
                                 .init(names: ["maya"], nodeIDs: [maya], body: "lint")])
        #expect(CommandTargets.split("@all status", candidates: cands)!.deliveries.first?.nodeIDs == [ada, pip, maya])
    }

    @Test func bodyMentionsAreHighlightedAndCompleted() {
        let names = ["Ada", "Pip", "all"]
        #expect(Mention.targets(in: "@Ada fix @Pip test", names: names).map(\.location) == [0, 9])
        #expect(Mention.targets(in: "fix @Pip", names: names).isEmpty)
        #expect(Mention.activeInBody(in: "@Ada fix @P", cursor: 11, names: names)?.query == "P")
        #expect(Mention.activeInBody(in: "@Ada mail a@b", cursor: 13, names: names) == nil)
        #expect(Mention.activeInBody(in: "hi @P", cursor: 5, names: names) == nil)
    }
}

@Suite struct ShortcutCatalogTests {
    var all: [String] { ShortcutCatalog.sections.flatMap { $0.entries.map(\.keys) } }

    @Test func hasTheFourGroups() {
        #expect(ShortcutCatalog.sections.map(\.title) == ["Canvas", "Consoles", "Command bar", "Nodes and tools"])
    }

    @Test func includesThisRoundsKeys() {
        for k in ["⇧ Enter", "⇧⌘ E", "⌥ ←  /  ⌥ →", "⌘ ←  /  ⌘ →", "⌥ ⌫", "⌘ ⌫", "⌃ Tab  /  ⌃⇧ Tab", "⌘ 1 … ⌘ 9", "⇧⌘ 1", "?"] {
            #expect(all.contains(k), "missing \(k)")
        }
    }

    @Test func noDuplicateRows() {
        let ids = ShortcutCatalog.sections.flatMap { $0.entries.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }
}

@Suite struct BoardToolsTests {
    @Test func mcpConfigNamesServerSocketAndCaller() throws {
        let id = UUID()
        let json = BoardTools.mcpConfigJSON(serverPath: "/A/symboard-mcp", socketPath: "/tmp/s.sock", nodeID: id)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let server = (obj["mcpServers"] as! [String: Any])["symboard"] as! [String: Any]
        #expect(server["command"] as? String == "/A/symboard-mcp")
        let env = server["env"] as! [String: String]
        #expect(env["SYMBOARD_SOCKET"] == "/tmp/s.sock")
        #expect(env["SYMBOARD_CALLER"] == id.uuidString)
    }

    @Test func claudeLaunchGetsArgsButNotStrictConfig() {
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp")
        let extra = BoardTools.claudeArgs(configPath: "/tmp/x.mcp.json")
        let plan = LaunchPlanner.plan(for: spec, nodeID: UUID(), statusFile: "/tmp/s", profile: nil, claudeSessionExists: false,
                                      defaultShell: "/bin/zsh", claudeExtraArgs: extra)
        #expect(plan.command.contains("--mcp-config"))
        #expect(plan.command.contains("--append-system-prompt"))
        #expect(!plan.command.contains("--strict-mcp-config"))
        // 셸에는 붙지 않는다.
        let shell = LaunchPlanner.plan(for: TerminalSpec(agent: .shell, cwd: "/tmp"), nodeID: UUID(), statusFile: "/tmp/s", profile: nil,
                                       claudeSessionExists: false, defaultShell: "/bin/zsh", claudeExtraArgs: extra)
        #expect(!shell.command.contains("--mcp-config"))
    }

    @Test func settingDefaultsOnAndTurnsOff() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefs = Prefs(directory: dir)
        #expect(BoardTools.enabled(prefs))
        BoardTools.setEnabled(false, prefs)
        #expect(!BoardTools.enabled(prefs))
        BoardTools.setEnabled(true, prefs)
        #expect(BoardTools.enabled(prefs))
    }

    @Test func stdioServerAnswersHandshakeListAndCall() throws {
        let server = MCPStdioServer { tool, args in ("called \(tool) \(args["name"] as? String ?? "")", false) }
        func obj(_ s: String?) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(s!.utf8)) as! [String: Any] }
        let ini = try obj(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#))
        #expect((ini["result"] as! [String: Any])["protocolVersion"] as? String == "2025-06-18")
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        let list = try obj(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let names = ((list["result"] as! [String: Any])["tools"] as! [[String: Any]]).map { $0["name"] as! String }
        #expect(names == ["list_consoles", "spawn_console", "send_to_console", "read_console", "close_console"])
        let call = try obj(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_console","arguments":{"name":"Ada"}}}"#))
        let content = (call["result"] as! [String: Any])["content"] as! [[String: Any]]
        #expect(content.first?["text"] as? String == "called read_console Ada")
        let bad = try obj(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"nope"}"#))
        #expect((bad["error"] as! [String: Any])["code"] as? Int == -32601)
    }
}
