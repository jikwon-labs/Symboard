import Foundation

/// 터미널 글꼴 설정(7차). 영문 고정폭 글꼴, 한글 글자에만 쓰는 글꼴, 크기. 상태 폴더 prefs.json 에 둔다.
/// 글꼴 이름은 글꼴 묶음(family) 이름이다. 빈 글은 "시스템 기본"(영문: SF Mono, 한글: macOS 가 고르는 대체 글꼴).
public struct TerminalFontSetting: Equatable, Sendable {
    public var latinFamily: String
    public var hangulFamily: String
    public var size: Double

    public static let sizeRange: ClosedRange<Double> = 10...20
    public static let standard = TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12)
    public static let previewText = "claude ~/repo 한글 미리보기 0O1lI"

    public init(latinFamily: String, hangulFamily: String, size: Double) {
        self.latinFamily = latinFamily
        self.hangulFamily = hangulFamily
        self.size = Self.clamp(size)
    }

    /// 크기는 10~20 의 정수로 맞춘다. 숫자가 아니면 기본 12.
    public static func clamp(_ s: Double) -> Double {
        guard s.isFinite else { return standard.size }
        return min(sizeRange.upperBound, max(sizeRange.lowerBound, s.rounded()))
    }

    static let latinKey = "terminal.font.latin"
    static let hangulKey = "terminal.font.hangul"
    static let sizeKey = "terminal.font.size"

    public init(prefs: Prefs) {
        let s = prefs.string(Self.sizeKey).flatMap(Double.init) ?? Self.standard.size
        self.init(latinFamily: prefs.string(Self.latinKey) ?? "", hangulFamily: prefs.string(Self.hangulKey) ?? "", size: s)
    }

    public func save(to prefs: Prefs) {
        prefs.set(latinFamily.isEmpty ? nil : latinFamily, for: Self.latinKey)
        prefs.set(hangulFamily.isEmpty ? nil : hangulFamily, for: Self.hangulKey)
        prefs.set(size == Self.standard.size ? nil : String(Int(size)), for: Self.sizeKey)
    }

    /// 한글 글꼴이 맡을 글자: 자모, 호환 자모, 확장 자모 A·B, 음절.
    public static let hangulRanges: [ClosedRange<UInt32>] = [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF]

    public static func isHangul(_ u: Unicode.Scalar) -> Bool { hangulRanges.contains { $0.contains(u.value) } }
}
