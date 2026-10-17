import Foundation

/// 터미널 출력 바이트에서 이스케이프 시퀀스를 걷어 내고 사람이 읽는 텍스트만 남긴다.
/// 조각 경계에 걸친 UTF-8·이스케이프 시퀀스는 다음 조각까지 들고 있는다.
public struct ANSIStripper: Sendable {
    private enum Mode: Sendable { case text, esc, csi, osc, oscEsc, charset }
    private var mode: Mode = .text
    private var pending: [UInt8] = []

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var out: [UInt8] = []
        for b in bytes {
            switch mode {
            case .text:
                if b == 0x1B { mode = .esc }
                else if b == 0x0A || b == 0x09 { out.append(b) }
                else if b == 0x0D { out.append(0x0A) }
                else if b >= 0x20 && b != 0x7F { out.append(b) }
            case .esc:
                switch b {
                case UInt8(ascii: "["): mode = .csi
                case UInt8(ascii: "]"), UInt8(ascii: "P"), UInt8(ascii: "_"), UInt8(ascii: "^"): mode = .osc
                case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"): mode = .charset
                default: mode = .text
                }
            case .csi:
                if b >= 0x40 && b <= 0x7E { mode = .text }
            case .osc:
                if b == 0x07 { mode = .text } else if b == 0x1B { mode = .oscEsc }
            case .oscEsc:
                mode = (b == UInt8(ascii: "\\")) ? .text : .osc
            case .charset:
                mode = .text
            }
        }
        let all = pending + out
        // 끝에 잘린 UTF-8 문자가 있으면 다음 조각으로 넘긴다.
        var cut = all.count
        var back = 0
        while back < 4, cut - back - 1 >= 0 {
            let c = all[cut - back - 1]
            if c & 0xC0 == 0x80 { back += 1; continue }
            if c & 0x80 != 0 {
                let need = c & 0xE0 == 0xC0 ? 2 : c & 0xF0 == 0xE0 ? 3 : 4
                if back + 1 < need { cut = cut - back - 1 }
            }
            break
        }
        pending = Array(all[cut...])
        let s = String(decoding: all[..<cut], as: UTF8.self)
        // 연속 빈 줄은 하나로.
        return s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
}
