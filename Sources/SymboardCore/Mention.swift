import Foundation

/// 입력칸 @ 자동완성과 색칠 계산. 위치는 모두 UTF-16 단위(NSString·NSTextView 와 같은 단위)다.
///
/// 대상으로 보는 @ 는 `CommandTargets.parse` 와 같이 "맨 앞에 이어 붙은 @ 토큰" 뿐이다.
/// 본문 중간의 @(예: claude 에 보내는 `@file`)는 목록도 띄우지 않고 색칠도 하지 않는다.
public enum Mention {
    /// 지금 커서 바로 앞에서 쓰고 있는 @ 토큰. `range` 는 @ 부터 커서까지, `query` 는 @ 뒤 글자.
    public struct Active: Equatable, Sendable {
        public var range: NSRange
        public var query: String
        public init(range: NSRange, query: String) { self.range = range; self.query = query }
    }

    /// 커서 앞의 @ 토큰을 찾는다. 그 @ 앞이 모두 알려진 @대상과 빈칸이어야 한다(맨 앞 대상 줄).
    /// `names` 는 알려진 이름(콘솔·all·그룹). 그룹처럼 빈칸이 든 이름도 `query` 에 빈칸째 들어간다.
    public static func active(in text: String, cursor: Int, names: [String]) -> Active? {
        let ns = text as NSString
        guard cursor >= 0, cursor <= ns.length else { return nil }
        // 맨 앞 대상 줄에서 끝까지 쓴 이름들을 먼저 건너뛴다.
        var i = 0
        while true {
            i = skipSpaces(ns, from: i)
            guard i < cursor, ns.character(at: i) == at else { return nil }
            if let len = matchedName(ns, nameStart: i + 1, names: names), i + 1 + len <= cursor {
                let after = i + 1 + len
                // 완성된 이름 뒤에 빈칸이 있으면 다음 토큰으로 넘어간다. 바로 커서면 아직 쓰는 중이다.
                if after < cursor, isSpace(ns.character(at: after)) {
                    i = after
                    continue
                }
                if after == cursor { return Active(range: NSRange(location: i, length: cursor - i), query: ns.substring(with: NSRange(location: i + 1, length: len))) }
            }
            // 여기 @ 가 지금 쓰는 토큰이다. 커서까지 사이에 빈칸이 있으면 알려진 이름의 앞부분일 때만 이어 본다.
            let q = ns.substring(with: NSRange(location: i + 1, length: cursor - i - 1))
            if q.contains(where: { $0.isWhitespace }) {
                let lq = q.lowercased()
                guard names.contains(where: { $0.lowercased().hasPrefix(lq) }) else { return nil }
            }
            return Active(range: NSRange(location: i, length: cursor - i), query: q)
        }
    }

    /// 앞부분 일치(대소문자 무시)로 좁힌 이름. 순서는 `names` 그대로.
    public static func filter(_ names: [String], query: String) -> [String] {
        let q = query.lowercased()
        return names.filter { $0.lowercased().hasPrefix(q) }
    }

    /// `active` 자리를 `@이름 ` 으로 바꾼 글과 새 커서 위치. 뒤에 이미 빈칸이 있으면 하나만 둔다.
    public static func insert(_ name: String, into text: String, replacing range: NSRange) -> (text: String, cursor: Int) {
        let ns = text as NSString
        var end = NSMaxRange(range)
        // 커서 뒤에 붙어 있던 같은 토큰의 나머지 글자는 함께 바꾼다(`@P|ip` 에서 고르면 `@Pip`).
        while end < ns.length, !isSpace(ns.character(at: end)) { end += 1 }
        let hasSpace = end < ns.length && isSpace(ns.character(at: end))
        let piece = "@" + name + (hasSpace ? "" : " ")
        let out = ns.replacingCharacters(in: NSRange(location: range.location, length: end - range.location), with: piece)
        let cursor = range.location + (piece as NSString).length + (hasSpace ? 1 : 0)
        return (out, cursor)
    }

    /// 색칠할 범위: 맨 앞 대상 줄에서 알려진 이름으로 끝까지 쓴 `@이름` 들(@ 포함).
    /// 이름 뒤는 빈칸·글 끝·`,`·`:` 이어야 한다(`@Adam` 은 Ada 가 아니다).
    public static func highlights(in text: String, names: [String]) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var i = 0
        while true {
            i = skipSpaces(ns, from: i)
            guard i < ns.length, ns.character(at: i) == at else { return out }
            guard let len = matchedName(ns, nameStart: i + 1, names: names) else { return out }
            out.append(NSRange(location: i, length: len + 1))
            var j = i + 1 + len
            while j < ns.length, [comma, colon].contains(ns.character(at: j)) { j += 1 }
            i = j
        }
    }

    /// `nameStart` 부터 가장 길게 맞는 알려진 이름의 길이. 이름 뒤가 경계가 아니면 맞지 않는 것으로 본다.
    public static func matchedName(_ ns: NSString, nameStart: Int, names: [String]) -> Int? {
        var best: Int?
        for n in names {
            let len = (n as NSString).length
            guard len > 0, nameStart + len <= ns.length else { continue }
            let piece = ns.substring(with: NSRange(location: nameStart, length: len))
            guard piece.lowercased() == n.lowercased() else { continue }
            let end = nameStart + len
            if end < ns.length {
                let c = ns.character(at: end)
                guard isSpace(c) || c == comma || c == colon else { continue }
            }
            if len > (best ?? 0) { best = len }
        }
        return best
    }

    private static let at: unichar = 0x40
    private static let comma: unichar = 0x2C
    private static let colon: unichar = 0x3A
    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x3000 || c == 0xA0 }
    private static func skipSpaces(_ ns: NSString, from i: Int) -> Int {
        var i = i
        while i < ns.length, isSpace(ns.character(at: i)) { i += 1 }
        return i
    }
}
