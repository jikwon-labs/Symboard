import Foundation
import Testing
@testable import SymboardCore

@Suite struct PlacementTests {
    @Test func keepsFrameThatTouchesNothing() {
        let f = Rect(x: 0, y: 0, w: 100, h: 100)
        #expect(CanvasLayout.nearestFree(f, avoiding: [Rect(x: 500, y: 500, w: 50, h: 50)]) == f)
    }

    @Test func pushesBelowWhenThatIsNearest() {
        let o = Rect(x: 0, y: 0, w: 400, h: 300)
        let f = Rect(x: 50, y: 250, w: 200, h: 200)
        let r = CanvasLayout.nearestFree(f, avoiding: [o], gap: 20)
        #expect(r == Rect(x: 50, y: 320, w: 200, h: 200))
    }

    @Test func findsGapBetweenTwoObstacles() {
        // 왼쪽 그룹과 오른쪽 오케스트레이터 사이 틈(폭 300)에 200 짜리가 들어간다.
        let left = Rect(x: 0, y: 0, w: 400, h: 600), right = Rect(x: 700, y: 0, w: 400, h: 600)
        let f = Rect(x: 350, y: 100, w: 200, h: 150)
        let r = CanvasLayout.nearestFree(f, avoiding: [left, right], gap: 20)
        #expect(r.x == 420 && r.y == 100)
    }

    @Test func resultNeverOverlapsAnyObstacle() {
        let obs = [Rect(x: 0, y: 0, w: 300, h: 300), Rect(x: 320, y: 0, w: 300, h: 300), Rect(x: 0, y: 320, w: 620, h: 200)]
        let f = Rect(x: 100, y: 100, w: 500, h: 330)
        let r = CanvasLayout.nearestFree(f, avoiding: obs, gap: 24)
        for o in obs {
            #expect(!(r.x < o.x + o.w + 24 && o.x < r.x + r.w + 24 && r.y < o.y + o.h + 24 && o.y < r.y + r.h + 24))
        }
    }

    @Test func groupMembersBecomeOneFrameWithHeader() {
        let t = Team(name: "group 1")
        let a = BoardNode(kind: .terminal, frame: Rect(x: 100, y: 100, w: 200, h: 100), title: "a", teamID: t.id)
        let b = BoardNode(kind: .terminal, frame: Rect(x: 320, y: 100, w: 200, h: 100), title: "b", teamID: t.id)
        let c = BoardNode(kind: .orchestrator, frame: Rect(x: 0, y: 400, w: 100, h: 100), title: "o")
        let obs = CanvasLayout.obstacles(nodes: [a, b, c], teams: [t])
        #expect(obs.count == 2)
        #expect(obs.contains(Rect(x: 86, y: 56, w: 448, h: 158)))
    }
}
