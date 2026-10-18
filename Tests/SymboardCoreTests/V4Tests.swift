import Foundation
import Testing
@testable import SymboardCore

/// 실제 claude 2.1.302 · codex 0.157.1 화면에서 옮겨 온 글자 표본.
enum ScreenSamples {
    static let claudeTrust = """
     Accessing workspace:

     /private/tmp/symtrust-1

     Quick safety check: Is this a project you created or one you trust? (Like your
     own code, a well-known open source project, or work from your team). If not, take
     a moment to review what's in this folder first.

     Claude Code'll be able to read, edit, and execute files here.

     Security guide

     ❯ No, exit
       Yes, I trust this folder

     Enter to confirm · Esc to cancel
    """
    static let codexTrust = """
      Folder access
      /private/tmp/symtrust-2

      Trust this folder? Codex can read, edit, and run files here, subject to your
      permission settings.

    › 1. Trust and continue
      2. Quit

      enter continue · esc quit
    """
    static let codexUpdate = """
      Update available · 0.157.1 → 0.163.0

    › 1. Update now (runs `npm install -g @openai/codex`)
      2. Skip
      3. Skip until next version

      enter continue · esc skip
    """
    static let codexDaemon = """
      Background server has incompatible feature settings
      This session requires api_key_model_discovery to be disabled
      Restart will use these shared feature settings:
        api_key_model_discovery = false
      These settings persist and can disable functionality for other clients. Restart
      may interrupt active or queued work.


      1. Run without daemon this time
      2. Restart with these settings
    › 3. Cancel
    """
    static let claudePrompt = """
    ╭───────────────────────────────────────╮
    │ ✻ Welcome to Claude Code!             │
    ╰───────────────────────────────────────╯
    ⏺ The answer is 4.

    ────────────────────────────────────────
    ❯ 
    ────────────────────────────────────────
      ? for shortcuts
    """
    static let claudeAnswerWithList = """
    ⏺ Here are the steps:
      1. Open the file
      2. Edit it
      3. Save it

    ────────────────────────────────────────
    ❯ thanks
    ────────────────────────────────────────
      ? for shortcuts
    """
}

@Suite struct PromptDetectorTests {
    @Test func claudeTrustScreenWaits() { #expect(PromptDetector.isWaitingForChoice(ScreenSamples.claudeTrust)) }
    @Test func codexTrustScreenWaits() { #expect(PromptDetector.isWaitingForChoice(ScreenSamples.codexTrust)) }
    @Test func codexUpdateScreenWaits() { #expect(PromptDetector.isWaitingForChoice(ScreenSamples.codexUpdate)) }
    @Test func codexDaemonMenuWaits() { #expect(PromptDetector.isWaitingForChoice(ScreenSamples.codexDaemon)) }
    @Test func plainPromptIsNotWaiting() { #expect(!PromptDetector.isWaitingForChoice(ScreenSamples.claudePrompt)) }
    @Test func numberedAnswerIsNotWaiting() { #expect(!PromptDetector.isWaitingForChoice(ScreenSamples.claudeAnswerWithList)) }
    @Test func oldDialogScrolledAwayIsIgnored() {
        let screen = ScreenSamples.claudeTrust + "\n" + (1...25).map { "line \($0)" }.joined(separator: "\n")
        #expect(!PromptDetector.isWaitingForChoice(screen))
    }
}

@Suite struct DoneStateTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func screenChoiceOverridesIdleWithoutHook() {
        var t = StatusTracker(usesHooks: true, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        #expect(t.resolve(now: t0.addingTimeInterval(10), screen: ScreenSamples.claudeTrust) == .waiting)
        #expect(t.resolve(now: t0.addingTimeInterval(11), screen: ScreenSamples.claudePrompt) == .idle)
    }

    @Test func hookWorkThenStopIsDoneUntilSeen() {
        var t = StatusTracker(usesHooks: true, startedAt: t0)
        t.noteHook(.idle, at: t0)
        #expect(t.resolve(now: t0.addingTimeInterval(1)) == .idle)
        t.noteInput(at: t0.addingTimeInterval(2))
        t.noteHook(.working, at: t0.addingTimeInterval(2))
        #expect(t.resolve(now: t0.addingTimeInterval(3)) == .working)
        t.noteHook(.waiting, at: t0.addingTimeInterval(4))
        #expect(t.resolve(now: t0.addingTimeInterval(5)) == .waiting)
        t.noteHook(.working, at: t0.addingTimeInterval(6))
        #expect(t.resolve(now: t0.addingTimeInterval(7)) == .working)
        t.noteHook(.idle, at: t0.addingTimeInterval(8))
        #expect(t.resolve(now: t0.addingTimeInterval(9)) == .done)
        #expect(t.resolve(now: t0.addingTimeInterval(20)) == .done)
        t.acknowledge()
        #expect(t.resolve(now: t0.addingTimeInterval(21)) == .idle)
    }

    @Test func newInputClearsDone() {
        var t = StatusTracker(usesHooks: true, startedAt: t0)
        t.noteHook(.working, at: t0)
        _ = t.resolve(now: t0.addingTimeInterval(1))
        t.noteHook(.idle, at: t0.addingTimeInterval(2))
        #expect(t.resolve(now: t0.addingTimeInterval(3)) == .done)
        t.noteInput(at: t0.addingTimeInterval(4))
        #expect(t.resolve(now: t0.addingTimeInterval(5)) == .idle)
    }

    @Test func bootOutputWithoutInputIsNotDone() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        for s in 0..<6 { t.noteOutput(at: t0.addingTimeInterval(Double(s))); _ = t.resolve(now: t0.addingTimeInterval(Double(s))) }
        #expect(t.resolve(now: t0.addingTimeInterval(20)) == .idle)
    }

    @Test func shortBurstAfterInputIsNotDone() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteInput(at: t0)
        t.noteOutput(at: t0.addingTimeInterval(0.5))
        _ = t.resolve(now: t0.addingTimeInterval(1))
        #expect(t.resolve(now: t0.addingTimeInterval(10)) == .idle)
    }

    @Test func longOutputAfterInputIsDone() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteInput(at: t0)
        for s in 1...5 { t.noteOutput(at: t0.addingTimeInterval(Double(s))); _ = t.resolve(now: t0.addingTimeInterval(Double(s))) }
        #expect(t.resolve(now: t0.addingTimeInterval(12)) == .done)
    }

    @Test func plainShellNeverDone() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteInput(at: t0); t.noteOutput(at: t0)
        #expect(t.resolve(now: t0.addingTimeInterval(1), shellAtPrompt: false) == .working)
        #expect(t.resolve(now: t0.addingTimeInterval(9), shellAtPrompt: false) == .working)
        #expect(t.resolve(now: t0.addingTimeInterval(10), shellAtPrompt: true) == .idle)
    }
}

@Suite struct PromptDetectorNulTests {
    /// 터미널이 한 번도 쓰지 않은 칸은 NUL 로 나온다(실제 화면에서 본 모양).
    @Test func nulSeparatedTrustScreenWaits() {
        let s = ScreenSamples.claudeTrust.replacingOccurrences(of: " ", with: "\u{0}")
        #expect(PromptDetector.isWaitingForChoice(s))
    }
}

@Suite struct PermissionModeTests {
    @Test func askReplacesAutoFlagsForClaude() {
        var spec = TerminalSpec(agent: .claude, cwd: "/tmp")
        spec.extraArgs = ["--model", "opus", "--dangerously-skip-permissions"]
        spec.extraArgs = PermissionMode.ask.apply(to: spec)
        #expect(spec.extraArgs == ["--model", "opus", "--permission-mode", "manual"])
        #expect(PermissionMode.current(for: spec) == .ask)
        #expect(PermissionMode.label(for: spec) == "ASK")
        spec.extraArgs = PermissionMode.cliDefault.apply(to: spec)
        #expect(spec.extraArgs == ["--model", "opus"] && PermissionMode.label(for: spec) == nil)
    }

    @Test func codexModes() {
        var spec = TerminalSpec(agent: .codex, cwd: "/tmp")
        spec.extraArgs = PermissionMode.ask.apply(to: spec)
        #expect(PermissionMode.current(for: spec) == .ask)
        spec.extraArgs = PermissionMode.auto.apply(to: spec)
        #expect(spec.extraArgs == ["--dangerously-bypass-approvals-and-sandbox"] && PermissionMode.label(for: spec) == "AUTO")
    }
}

@Suite struct RevealTests {
    let safe = Rect(x: 0, y: 0, w: 1000, h: 600)

    @Test func insideIsLeftAlone() {
        #expect(CanvasLayout.reveal([Rect(x: 100, y: 100, w: 200, h: 200)], in: safe, magnification: 1) == nil)
    }

    @Test func offRightEdgeCentersWithoutZoomingIn() {
        let r = CanvasLayout.reveal([Rect(x: 700, y: 100, w: 200, h: 200), Rect(x: 980, y: 160, w: 440, h: 360)], in: safe, magnification: 0.8)
        #expect(r != nil)
        #expect(r!.center.x == (700 + 1420) / 2)
        #expect(r!.zoom <= 0.8)
    }

    @Test func smallNodeKeepsZoom() {
        let r = CanvasLayout.reveal([Rect(x: 1100, y: 100, w: 200, h: 200)], in: safe, magnification: 0.5)
        #expect(r?.zoom == 0.5)
    }
}

@Suite struct KeyInputTests {
    /// 실제로 찍힌 값: 한글 입력 소스에서 Ctrl+C 는 characters [3], ignoringModifiers [12618 = ㅊ].
    @Test func koreanLayoutCtrlCSendsETX() {
        #expect(KeyInput.controlByte(control: true, command: false, option: false, characters: "\u{3}", ignoringModifiers: "\u{314A}") == 3)
    }
    @Test func englishLayoutIsLeftToSwiftTerm() {
        #expect(KeyInput.controlByte(control: true, command: false, option: false, characters: "\u{3}", ignoringModifiers: "c") == nil)
    }
    @Test func cmdOrPlainKeysAreIgnored() {
        #expect(KeyInput.controlByte(control: false, command: false, option: false, characters: "ㅊ", ignoringModifiers: "ㅊ") == nil)
        #expect(KeyInput.controlByte(control: true, command: true, option: false, characters: "\u{3}", ignoringModifiers: "ㅊ") == nil)
    }
}
