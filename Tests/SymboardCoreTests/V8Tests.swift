import Testing
@testable import SymboardCore

@Suite struct BesideSlotTests {
    @Test func emptyBoardHasNoSlot() {
        #expect(CanvasLayout.besideSlot(w: 640, h: 400, reference: nil, obstacles: []) == nil)
    }

    @Test func goesRightOfReferenceOnSameRow() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: a, obstacles: [a])
        #expect(r == Rect(x: 680, y: 0, w: 640, h: 400))
    }

    @Test func skipsPastNodesAlreadyOnTheRight() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400), b = Rect(x: 680, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: a, obstacles: [a, b])
        #expect(r == Rect(x: 1360, y: 0, w: 640, h: 400))
    }

    @Test func fullRowWrapsToNextRowLeft() {
        let a = Rect(x: 0, y: 0, w: 640, h: 400), b = Rect(x: 680, y: 0, w: 640, h: 400), c = Rect(x: 1360, y: 0, w: 640, h: 400)
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: c, obstacles: [a, b, c])
        #expect(r == Rect(x: 0, y: 440, w: 640, h: 400))
    }

    @Test func resultNeverOverlaps() {
        let obs = [Rect(x: 0, y: 0, w: 640, h: 400), Rect(x: 700, y: 100, w: 300, h: 300), Rect(x: 0, y: 450, w: 2000, h: 200)]
        let r = CanvasLayout.besideSlot(w: 640, h: 400, reference: obs[0], obstacles: obs)!
        for o in obs {
            #expect(!(r.x < o.x + o.w && o.x < r.x + r.w && r.y < o.y + o.h && o.y < r.y + r.h))
        }
    }
}
