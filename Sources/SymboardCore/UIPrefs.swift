import Foundation

/// 화면 모드(10차). 처음 켤 때 고르고 설정 창에서 바꾼다.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, dark, light
}

/// 화면 글 언어(10차). system 은 기기 언어(한국어면 한국어, 아니면 English).
public enum LanguageMode: String, CaseIterable, Sendable {
    case system, en, ko
}

public enum UIPrefs {
    public static let appearanceKey = "ui.appearance"
    public static let languageKey = "ui.language"

    /// 처음 켤 때 고르는 창을 보여야 하는지(둘 다 아직 고른 적 없음).
    public static func needsFirstRunChoice(_ prefs: Prefs) -> Bool {
        prefs.string(appearanceKey) == nil && prefs.string(languageKey) == nil
    }

    public static func appearance(_ prefs: Prefs) -> AppearanceMode {
        prefs.string(appearanceKey).flatMap(AppearanceMode.init) ?? .system
    }

    public static func setAppearance(_ m: AppearanceMode, _ prefs: Prefs) { prefs.set(m.rawValue, for: appearanceKey) }

    public static func language(_ prefs: Prefs) -> LanguageMode {
        prefs.string(languageKey).flatMap(LanguageMode.init) ?? .system
    }

    public static func setLanguage(_ m: LanguageMode, _ prefs: Prefs) { prefs.set(m.rawValue, for: languageKey) }

    /// 실제로 쓸 언어. system 이면 기기 선호 언어의 첫 번째가 한국어일 때 ko.
    public static func resolvedLanguage(_ mode: LanguageMode, preferred: [String] = Locale.preferredLanguages) -> LanguageMode {
        switch mode {
        case .en, .ko: return mode
        case .system: return (preferred.first ?? "en").hasPrefix("ko") ? .ko : .en
        }
    }
}
