import Foundation
import Testing
@testable import SymboardCore

@Suite struct UIPrefsTests {
    func prefs() throws -> Prefs {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Prefs(directory: dir)
    }

    @Test func firstRunUntilChosen() throws {
        let p = try prefs()
        #expect(UIPrefs.needsFirstRunChoice(p))
        #expect(UIPrefs.appearance(p) == .system && UIPrefs.language(p) == .system)
        UIPrefs.setAppearance(.light, p)
        #expect(!UIPrefs.needsFirstRunChoice(p))
        #expect(UIPrefs.appearance(p) == .light)
        UIPrefs.setLanguage(.ko, p)
        #expect(UIPrefs.language(p) == .ko)
    }

    @Test func systemLanguageFollowsPreferredList() {
        #expect(UIPrefs.resolvedLanguage(.system, preferred: ["ko-KR", "en-US"]) == .ko)
        #expect(UIPrefs.resolvedLanguage(.system, preferred: ["en-US", "ko-KR"]) == .en)
        #expect(UIPrefs.resolvedLanguage(.system, preferred: []) == .en)
        #expect(UIPrefs.resolvedLanguage(.en, preferred: ["ko-KR"]) == .en)
    }
}

@MainActor @Suite(.serialized) struct L10nTests {
    @Test func lookupAndFormats() {
        #expect(L10n.translate("Home", to: .ko) != "Home")                      // 표에 있는 글
        #expect(L10n.translate("zz not in table zz", to: .ko) == "zz not in table zz")  // 없으면 영어
        #expect(L10n.translate("Home", to: .en) == "Home")
        #expect(String(format: L10n.translate("Sent to %d consoles", to: .ko), 3).contains("3"))
        // 전역 언어는 기본 English(다른 시험과 동시에 돌기 때문에 바꾸지 않는다).
        #expect(Ln(1, "Sent to %d console", "Sent to %d consoles") == "Sent to 1 console")
        #expect(Ln(2, "Sent to %d console", "Sent to %d consoles") == "Sent to 2 consoles")
    }

    /// 한국어 표의 자리표시(%@·%d)가 영어 원문과 같은 수·순서인지(틀리면 String(format:) 이 엉뚱한 값을 넣거나 멈춘다).
    @Test func placeholdersMatch() {
        func marks(_ s: String) -> [String] {
            let rx = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[0-9]*[@dsf]")
            return rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
        }
        for (en, ko) in Strings.ko { #expect(marks(en) == marks(ko), "\(en) → \(ko)") }
    }

    @Test func shortcutTableIsTranslated() {
        for sec in ShortcutCatalog.sections {
            #expect(Strings.ko[sec.title] != nil, "\(sec.title)")
            for e in sec.entries { #expect(Strings.ko[e.action] != nil, "\(e.action)") }
        }
    }
}
