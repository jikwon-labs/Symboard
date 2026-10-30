import Foundation
import Testing
@testable import SymboardCore

@Suite struct ShiftEnterTests {
    func bytes(_ code: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false) -> [UInt8]? {
        KeyInput.editBytes(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
    }

    @Test func shiftEnterIsNewline() {
        #expect(bytes(36, shift: true) == [0x1b, 0x0d])
        #expect(bytes(76, shift: true) == [0x1b, 0x0d])     // 키패드 Enter
        #expect(bytes(36) == nil)                           // 그냥 Enter 는 보내기
        #expect(bytes(36, opt: true) == nil)                // Option+Enter 는 SwiftTerm(Meta) 그대로
        #expect(bytes(36, cmd: true, shift: true) == nil)
        #expect(bytes(36, ctrl: true, shift: true) == nil)
    }
}
