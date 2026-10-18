import Foundation
import Testing
@testable import SymboardCore

@Suite struct CommandTargetTests {
    let a = UUID(), b = UUID(), c = UUID()
    var cands: [CommandTargets.Candidate] {
        [.init(id: a, name: "Ada", team: "Backend"), .init(id: b, name: "Pip", team: "Backend"), .init(id: c, name: "Iris", team: nil)]
    }

    @Test func noMentionIsImplicit() {
        let r = CommandTargets.parse("git status", candidates: cands)
        #expect(r.implicit && r.nodeIDs.isEmpty && r.body == "git status")
    }

    @Test func namesAndTeams() {
        let r = CommandTargets.parse("@iris @backend run tests", candidates: cands)
        #expect(r.nodeIDs == [c, a, b])
        #expect(r.body == "run tests")
        #expect(!r.implicit)
    }

    @Test func allAndUnknown() {
        let r = CommandTargets.parse("@all, @nobody hi @ada", candidates: cands)
        #expect(r.nodeIDs.count == 3)
        #expect(r.unknown == ["nobody"])
        #expect(r.body == "hi @ada")
    }

    @Test func pendingMention() {
        #expect(CommandTargets.pendingMention(in: "@ad") == "ad")
        #expect(CommandTargets.pendingMention(in: "@ada fix") == nil)
    }
}

@Suite struct ProjectTests {
    @Test func inferUsesMostCommonTerminalFolder() {
        var ws = Workspace(name: "W")
        for cwd in ["/a", "/b", "/b"] {
            ws.nodes.append(BoardNode(kind: .terminal, frame: Rect(x: 0, y: 0, w: 1, h: 1), title: "t", terminal: TerminalSpec(agent: .shell, cwd: cwd)))
        }
        #expect(Projects.inferPath(for: ws, fallback: "/z") == "/b")
        #expect(Projects.inferPath(for: Workspace(name: "E"), fallback: "/z") == "/z")
    }

    @Test func oldStateDecodesWithoutProject() throws {
        let json = #"{"version":1,"workspaces":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Main","nodes":[],"viewport":{"center":{"x":0,"y":0},"zoom":1},"teams":[],"strokes":[],"loops":[]}],"profiles":[],"memories":[]}"#
        let s = try StateStore.decode(Data(json.utf8))
        #expect(s.workspaces[0].projectPath == nil)
        #expect(Projects.paths(in: s.workspaces).isEmpty)
    }
}

@Suite struct NamePoolTests {
    @Test func firstUnused() {
        #expect(NamePool.next(used: []) == "Ada")
        #expect(NamePool.next(used: ["Ada", "Pip"]) == "Maya")
        #expect(NamePool.next(used: Set(NamePool.names)) == "Ada2")
    }

    @Test func permissionBadge() {
        #expect(PermissionMode.label(for: TerminalSpec(agent: .claude, extraArgs: ["--dangerously-skip-permissions"], cwd: "/")) == "AUTO")
        #expect(PermissionMode.label(for: TerminalSpec(agent: .claude, extraArgs: ["--permission-mode", "plan"], cwd: "/")) == "PLAN")
        #expect(PermissionMode.label(for: TerminalSpec(agent: .codex, cwd: "/")) == nil)
    }
}

@Suite struct ResumePolicyTests {
    @Test func onlyLaunchedAgentsWithSession() {
        var st = AppState.initial()
        let mk = { (spec: TerminalSpec) in BoardNode(kind: .terminal, frame: Rect(x: 0, y: 0, w: 1, h: 1), title: "n", terminal: spec) }
        let a = mk(TerminalSpec(agent: .claude, cwd: "/", sessionID: "x", hasLaunched: true))
        let b = mk(TerminalSpec(agent: .claude, cwd: "/", sessionID: "y", hasLaunched: false))
        let c = mk(TerminalSpec(agent: .shell, cwd: "/", sessionID: "z", hasLaunched: true))
        let d = mk(TerminalSpec(agent: .codex, cwd: "/", sessionID: "w", hasLaunched: true))
        st.workspaces[0].nodes = [a, b, c, d]
        #expect(ResumePolicy.candidates(in: st) == [a.id, d.id])
    }
}

@Suite struct LoopV2Tests {
    @Test func sentenceAndRate() {
        var r = LoopRule(nodeID: UUID(), message: "go", trigger: .interval(seconds: 900))
        r.targetAll = true
        r.useMaxRuns = false
        r.goalMode = "agent"
        r.goal = "ALL GREEN"
        #expect(LoopSummary.sentence(r, consoleCount: 1) == "Every 15 min, the instruction is sent to every console on the board, until Claude judges the goal met.")
        #expect(LoopSummary.perHour(r, consoleCount: 1) == 4)
        r.goalMode = "command"; r.goalCommand = "swift test"; r.useMaxRuns = true; r.maxRuns = 5
        #expect(LoopSummary.sentence(r, consoleCount: 3).hasSuffix("until 5 runs or `swift test` passes."))
    }

    @Test func timeLimitStops() {
        let t0 = Date()
        var r = LoopRule(nodeID: UUID(), message: "go", trigger: .interval(seconds: 10))
        r.timeLimit = 30
        var rt = LoopRuntime(startedAt: t0)
        #expect(LoopEngine.evaluate(rule: r, runtime: &rt, now: t0.addingTimeInterval(31), idleSeconds: 0, lastOutputAt: nil) == .stop(reason: "time limit"))
    }

    @Test func targetsAllIncludesLater() {
        var ws = Workspace(name: "W")
        let a = BoardNode(kind: .terminal, frame: Rect(x: 0, y: 0, w: 1, h: 1), title: "a", terminal: TerminalSpec(agent: .shell, cwd: "/"))
        ws.nodes = [a]
        var r = LoopRule(nodeID: a.id, message: "m", trigger: .idle(seconds: 5))
        r.targetAll = true
        #expect(r.targets(in: ws) == [a.id])
        let b = BoardNode(kind: .terminal, frame: Rect(x: 0, y: 0, w: 1, h: 1), title: "b", terminal: TerminalSpec(agent: .shell, cwd: "/"))
        ws.nodes.append(b)
        #expect(r.targets(in: ws) == [a.id, b.id])
        r.targetAll = nil
        #expect(r.targets(in: ws) == [a.id])
    }
}

@Suite struct AgentStreamTests {
    @Test func claudeDeltasAndResult() {
        var p = AgentStreamParser(agent: "claude")
        #expect(p.parse(line: #"{"type":"system","subtype":"init"}"#).isEmpty)
        #expect(p.parse(line: #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}}"#) == [.text("Hel")])
        #expect(p.parse(line: #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"Read"}}}"#) == [.activity("Read")])
        // 조각을 받은 뒤의 통째 메시지는 겹치지 않게 버린다.
        #expect(p.parse(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#).isEmpty)
        #expect(p.parse(line: #"{"type":"result","subtype":"success","is_error":false,"result":"Hello"}"#) == [.done("Hello", true)])
    }

    @Test func codexItems() {
        var p = AgentStreamParser(agent: "codex")
        #expect(p.parse(line: #"{"type":"item.started","item":{"id":"1","type":"command_execution","command":"ls"}}"#) == [.activity("ls")])
        #expect(p.parse(line: #"{"type":"item.completed","item":{"id":"2","type":"agent_message","text":"Done."}}"#) == [.text("Done.")])
        #expect(p.parse(line: #"{"type":"turn.completed","usage":{}}"#) == [.done(nil, true)])
    }

    @Test func verdicts() {
        #expect(AgentStreamParser.verdict("YES - tests pass") == true)
        #expect(AgentStreamParser.verdict("\n no.") == false)
        #expect(AgentStreamParser.verdict("maybe") == nil)
    }
}

@Suite struct BoardHelperTests {
    @Test func moveCardAcrossColumnsMigratesOldCards() {
        var cols = [KanbanColumn(title: "A", cards: ["one", "two"]), KanbanColumn(title: "B")]
        let id = cols[0].allCards[0].id
        // allCards 는 매번 새 id 를 만들므로, 먼저 옮겨 둔 뒤 id 로 찾는다.
        Board.move(card: id, to: cols[1].id, at: nil, in: &cols)
        #expect(cols[0].items!.count == 2)
        let first = cols[0].items![0].id
        Board.move(card: first, to: cols[1].id, at: 0, in: &cols)
        #expect(cols[0].items!.map(\.title) == ["two"])
        #expect(cols[1].items!.map(\.title) == ["one"])
        #expect(cols[0].cards.isEmpty)
    }

    @Test func monthGridStartsMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let grid = Board.monthGrid(for: d, calendar: cal)
        #expect(grid.count == 42)
        // 2026-09-01 은 화요일 → 첫 칸은 8월 31일 월요일.
        #expect(cal.component(.day, from: grid[0]) == 31)
        #expect(cal.component(.day, from: grid[1]) == 1)
    }
}
