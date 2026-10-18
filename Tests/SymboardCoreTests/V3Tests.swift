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
