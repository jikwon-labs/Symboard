import Foundation

/// 앱이 붙이는 기본 이름(12차). 저장값은 영어 그대로 두고, 화면에서만 지금 언어로 보인다.
/// 사용자가 이름을 바꿨으면(표에 없는 글) 그대로 보인다.
public enum DefaultNames {
    /// 새 노드를 놓을 때 붙이는 이름. 도형은 `k.capitalized`(Rect·Ellipse·…).
    public static let nodeTitles: Set<String> = [
        "Text", "Note", "Checklist", "Board", "Web", "Orchestrator", "Calendar", "Document", "Memory",
        "Rect", "Ellipse", "Diamond", "Arrow",
    ]
    /// 칸반을 새로 놓을 때 붙는 열 이름과 "New column" 의 기본값.
    public static let kanbanColumns: Set<String> = ["Backlog", "To Do", "In Progress", "Done", "Review"]

    public static func display(_ title: String, defaults: Set<String>, in lang: LanguageMode) -> String {
        defaults.contains(title) ? L10n.translate(title, to: lang) : title
    }
}

extension BoardNode {
    /// 화면에 보일 이름. 기본 이름이면 지금 언어로.
    public var displayTitle: String { displayTitle(in: L10n.current) }
    public func displayTitle(in lang: LanguageMode) -> String {
        DefaultNames.display(title, defaults: DefaultNames.nodeTitles, in: lang)
    }
}

extension KanbanColumn {
    public var displayTitle: String { displayTitle(in: L10n.current) }
    public func displayTitle(in lang: LanguageMode) -> String {
        DefaultNames.display(title, defaults: DefaultNames.kanbanColumns, in: lang)
    }
}

/// 다이어그램 채움 색(12차). Colorful 스타일은 강조색을 22% 로 어둡게 한 채움을 저장한다(다크 바탕용).
/// 라이트에서는 같은 색 계열의 밝은 채움으로 바꿔 그린다. 어둡지 않은 채움(사용자가 고른 색)은 그대로.
public enum ShapeFill {
    public static let darkFactor = 0.22

    /// "#RRGGBB" → 0...1 성분. 읽지 못하면 nil.
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public static func hex(_ c: (r: Double, g: Double, b: Double)) -> String {
        func b(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(c.r), b(c.g), b(c.b))
    }

    /// 다크용으로 어둡게 만든 채움인가(가장 밝은 성분이 원래 색의 22% 이하 범위).
    public static func isDarkened(_ hex: String) -> Bool {
        guard let c = rgb(hex) else { return false }
        let m = max(c.r, c.g, c.b)
        return m > 0.02 && m <= darkFactor + 0.01
    }

    /// 지금 모드에 맞는 채움. 라이트에서 어둡게 만든 채움이면 원래 색을 되살려 흰색 쪽으로 82% 섞는다.
    public static func forMode(_ hex: String, light: Bool) -> String {
        guard light, isDarkened(hex), let c = rgb(hex) else { return hex }
        let base = (r: min(1, c.r / darkFactor), g: min(1, c.g / darkFactor), b: min(1, c.b / darkFactor))
        let t = 0.82
        return Self.hex((base.r + (1 - base.r) * t, base.g + (1 - base.g) * t, base.b + (1 - base.b) * t))
    }
}
