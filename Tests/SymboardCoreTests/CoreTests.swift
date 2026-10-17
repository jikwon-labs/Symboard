import Foundation
import Testing
@testable import SymboardCore

@Suite struct StateStoreTests {
    @Test func roundTripKeepsNodes() throws {
        var state = AppState.initial()
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp", sessionID: "abc", hasLaunched: true)
        state.workspaces[0].nodes.append(BoardNode(kind: .terminal, frame: Rect(x: 10, y: 20, w: 300, h: 200), title: "A", terminal: spec))
        let data = try StateStore.encode(state)
        let decoded = try StateStore.decode(data)
        #expect(decoded == state)
        #expect(String(decoding: data, as: UTF8.self).contains("\"version\" : 1"))
    }

    @Test func rejectsNewerVersion() throws {
        let json = #"{"version": 99, "workspaces": [], "profiles": [], "memories": []}"#
        #expect(throws: StateStoreError.unsupportedVersion(99)) { try StateStore.decode(Data(json.utf8)) }
    }

    @Test func saveAndLoadFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = StateStore(directory: dir)
        #expect(store.load().workspaces.count == 1)
        var state = AppState.initial()
        state.workspaces.append(Workspace(name: "Second"))
        try store.save(state)
        #expect(store.load().workspaces.map(\.name) == ["Main", "Second"])
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func brokenFileIsMovedAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = StateStore(directory: dir)
        try Data("not json".utf8).write(to: store.stateURL)
        #expect(store.load().workspaces.count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("state.broken-") })
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite struct LaunchPlanTests {
    let node = UUID()

    @Test func claudeNewUsesSessionIDAndHooks() {
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp/x")
        let plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.command[0] == "claude")
        #expect(plan.command[1] == "--session-id")
        #expect(plan.sessionID != nil)
        #expect(plan.command.contains("--settings"))
        #expect(!plan.isResume)
        #expect(plan.environment["SYMBOARD_STATUS_FILE"] == "/s")
    }

    @Test func claudeResumeWhenSessionExists() {
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp/x", sessionID: "sid", hasLaunched: true)
        let plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: true, defaultShell: "/bin/zsh")
        #expect(Array(plan.command.prefix(3)) == ["claude", "--resume", "sid"])
        #expect(plan.isResume)
    }

    @Test func claudeRestartsWithSameIDWhenNoTranscript() {
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp/x", sessionID: "sid", hasLaunched: true)
        let plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(Array(plan.command.prefix(3)) == ["claude", "--session-id", "sid"])
    }

    @Test func codexResume() {
        var spec = TerminalSpec(agent: .codex, cwd: "/tmp/x", hasLaunched: true)
        var plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.command == ["codex", "resume", "--last"])
        spec.sessionID = "u-1"
        plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.command == ["codex", "resume", "u-1"])
    }

    @Test func profileSetsConfigDir() {
        let p = AccountProfile(name: "work", agent: .claude, configDir: "/tmp/cfg")
        let spec = TerminalSpec(agent: .claude, cwd: "/tmp")
        let plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: p, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.environment["CLAUDE_CONFIG_DIR"] == "/tmp/cfg")
        let cp = AccountProfile(name: "work", agent: .codex, configDir: "/tmp/c2")
        let plan2 = LaunchPlanner.plan(for: TerminalSpec(agent: .codex, cwd: "/tmp"), nodeID: node, statusFile: "/s", profile: cp, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan2.environment["CODEX_HOME"] == "/tmp/c2")
    }

    @Test func hookSettingsIsValidJSON() throws {
        let json = LaunchPlanner.claudeHookSettingsJSON()
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let hooks = obj?["hooks"] as? [String: Any]
        #expect(hooks?["Stop"] != nil)
        #expect(hooks?["UserPromptSubmit"] != nil)
        #expect((hooks?["Notification"] as? [Any])?.count == 2)
    }

    @Test func projectDirName() {
        #expect(LaunchPlanner.claudeProjectDirName(for: "/Users/a/side.b") == "-Users-a-side-b")
    }

    @Test func shellWrapping() {
        let w = LaunchPlanner.shellWrapped(["claude", "--x"], shell: "/bin/zsh")
        #expect(w.executable == "/bin/zsh")
        #expect(w.args.suffix(2) == ["claude", "--x"])
        let s = LaunchPlanner.shellWrapped(["/bin/zsh", "-l"], shell: "/bin/zsh")
        #expect(s.args == ["-l"])
    }
}

@Suite struct StatusTrackerTests {
    @Test func outputBasedInference() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var t = StatusTracker(usesHooks: false, idleAfter: 3, startedAt: t0)
        #expect(t.status(now: t0.addingTimeInterval(1)) == .starting)
        #expect(t.status(now: t0.addingTimeInterval(5)) == .idle)
        t.noteOutput(at: t0.addingTimeInterval(10))
        #expect(t.status(now: t0.addingTimeInterval(11)) == .working)
        #expect(t.status(now: t0.addingTimeInterval(14)) == .idle)
        t.noteExit()
        #expect(t.status(now: t0.addingTimeInterval(14)) == .exited)
    }

    @Test func hooksOverrideOutput() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var t = StatusTracker(usesHooks: true, idleAfter: 3, startedAt: t0)
        t.noteOutput(at: t0)
        t.noteHook(.waiting, at: t0)
        #expect(t.status(now: t0) == .waiting)
        t.noteHook(.idle, at: t0)
        #expect(t.status(now: t0) == .idle)
    }
}

@Suite struct EnvironmentTests {
    @Test func stripsInheritedClaudeSessionMarkers() {
        let env = ["CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDECODE": "1", "PATH": "/bin", "CLAUDE_CONFIG_DIR": "/x"]
        let out = LaunchPlanner.sanitized(env)
        #expect(out == ["PATH": "/bin", "CLAUDE_CONFIG_DIR": "/x"])
    }

    @Test func resolvesTmpSymlink() {
        #expect(LaunchPlanner.resolvedPath("/tmp") == "/private/tmp")
    }
}

@Suite struct ComposerTests {
    @Test func gridIsClampedAndCentered() {
        let f = Composer.frames(count: 20, center: Point(x: 0, y: 0), size: (100, 50), gap: 10)
        #expect(f.count == 12)
        // 12 개 → 4열 3행
        #expect(Set(f.map(\.x)).count == 4)
        #expect(Set(f.map(\.y)).count == 3)
        let minX = f.map(\.x).min()!, maxX = f.map { $0.x + $0.w }.max()!
        #expect(abs((minX + maxX) / 2) < 0.001)
    }

    @Test func rolesPadWithNil() {
        #expect(Composer.roles(from: "Lead, Coder,, ", count: 3) == ["Lead", "Coder", nil])
    }
}

@Suite struct LoopEngineTests {
    let t0 = Date(timeIntervalSince1970: 10_000)

    @Test func intervalFiresEveryPeriod() {
        let rule = LoopRule(nodeID: UUID(), message: "go", trigger: .interval(seconds: 10))
        var rt = LoopRuntime(startedAt: t0)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(5), idleSeconds: 0, lastOutputAt: nil) == .none)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(10), idleSeconds: 0, lastOutputAt: nil) == .fire)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(15), idleSeconds: 0, lastOutputAt: nil) == .none)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(20), idleSeconds: 0, lastOutputAt: nil) == .fire)
    }

    @Test func idleWaitsForNewActivity() {
        let rule = LoopRule(nodeID: UUID(), message: "continue", trigger: .idle(seconds: 5))
        var rt = LoopRuntime(startedAt: t0)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(6), idleSeconds: 6, lastOutputAt: t0) == .fire)
        // 아무 출력이 없었으면 다시 보내지 않는다.
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(20), idleSeconds: 20, lastOutputAt: t0) == .none)
        // 출력이 있고 다시 유휴가 되면 보낸다.
        let out = t0.addingTimeInterval(22)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(28), idleSeconds: 6, lastOutputAt: out) == .fire)
    }

    @Test func outputPatternAndGoalStop() {
        let rule = LoopRule(nodeID: UUID(), message: "next please", trigger: .output(pattern: "READY"), goal: "ALL DONE")
        var rt = LoopRuntime(startedAt: t0)
        rt.pending = "...REA"
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0, idleSeconds: 0, lastOutputAt: t0) == .none)
        rt.pending += "DY>"
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(1), idleSeconds: 0, lastOutputAt: t0) == .fire)
        rt.pending += "working... all done"
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(9), idleSeconds: 0, lastOutputAt: t0) == .stop(reason: "goal"))
    }

    @Test func echoedMessageDoesNotTriggerGoal() {
        let rule = LoopRule(nodeID: UUID(), message: "say ALL DONE when finished", trigger: .interval(seconds: 100), goal: "ALL DONE")
        var rt = LoopRuntime(startedAt: t0)
        rt.pending = "> say ALL DONE when finished\n"
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(1), idleSeconds: 0, lastOutputAt: t0) == .none)
    }

    @Test func maxRunsStops() {
        let rule = LoopRule(nodeID: UUID(), message: "x", trigger: .interval(seconds: 1), maxRuns: 2, runCount: 2)
        var rt = LoopRuntime(startedAt: t0)
        #expect(LoopEngine.evaluate(rule: rule, runtime: &rt, now: t0.addingTimeInterval(5), idleSeconds: 0, lastOutputAt: nil) == .stop(reason: "max runs"))
    }
}

@Suite struct HandoffTests {
    @Test func extractSkipsEchoedRequest() {
        let text = "> " + Handoff.request(note: "") + "\nthinking...\nHANDOFF-BEGIN\nGoal: x\nLeft: y\nHANDOFF-END\n> "
        #expect(Handoff.extractMarked(text) == "Goal: x\nLeft: y")
        #expect(Handoff.extractMarked("no markers") == nil)
    }

    @Test func claudeReplyFromTranscript() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"old"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"summarize"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":""}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"..."}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"HANDOFF-BEGIN\nsum\nHANDOFF-END"}]}}"#,
        ].joined(separator: "\n")
        #expect(Handoff.claudeLastReply(jsonl: lines) == "HANDOFF-BEGIN\nsum\nHANDOFF-END")
    }

    @Test func codexReplyFromRollout() {
        let lines = [
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"first"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"second"}]}}"#,
        ].joined(separator: "\n")
        #expect(Handoff.codexLastReply(jsonl: lines) == "second")
    }
}

@Suite struct GitStatusTests {
    @Test func parsesPorcelainV2() {
        let text = """
        # branch.oid 0123
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 aaa bbb Sources/a b.swift
        2 R. N... 100644 100644 100644 aaa bbb R100 new.txt\told.txt
        ? notes.md
        """
        let s = GitStatus.parse(text)
        #expect(s.branch == "main")
        #expect(s.upstream == "origin/main")
        #expect(s.ahead == 2 && s.behind == 1)
        #expect(s.changes == [.init(code: ".M", path: "Sources/a b.swift"), .init(code: "R.", path: "new.txt"), .init(code: "??", path: "notes.md")])
    }
}

@Suite struct StudioTests {
    @Test func highlightsSwift() {
        let src = "let url = \"http://x\" // note\nreturn 42"
        let t = SyntaxHighlighter.tokens(src, language: "swift")
        let ns = src as NSString
        let pairs = t.map { (ns.substring(with: $0.range), $0.kind) }
        #expect(pairs.contains { $0.0 == "let" && $0.1 == .keyword })
        #expect(pairs.contains { $0.0 == "\"http://x\"" && $0.1 == .string })
        #expect(pairs.contains { $0.0 == "// note" && $0.1 == .comment })
        #expect(pairs.contains { $0.0 == "42" && $0.1 == .number })
        // 문자열 안의 // 는 주석이 아니다.
        #expect(!pairs.contains { $0.1 == .comment && $0.0.hasPrefix("//x") })
    }

    @Test func markdownLinksAndGraph() {
        #expect(Markdown.links(in: "See [[Plan]] and [notes](sub/Notes.md#top) and [web](https://a.md)") == ["Plan", "Notes"])
        let edges = Markdown.graph(["README": "[[plan]] [[missing]]", "plan": "back to [r](README.md)"])
        #expect(edges.map { "\($0.from)>\($0.to)" } == ["README>plan", "plan>README"])
    }

    @Test func markdownHTML() {
        let h = Markdown.html("# Title\n\nSome **bold** and `code`.\n\n- a\n- b\n\n```\nx < y\n```")
        #expect(h.contains("<h1>Title</h1>"))
        #expect(h.contains("<strong>bold</strong>"))
        #expect(h.contains("<code>code</code>"))
        #expect(h.contains("<ul><li>a</li><li>b</li></ul>"))
        #expect(h.contains("<pre><code>x &lt; y</code></pre>"))
    }

    @Test func diagramParseAndLayers() {
        let d = Diagram.parse("# flow\nUser -> App: open\nApp -> Agent -> Disk\nAgent -> App\nLonely")
        #expect(d.nodes == ["User", "App", "Agent", "Disk", "Lonely"])
        #expect(d.edges.count == 4)
        #expect(d.edges[0].label == "open")
        let layers = d.layers()
        #expect(layers.first?.contains("User") == true)
        #expect(layers.flatMap { $0 }.count == 5)
        // 순환(App -> Agent -> App)이 있어도 앞에서 뒤로 층이 놓인다.
        #expect(layers.firstIndex { $0.contains("App") }! < layers.firstIndex { $0.contains("Agent") }!)
        #expect(layers.firstIndex { $0.contains("Agent") }! < layers.firstIndex { $0.contains("Disk") }!)
    }
}

@Suite struct UsageTests {
    @Test func claudeDedupesRepeatedMessage() {
        let line = #"{"type":"assistant","timestamp":"2026-10-17T20:27:40.918Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":2,"output_tokens":120,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}"#
        let other = #"{"type":"assistant","timestamp":"2026-10-17T20:28:00.000Z","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":3,"output_tokens":5}}}"#
        var seen = Set<String>()
        let recs = UsageParser.claude(jsonl: [line, line, other].joined(separator: "\n"), fallbackDay: "x", seen: &seen)
        #expect(recs.count == 2)
        let agg = UsageParser.aggregate(recs)
        let total = agg.values.flatMap(\.values).reduce(TokenCounts(), +)
        #expect(total == TokenCounts(input: 5, output: 125, cacheRead: 100, cacheWrite: 50))
    }

    @Test func codexUsesCumulativeDeltas() {
        func ev(_ input: Int, _ cached: Int, _ out: Int) -> String {
            #"{"timestamp":"2026-10-17T20:29:36.309Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(out)}}}}"#
        }
        let recs = UsageParser.codex(jsonl: [ev(100, 40, 10), ev(100, 40, 10), ev(250, 90, 30)].joined(separator: "\n"), fallbackDay: "x")
        let total = recs.map(\.counts).reduce(TokenCounts(), +)
        #expect(total == TokenCounts(input: 160, output: 30, cacheRead: 90, cacheWrite: 0))
    }
}

@Suite struct UsageFieldTests {
    @Test func fieldExtraction() {
        let t = #"{"requestId":"req_1","message":{"id":"msg_abc","usage":{}},"timestamp":"2026-10-17T20:27:40.918Z"}"#
        #expect(UsageParser.messageID(t) == "msg_abc")
        #expect(UsageParser.field(t, "\"requestId\":\"") == "req_1")
        #expect(UsageParser.field(t, "\"timestamp\":\"") == "2026-10-17T20:27:40.918Z")
    }
}
