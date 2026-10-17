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
