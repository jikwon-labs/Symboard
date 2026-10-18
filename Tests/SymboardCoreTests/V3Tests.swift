import Foundation
import Testing
@testable import SymboardCore

@Suite struct CanvasInputTests {
    /// 배율 0.51 에서 원점 (100, 500) 인 flipped 뷰의 로컬 (911, 272) 을 누른 경우:
    /// SwiftUI 가 (창 x − 원점 x, 원점 y − 창 y) 를 계산했을 때 (911, 272) 가 나와야 한다.
    @Test func flippedViewRoundTrip() {
        let p = CanvasInput.unscaledWindowPoint(localX: 911, localY: 272, originX: 100, originY: 500, flipped: true)
        #expect(p.x - 100 == 911)
        #expect(500 - p.y == 272)
    }

    @Test func unflippedView() {
        let p = CanvasInput.unscaledWindowPoint(localX: 10, localY: 20, originX: 5, originY: 5, flipped: false)
        #expect(p.x == 15 && p.y == 25)
    }
}

@Suite struct ComposerResizeTests {
    @Test func growUsesLastFillChoice() {
        // Fill all Shell 뒤 마지막 타일만 Claude 로 돌렸어도 새 타일은 Shell.
        let t = Composer.resize(tiles: ["shell", "shell", "shell", "claude"], to: 6, fill: "shell", fallback: "claude")
        #expect(t == ["shell", "shell", "shell", "claude", "shell", "shell"])
    }

    @Test func growWithoutFillUsesPreviousTile() {
        #expect(Composer.resize(tiles: ["codex"], to: 3, fill: nil, fallback: "claude") == ["codex", "codex", "codex"])
    }

    @Test func shrinkAndClamp() {
        #expect(Composer.resize(tiles: ["a", "b", "c"], to: 0, fill: nil, fallback: "x") == ["a"])
        #expect(Composer.resize(tiles: [], to: 2, fill: nil, fallback: "x") == ["x", "x"])
        #expect(Composer.resize(tiles: ["a"], to: 99, fill: nil, fallback: "x").count == Composer.maxNodes)
    }
}

@Suite struct ShellStatusTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    @Test func shellAtPromptIsReadyEvenWhilePromptRedraws() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        // 방금 출력이 있었어도(프롬프트 다시 그리기) 셸이 앞에 있으면 READY.
        #expect(t.status(now: t0.addingTimeInterval(1.5), shellAtPrompt: true) == .idle)
    }

    @Test func runningCommandIsWorkingEvenWhenQuiet() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        #expect(t.status(now: t0.addingTimeInterval(60), shellAtPrompt: false) == .working)
    }

    @Test func startingUntilFirstOutput() {
        let t = StatusTracker(usesHooks: false, startedAt: t0)
        #expect(t.status(now: t0.addingTimeInterval(0.5), shellAtPrompt: true) == .starting)
        #expect(t.status(now: t0.addingTimeInterval(5), shellAtPrompt: true) == .idle)
    }

    @Test func withoutShellInfoFallsBackToOutputTiming() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        #expect(t.status(now: t0.addingTimeInterval(2)) == .working)
        #expect(t.status(now: t0.addingTimeInterval(10)) == .idle)
    }
}
