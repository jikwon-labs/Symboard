import Foundation

/// 터미널 글꼴 설정(7차). 영문 고정폭 글꼴, 한글 글자에만 쓰는 글꼴, 크기, 줄 간격. 상태 폴더 prefs.json 에 둔다.
/// 글꼴 이름은 글꼴 묶음(family) 이름이다. 빈 글은 "시스템 기본"(영문: SF Mono, 한글: macOS 가 고르는 대체 글꼴).
public struct TerminalFontSetting: Equatable, Sendable {
    public var latinFamily: String
    public var hangulFamily: String
    public var size: Double
    /// 줄 높이 배율(글꼴 높이의 몇 배). 1.0~1.5, 0.05 단위.
    public var lineHeight: Double

    public static let sizeRange: ClosedRange<Double> = 10...20
    public static let lineHeightRange: ClosedRange<Double> = 1.0...1.5
    public static let lineHeightChoices: [Double] = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
    public static let standard = TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12, lineHeight: 1.2)
    public static let previewText = "claude ~/repo 한글 미리보기 0O1lI"

    public init(latinFamily: String, hangulFamily: String, size: Double, lineHeight: Double = 1.2) {
        self.latinFamily = latinFamily
        self.hangulFamily = hangulFamily
        self.size = Self.clamp(size)
        self.lineHeight = Self.clampLineHeight(lineHeight)
    }

    /// 줄 간격은 1.0~1.5 의 0.05 단위로 맞춘다. 숫자가 아니면 기본 1.2.
    public static func clampLineHeight(_ v: Double) -> Double {
        guard v.isFinite else { return 1.2 }
        let r = (v * 20).rounded() / 20
        return min(lineHeightRange.upperBound, max(lineHeightRange.lowerBound, r))
    }

    /// 크기는 10~20 의 정수로 맞춘다. 숫자가 아니면 기본 12.
    public static func clamp(_ s: Double) -> Double {
        guard s.isFinite else { return standard.size }
        return min(sizeRange.upperBound, max(sizeRange.lowerBound, s.rounded()))
    }

    static let latinKey = "terminal.font.latin"
    static let hangulKey = "terminal.font.hangul"
    static let sizeKey = "terminal.font.size"
    static let lineHeightKey = "terminal.font.lineHeight"

    public init(prefs: Prefs) {
        let s = prefs.string(Self.sizeKey).flatMap(Double.init) ?? Self.standard.size
        let lh = prefs.string(Self.lineHeightKey).flatMap(Double.init) ?? Self.standard.lineHeight
        self.init(latinFamily: prefs.string(Self.latinKey) ?? "", hangulFamily: prefs.string(Self.hangulKey) ?? "", size: s, lineHeight: lh)
    }

    public func save(to prefs: Prefs) {
        prefs.set(latinFamily.isEmpty ? nil : latinFamily, for: Self.latinKey)
        prefs.set(hangulFamily.isEmpty ? nil : hangulFamily, for: Self.hangulKey)
        prefs.set(size == Self.standard.size ? nil : String(Int(size)), for: Self.sizeKey)
        prefs.set(lineHeight == Self.standard.lineHeight ? nil : String(lineHeight), for: Self.lineHeightKey)
    }

    /// 한글 글꼴이 맡을 글자: 자모, 호환 자모, 확장 자모 A·B, 음절.
    public static let hangulRanges: [ClosedRange<UInt32>] = [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF]

    public static func isHangul(_ u: Unicode.Scalar) -> Bool { hangulRanges.contains { $0.contains(u.value) } }
}
