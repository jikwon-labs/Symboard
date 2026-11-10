import Foundation

/// 터미널이 프로그램으로 보내는 바이트 가운데 "사용자가 친 글이 아닌 것"을 가려낸다.
/// 마우스 보고·초점 보고·질의에 대한 자동 응답은 키 입력과 같은 길로 나가지만 입력창에 글을 남기지 않는다.
/// lead 알림이 "쓰다 만 글" 을 볼 때 이것들을 친 것으로 세면, 마우스만 지나가도 알림이 막힌다.
public enum TerminalReport {
    /// 덩어리 전체가 보고·응답으로만 이루어졌으면 true. 하나라도 키 입력이 섞였으면 false.
    public static func isReportOnly<S: Sequence>(_ data: S) -> Bool where S.Element == UInt8 {
        let b = Array(data)
        guard !b.isEmpty else { return true }
        var i = 0
        while i < b.count {
            guard let next = skipReport(b, from: i) else { return false }
            i = next
        }
        return true
    }

    /// i 에서 시작하는 보고 하나를 지나간 자리. 보고가 아니면 nil.
    private static func skipReport(_ b: [UInt8], from i: Int) -> Int? {
        guard b[i] == 0x1b, i + 1 < b.count else { return nil }
        switch b[i + 1] {
        case UInt8(ascii: "]"), UInt8(ascii: "P"):
            // OSC·DCS 응답(색 질의 등). BEL 또는 ESC \ 로 끝난다. 키 입력은 이 머리로 시작하지 않는다.
            var j = i + 2
            while j < b.count {
                if b[j] == 0x07 { return j + 1 }
                if b[j] == 0x1b, j + 1 < b.count, b[j + 1] == UInt8(ascii: "\\") { return j + 2 }
                j += 1
            }
            return b.count
        case UInt8(ascii: "["):
            return skipCSI(b, from: i + 2)
        default:
            return nil
        }
    }

    /// "ESC [" 뒤(i)부터 CSI 하나를 읽어, 보고이면 지나간 자리를 낸다.
    private static func skipCSI(_ b: [UInt8], from start: Int) -> Int? {
        guard start < b.count else { return nil }
        // X10 마우스: ESC [ M 뒤에 버튼·x·y 세 바이트.
        if b[start] == UInt8(ascii: "M") { return start + 4 <= b.count ? start + 4 : nil }
        var j = start
        // 매개변수(0x30–0x3F)와 중간 바이트(0x20–0x2F).
        while j < b.count, (0x20...0x3f).contains(b[j]) { j += 1 }
        guard j < b.count, (0x40...0x7e).contains(b[j]) else { return nil }
        let params = b[start..<j]
        let final = b[j]
        let prefix = params.first
        let bare = params.isEmpty
        let isReport: Bool
        switch final {
        case UInt8(ascii: "I"), UInt8(ascii: "O"):
            // 초점 들어옴·나감.
            isReport = bare
        case UInt8(ascii: "M"), UInt8(ascii: "m"):
            // SGR 마우스(ESC [ < b;x;y M/m)와 urxvt 마우스(ESC [ b;x;y M).
            isReport = prefix == UInt8(ascii: "<") || (final == UInt8(ascii: "M") && !bare)
        case UInt8(ascii: "R"):
            // 커서 위치 응답(ESC [ y;x R). "1;2R" 꼴은 Shift+F3 같은 키와 겹쳐서 친 것으로 둔다.
            let looksLikeKey = params.count == 3 && params.starts(with: Array("1;".utf8))
            isReport = !bare && !looksLikeKey
        case UInt8(ascii: "n"), UInt8(ascii: "c"), UInt8(ascii: "t"), UInt8(ascii: "y"):
            // 상태·장치 속성·창 크기·모드 질의 응답.
            isReport = true
        case UInt8(ascii: "u"):
            // kitty 키보드 질의 응답(ESC [ ? flags u). 접두 글자가 없으면 키 입력이다.
            isReport = prefix == UInt8(ascii: "?")
        default:
            isReport = false
        }
        return isReport ? j + 1 : nil
    }
}
