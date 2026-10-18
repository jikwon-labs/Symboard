import AppKit
import SymboardCore

extension Notification.Name {
    /// 터미널 글꼴 설정이 바뀌었을 때. 떠 있는 모든 콘솔이 받아 바로 바꾼다.
    static let terminalFontChanged = Notification.Name("symboard.terminalFontChanged")
}

/// 터미널 글꼴(7차). 영문 글꼴에 한글 글꼴을 CoreText 대체 글꼴 목록(cascade list)으로 이어 붙인다.
/// 한글 글꼴 설명에는 한글 글자 범위(characterSet)를 붙여, 그 글꼴에 있는 다른 기호(※ ★ 「」 등)는
/// 가져가지 않고 한글에만 쓰이게 한다. 글자 자리는 SwiftTerm 이 칸 단위로 정하므로 넓은 글자는 두 칸에 놓인다.
@MainActor
enum TerminalFont {
    private(set) static var setting = TerminalFontSetting(prefs: .shared)

    static var current: NSFont { make(setting) }

    static func update(_ s: TerminalFontSetting) {
        guard s != setting else { return }
        setting = s
        s.save(to: .shared)
        NotificationCenter.default.post(name: .terminalFontChanged, object: nil)
    }

    static func make(_ s: TerminalFontSetting) -> NSFont {
        let size = CGFloat(s.size)
        let latin = regular(family: s.latinFamily, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        guard let hangul = regular(family: s.hangulFamily, size: size) else { return latin }
        let ko = NSFontDescriptor(fontAttributes: [.name: hangul.fontName, .characterSet: hangulSet])
        return NSFont(descriptor: latin.fontDescriptor.addingAttributes([.cascadeList: [ko]]), size: size) ?? latin
    }

    /// 묶음의 보통 굵기 글꼴. 빈 이름이거나 없는 글꼴이면 nil(시스템 기본).
    static func regular(family: String, size: CGFloat) -> NSFont? {
        guard !family.isEmpty else { return nil }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    static let hangulSet: CharacterSet = {
        var cs = CharacterSet()
        for r in TerminalFontSetting.hangulRanges { cs.insert(charactersIn: Unicode.Scalar(r.lowerBound)!...Unicode.Scalar(r.upperBound)!) }
        return cs
    }()

    /// 고정폭 글꼴 묶음(영문 글꼴 목록).
    static let monospacedFamilies: [String] = NSFontManager.shared.availableFontFamilies.filter { fam in
        !fam.hasPrefix(".") && (regular(family: fam, size: 12)?.isFixedPitch ?? false)
    }

    /// 설치된 모든 글꼴 묶음(한글 글꼴 목록). 한글을 가진 글꼴을 앞에 둔다.
    static let allFamilies: (hangul: [String], other: [String]) = {
        let fams = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
        let ga = Array("가".utf16)
        var hangul: [String] = [], other: [String] = []
        for f in fams {
            var g: [CGGlyph] = [0]
            if let font = regular(family: f, size: 12), CTFontGetGlyphsForCharacters(font, ga, &g, 1) { hangul.append(f) } else { other.append(f) }
        }
        return (hangul, other)
    }()
}
