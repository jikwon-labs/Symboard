import Foundation
import Testing
@testable import SymboardCore

/// 에이전트가 띄운 하위 콘솔은 lead 좌우 같은 줄에, 한 줄에 5개까지.
struct SideSlotTests {
    let lead = Rect(x: 0, y: 0, w: 640, h: 400)

    /// lead 가 n 개를 차례로 띄웠을 때의 자리들.
    func spawn(_ n: Int, from ref: Rect, others: [Rect]) -> [Rect] {
        var own: [Rect] = []
        for _ in 0..<n {
            own.append(CanvasLayout.sideSlot(w: 640, h: 400, reference: ref, obstacles: [ref] + others + own, own: own))
        }
        return own
    }

    @Test func alternatesRightThenLeft() {
        let c = spawn(5, from: lead, others: [])
        #expect(c.map(\.x) == [680, -680, 1360, -1360, 2040])
        #expect(c.allSatisfy { $0.y == 0 })
    }

    @Test func sixthStartsNextRowUnderLead() {
        let c = spawn(8, from: lead, others: [])
        #expect(c[5].x == 0 && c[5].y == 440)
        #expect(c[6].x == 680 && c[6].y == 440)
        #expect(c[7].x == -680 && c[7].y == 440)
    }

    @Test func doesNotJumpOverOtherSession() {
        // 세션1 오른쪽의 세션2 가 띄우면 세션1 쪽(왼쪽)은 쓰지 않는다.
        let s1 = Rect(x: 0, y: 0, w: 640, h: 400), s2 = Rect(x: 680, y: 0, w: 640, h: 400)
        let c = spawn(6, from: s2, others: [s1])
        #expect(c.prefix(5).map(\.x) == [1360, 2040, 2720, 3400, 4080])
        #expect(c.prefix(5).allSatisfy { $0.y == 0 })
        #expect(c[5].x == 680 && c[5].y == 440)
        for r in c { #expect(!(r.x < s1.x + s1.w && s1.x < r.x + r.w && r.y < s1.y + s1.h && s1.y < r.y + r.h)) }
    }

    @Test func boxedInDropsBelowEarly() {
        // 양옆이 다른 세션이면 첫 하위 콘솔부터 아래 줄 lead 밑.
        let l = Rect(x: -680, y: 0, w: 640, h: 400), r = Rect(x: 680, y: 0, w: 640, h: 400)
        let c = spawn(1, from: lead, others: [l, r])
        #expect(c[0].x == 0 && c[0].y == 440)
    }
}
