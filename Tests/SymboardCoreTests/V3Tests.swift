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
