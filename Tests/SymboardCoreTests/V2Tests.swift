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
