import Foundation
import Testing
@testable import SymboardCore

/// 성능 점검 2차: 같은 커서 다시 걸기 거르기, 확대·축소가 멎었는지 보는 시계.
@Suite struct SmoothnessTests {
    @Test func cursorDedupeSkipsSameCursorWithinWindow() {
        var d = CursorDedupe<Int>()
        #expect(d.shouldSkip(1, isCurrent: false, now: 0) == false)   // 처음은 건다
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.01) == true)  // 같은 커서, 바로 뒤
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.2) == true)   // 건너뛴 것은 시각을 늦추지 않는다
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.26) == false) // 마지막으로 실제로 건 지 0.25초가 지나면 다시 건다
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.3) == true)
    }

    @Test func cursorDedupeAlwaysAppliesDifferentOrNotCurrent() {
        var d = CursorDedupe<Int>()
        _ = d.shouldSkip(1, isCurrent: false, now: 0)
        #expect(d.shouldSkip(2, isCurrent: true, now: 0.01) == false) // 다른 커서
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.02) == false) // 다시 바뀜
        // 지금 걸린 커서가 아니라고 하면(바깥에서 바뀜) 같은 커서라도 건다.
        #expect(d.shouldSkip(1, isCurrent: false, now: 0.03) == false)
    }

    @Test func cursorDedupeResetForcesNextApply() {
        var d = CursorDedupe<Int>()
        _ = d.shouldSkip(1, isCurrent: false, now: 0)
        d.reset()
        #expect(d.shouldSkip(1, isCurrent: true, now: 0.01) == false)
    }

    @Test func quietTimerReportsStartAndQuiet() {
        var q = QuietTimer(quiet: 0.18)
        #expect(q.isQuiet(now: 0))
        #expect(q.poke(now: 1.0) == true)      // 조용하다가 처음 움직임
        #expect(q.poke(now: 1.05) == false)    // 이어지는 움직임
        #expect(!q.isQuiet(now: 1.1))
        #expect(abs(q.remaining(now: 1.1) - 0.13) < 1e-9)
        #expect(q.isQuiet(now: 1.24))
        #expect(q.remaining(now: 2) == 0)
        #expect(q.poke(now: 2.0) == true)      // 멎은 뒤 다시 시작
    }
}
