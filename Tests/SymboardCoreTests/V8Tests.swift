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

@Suite struct TerminalEditKeyTests {
    func bytes(_ code: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false) -> [UInt8]? {
        KeyInput.editBytes(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
    }

    @Test func optionArrowsMoveByWord() {
        #expect(bytes(123, opt: true) == [0x1b, 0x62])
        #expect(bytes(124, opt: true) == [0x1b, 0x66])
    }

    @Test func commandArrowsGoToLineEnds() {
        #expect(bytes(123, cmd: true) == [0x01])
        #expect(bytes(124, cmd: true) == [0x05])
    }

    @Test func deletes() {
        #expect(bytes(51, opt: true) == [0x1b, 0x7f])
        #expect(bytes(51, cmd: true) == [0x15])
    }

    @Test func otherCombinationsPassThrough() {
        #expect(bytes(123) == nil)                          // 그냥 ←
        #expect(bytes(51) == nil)                           // 그냥 Backspace
        #expect(bytes(123, cmd: true, opt: true) == nil)    // 둘 다
        #expect(bytes(123, cmd: true, shift: true) == nil)  // 선택 확장 키
        #expect(bytes(123, opt: true, ctrl: true) == nil)
        #expect(bytes(8, cmd: true) == nil)                 // Cmd+C
        #expect(bytes(0, cmd: true) == nil)                 // Cmd+A
    }
}
