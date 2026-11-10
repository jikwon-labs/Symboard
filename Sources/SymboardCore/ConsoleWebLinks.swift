import Foundation

/// 콘솔에 나온 링크를 웹 타일로 여는 규칙(15차).
/// - claude 가 답에 링크를 쓰면 그 콘솔과 선으로 이은 웹 타일에 자동으로 연다(설정에서 끔).
/// - 콘솔의 링크를 Cmd+클릭하면 앱 안 웹 타일, Cmd+Shift+클릭하면 기본 브라우저.
public enum ConsoleWebLinks {
    /// 콘솔 → 웹 타일 선(NodeLink.style).
    public static let linkStyle = "web"

    public static let autoOpenKey = "ui.autoOpenLinks"
    /// claude 가 보여 준 링크를 웹 타일에 자동으로 여는지(기본 켬).
    public static func autoOpen(_ prefs: Prefs) -> Bool { prefs.string(autoOpenKey) != "off" }
    public static func setAutoOpen(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: autoOpenKey) }

    /// 콘솔마다 기억하는 최근 주소 수.
    public static let knownLimit = 200

    private static let pattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'`]+"#, options: [.caseInsensitive])

    /// 글 안의 http(s) 주소들. 나온 차례대로, 겹침 없이. 끝에 붙은 문장 부호·마크다운 기호는 뗀다.
    public static func urls(in text: String) -> [String] {
        var out: [String] = []
        for r in ranges(in: text) {
            let u = String(text[r])
            if !out.contains(u) { out.append(u) }
        }
        return out
    }

    /// 주소 자리들(끝 정리 뒤).
    static func ranges(in text: String) -> [Range<String.Index>] {
        let ns = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: ns).compactMap { m -> Range<String.Index>? in
            guard let r = Range(m.range, in: text) else { return nil }
            let trimmed = trim(text[r])
            guard trimmed.count > "https://".count else { return nil }
            return r.lowerBound..<text.index(r.lowerBound, offsetBy: trimmed.count)
        }
    }

    /// 주소 끝의 문장 부호·닫는 괄호(짝 없는 것)·마크다운 굵게 기호를 뗀다.
    static func trim(_ s: Substring) -> Substring {
        var s = s
        while let last = s.last {
            if ".,;:!?*'\"".contains(last) { s = s.dropLast(); continue }
            if let open = ["(": ")", "[": "]", "{": "}"].first(where: { $0.value == String(last) })?.key {
                let opens = s.filter { String($0) == open }.count
                let closes = s.filter { $0 == last }.count
                if closes > opens { s = s.dropLast(); continue }
            }
            break
        }
        return s
    }

    /// 콘솔 한 줄에서 index 번째 글자를 Cmd+클릭했을 때 열 주소.
    /// - 그 자리에 주소가 있으면 그 주소. 줄바꿈에 잘렸으면 known(이 콘솔에 나온 주소) 중 그것으로 시작하는 더 긴 주소.
    /// - 주소 조각(긴 주소가 다음 줄로 넘어간 부분)이면 known 중 그 조각을 품은 가장 최근 주소.
    /// - localhost:3000 처럼 http 가 없는 로컬 주소도 연다.
    public static func url(at index: Int, in line: String, known: [String]) -> String? {
        let chars = Array(line)
        guard index >= 0, index < chars.count, !chars[index].isWhitespace else { return nil }
        for r in ranges(in: line) {
            let lo = line.distance(from: line.startIndex, to: r.lowerBound)
            let hi = line.distance(from: line.startIndex, to: r.upperBound)
            guard index >= lo, index < hi else { continue }
            let u = String(line[r])
            return known.last(where: { $0.count > u.count && $0.hasPrefix(u) }) ?? u
        }
        // 클릭한 자리의 공백 없는 덩어리.
        var lo = index, hi = index
        while lo > 0, !chars[lo - 1].isWhitespace { lo -= 1 }
        while hi + 1 < chars.count, !chars[hi + 1].isWhitespace { hi += 1 }
        let token = String(trim(Substring(String(chars[lo...hi]))))
        if token.count >= 6, let u = known.last(where: { $0.contains(token) }) { return u }
        if token.range(of: #"^(localhost|127\.0\.0\.1|0\.0\.0\.0)(:\d+)?(/\S*)?$"#, options: .regularExpression) != nil {
            return "http://" + token
        }
        return nil
    }

    /// 같은 일로 묶인 노드들: spawned·handoff 선으로 이어진 무리(부모·하위 콘솔과 그 사이의 프롬프트 카드). 자기 자신 포함.
    public static func family(of id: UUID, links: [NodeLink]) -> Set<UUID> {
        let chain = links.filter { AgentLimits.chainStyles.contains($0.style ?? "") }
        var seen: Set<UUID> = [id], queue = [id]
        while let cur = queue.popLast() {
            for l in chain where l.from == cur || l.to == cur {
                let other = l.from == cur ? l.to : l.from
                if seen.insert(other).inserted { queue.append(other) }
            }
        }
        return seen
    }

    /// 두 주소가 같은 페이지인가. 끝의 / 하나 차이는 같다고 본다(웹 타일은 열고 난 뒤의 주소로 탭을 고쳐 적는다).
    public static func sameAddress(_ a: String, _ b: String) -> Bool {
        func bare(_ s: String) -> Substring { s.hasSuffix("/") ? s.dropLast() : Substring(s) }
        return !a.isEmpty && bare(a) == bare(b)
    }

    /// 같은 무리의 다른 콘솔이 이미 이 주소를 띄워 둔 웹 타일과 그 탭. 없으면 nil.
    /// 하위 콘솔이 만든 페이지 주소를 부모 콘솔이 보고에 다시 적으면, 부모 옆에 같은 페이지 타일이 하나 더 생겼다.
    /// - tabs: 웹 타일의 탭 주소들(웹 타일이 아니면 nil).
    public static func familyTile(showing address: String, from consoleID: UUID, links: [NodeLink],
                                  tabs: (UUID) -> [String]?) -> (tile: UUID, tab: Int)? {
        let kin = family(of: consoleID, links: links).subtracting([consoleID])
        for l in links where l.style == linkStyle && kin.contains(l.from) {
            if let i = tabs(l.to)?.firstIndex(where: { sameAddress($0, address) }) { return (l.to, i) }
        }
        return nil
    }

    /// 기억하는 주소 목록에 새 주소를 더한다(이미 있으면 맨 뒤로). 한도를 넘으면 오래된 것부터 뺀다.
    public static func remember(_ urls: [String], in known: inout [String]) {
        for u in urls {
            known.removeAll { $0 == u }
            known.append(u)
        }
        if known.count > knownLimit { known.removeFirst(known.count - knownLimit) }
    }
}
