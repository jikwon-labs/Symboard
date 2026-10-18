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

@Suite struct UsagePillCLITests {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    func at(_ h: Int, _ m: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = seoul
        return c.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: h, minute: m))!
    }
    let limits = [PlanLimit(name: "Current session", percent: 4, resets: "9:59pm (Asia/Seoul)"),
                  PlanLimit(name: "Current week (all models)", percent: 20, resets: "Oct 22 at 8am (Asia/Seoul)")]

    @Test func usesCLIResetAndPercentWhenFresh() {
        let d = UsagePill.display(limits: limits, readAt: at(17, 20), blockEnds: [at(22)], now: at(17, 30), timeZone: seoul)
        #expect(d == UsagePill.Display(text: "resets 9:59pm", percent: 4, fromCLI: true))
    }

    @Test func fallsBackToEstimateAfterCLIResetPassed() {
        let d = UsagePill.display(limits: limits, readAt: at(17, 20), blockEnds: [at(23)], now: at(22, 5), timeZone: seoul)
        #expect(!d.fromCLI)
        #expect(d.percent == nil)
        #expect(d.text == "resets 11:00pm")
    }

    @Test func fallsBackWhenNoCLIValue() {
        let d = UsagePill.display(limits: [], readAt: nil, blockEnds: [at(22)], now: at(17), timeZone: seoul)
        #expect(d == UsagePill.Display(text: "resets 10:00pm", percent: nil, fromCLI: false))
    }

    @Test func resetDateRollsToNextDayAndKeepsZone() {
        #expect(PlanUsageParser.resetDate("10pm (Asia/Seoul)", after: at(17), timeZone: .gmt) == at(22))
        #expect(PlanUsageParser.resetDate("2am (Asia/Seoul)", after: at(23)) == at(23).addingTimeInterval(3 * 3600))
        #expect(PlanUsageParser.resetDate("12:30pm", after: at(9), timeZone: seoul) == at(12, 30))
        #expect(PlanUsageParser.resetDate("Oct 22 at 8am (Asia/Seoul)", after: at(9)) == nil)
    }

    @Test func shortResetDropsZone() {
        #expect(PlanUsageParser.shortReset("9:59pm (Asia/Seoul)") == "9:59pm")
        #expect(PlanUsageParser.shortReset("10PM") == "10pm")
    }
}

@Suite struct CodexLimitTests {
    @Test func parsesStatusBox() {
        let screen = """
        ╭──────────────────────────────────────────────╮
        │  Account: Plus                               │
        │  5h limit:     [██████░░░░]  72% left (resets 9:01 PM)          │
        │  Weekly limit: [████████████████████]100% left (resets 5:34 PM on 25 Oct) │
        ╰──────────────────────────────────────────────╯
        """
        #expect(CodexLimitParser.parseStatus(screen) == [
            PlanLimit(name: "5h limit", percent: 28, resets: "9:01 PM"),
            PlanLimit(name: "Weekly limit", percent: 0, resets: "5:34 PM on 25 Oct"),
        ])
        #expect(PlanUsageParser.isSession("5h limit"))
    }

    @Test func ignoresScreensWithoutLimits() {
        #expect(CodexLimitParser.parseStatus("› Ask Codex to do anything\n? for shortcuts").isEmpty)
    }

    @Test func parsesLogRateLimits() {
        let log = """
        {"timestamp":"2026-10-17T20:29:36.309Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":27.0,"window_minutes":43200,"resets_at":1792768206},"secondary":{"used_percent":3.4,"window_minutes":300,"resets_at":1792700000}}}}
        {"timestamp":"2026-10-17T20:30:00.000Z","type":"response_item","payload":{}}
        """
        let r = CodexLimitParser.parseLog(log, timeZone: TimeZone(identifier: "Asia/Seoul")!)
        #expect(r.limits.map(\.name) == ["5h limit", "Monthly limit"])
        #expect(r.limits.map(\.percent) == [3, 27])
        #expect(r.limits[1].resets == "12:10 AM on 24 Oct")
        #expect(r.at != nil)
    }
}

@Suite struct UsageFileCacheTests {
    func rec(_ key: String?, _ n: Int) -> UsageRecord {
        UsageRecord(day: "2026-10-18", agent: .claude, counts: TokenCounts(input: n, output: 0, cacheRead: 0, cacheWrite: 0), key: key)
    }

    @Test func reusesUnchangedFilesAndRereadsChanged() {
        let cache = UsageFileCache()
        let t = Date(timeIntervalSince1970: 1000)
        var reads = 0
        _ = cache.records(path: "/a", stamp: .init(modified: t, size: 10)) { reads += 1; return [rec("x", 1)] }
        _ = cache.records(path: "/a", stamp: .init(modified: t, size: 10)) { reads += 1; return [rec("x", 1)] }
        #expect(reads == 1)
        let r = cache.records(path: "/a", stamp: .init(modified: t, size: 20)) { reads += 1; return [rec("x", 1), rec("y", 2)] }
        #expect(reads == 2)
        #expect(r.count == 2)
        cache.prune(keeping: [])
        _ = cache.records(path: "/a", stamp: .init(modified: t, size: 20)) { reads += 1; return [] }
        #expect(reads == 3)
    }

    @Test func mergeDropsDuplicateKeysAcrossFilesButKeepsKeyless() {
        let merged = UsageFileCache.merge([[rec("m1", 1), rec(nil, 5)], [rec("m1", 1), rec("m2", 2), rec(nil, 5)]])
        #expect(merged.map(\.counts.input) == [1, 5, 2, 5])
    }
}

@Suite struct AccountInitialsTests {
    @Test func initials() {
        #expect(AccountProfile.initials("5 Account Claude Code") == "5A")
        #expect(AccountProfile.initials("Second Account 200 plan max") == "SA")
        #expect(AccountProfile.initials("work") == "WO")
        #expect(AccountProfile.initials("") == "?")
    }
}

@Suite struct CodexDaemonTests {
    @Test func freshCodexRunsWithoutSharedDaemonUnlessUserChose() {
        let node = UUID()
        var spec = TerminalSpec(agent: .codex, cwd: "/tmp/x")
        var plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.command == ["codex", "--no-daemon"])
        spec.extraArgs = ["--remote-daemon"]
        plan = LaunchPlanner.plan(for: spec, nodeID: node, statusFile: "/s", profile: nil, claudeSessionExists: false, defaultShell: "/bin/zsh")
        #expect(plan.command == ["codex", "--remote-daemon"])
    }
}

@Suite struct BoardCommandTests {
    @Test func parsesSpokenSpawnAndSlashForm() {
        #expect(BoardCommand.parse("Can you spawn 5 claude code agents?") == .spawn(count: 5, agent: "claude"))
        #expect(BoardCommand.parse("Now spawn 2 codex agents") == .spawn(count: 2, agent: "codex"))
        #expect(BoardCommand.parse("/spawn three shells") == .spawn(count: 3, agent: "shell"))
        #expect(BoardCommand.parse("spawn") == nil)
    }

    @Test func parsesOrchestratorPresetAndClose() {
        #expect(BoardCommand.parse("Can you now put an orchestrator wire with group 1?") == .orchestrator(group: "group 1"))
        #expect(BoardCommand.parse("add an orchestrator wired to backend group") == .orchestrator(group: "backend"))
        #expect(BoardCommand.parse("Please can you put me preset 1 in the board") == .preset("1"))
        #expect(BoardCommand.parse("deploy the mixed preset") == .preset("mixed"))
        #expect(BoardCommand.parse("Thanks you very much. Can you delete the group called backend for me") == .closeGroup("backend"))
    }

    @Test func leavesOrdinaryMessagesAlone() {
        #expect(BoardCommand.parse("run the tests and tell me which one fails") == nil)
        #expect(BoardCommand.parse("fix the bug, then close the file") == nil)
        #expect(BoardCommand.parse("delete the temp file") == nil)
    }

    @Test func matchesGroups() {
        let g = ["Frontend", "Backend", "Testers"]
        #expect(BoardCommand.matchGroup("backend", in: g) == 1)
        #expect(BoardCommand.matchGroup("group 1", in: g) == 0)
        #expect(BoardCommand.matchGroup("test", in: g) == 2)
        #expect(BoardCommand.matchGroup("group 9", in: g) == nil)
    }
}
