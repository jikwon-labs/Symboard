import Foundation
import Testing
@testable import SymboardCore

/// 7차: 터미널 글꼴 설정 저장·되살리기와 크기 범위.
@Suite struct TerminalFontSettingTests {
    func tempPrefs() -> (Prefs, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("symfont-\(UUID().uuidString)")
        return (Prefs(directory: dir), dir)
    }

    @Test func defaultsWhenNothingSaved() {
        let (p, _) = tempPrefs()
        #expect(TerminalFontSetting(prefs: p) == .standard)
    }

    @Test func sizeIsClampedAndRounded() {
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 4).size == 10)
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 99).size == 20)
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 13.4).size == 13)
        #expect(TerminalFontSetting.clamp(.nan) == 12)
    }

    @Test func roundTripsThroughPrefsFile() {
        let (p, dir) = tempPrefs()
        TerminalFontSetting(latinFamily: "Menlo", hangulFamily: "Pretendard", size: 14).save(to: p)
        // 앱을 다시 켠 것처럼 같은 폴더에서 새로 읽는다.
        let again = TerminalFontSetting(prefs: Prefs(directory: dir))
        #expect(again == TerminalFontSetting(latinFamily: "Menlo", hangulFamily: "Pretendard", size: 14))
    }

    @Test func backToDefaultRemovesKeys() {
        let (p, dir) = tempPrefs()
        TerminalFontSetting(latinFamily: "Menlo", hangulFamily: "Pretendard", size: 14).save(to: p)
        TerminalFontSetting.standard.save(to: p)
        #expect(p.string("terminal.font.hangul") == nil)
        #expect(TerminalFontSetting(prefs: Prefs(directory: dir)) == .standard)
    }

    @Test func lineHeightDefaultsClampsAndSaves() {
        #expect(TerminalFontSetting.standard.lineHeight == 1.2)
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12, lineHeight: 0.5).lineHeight == 1.0)
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12, lineHeight: 3).lineHeight == 1.5)
        #expect(TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12, lineHeight: 1.33).lineHeight == 1.35)
        #expect(TerminalFontSetting.clampLineHeight(.nan) == 1.2)
        let (p, dir) = tempPrefs()
        TerminalFontSetting(latinFamily: "", hangulFamily: "", size: 12, lineHeight: 1.4).save(to: p)
        #expect(TerminalFontSetting(prefs: Prefs(directory: dir)).lineHeight == 1.4)
        TerminalFontSetting.standard.save(to: p)
        #expect(p.string("terminal.font.lineHeight") == nil)
    }

    @Test func hangulRanges() {
        #expect(TerminalFontSetting.isHangul("한".unicodeScalars.first!))
        #expect(TerminalFontSetting.isHangul("ㄱ".unicodeScalars.first!))
        #expect(!TerminalFontSetting.isHangul("A".unicodeScalars.first!))
        #expect(!TerminalFontSetting.isHangul("漢".unicodeScalars.first!))
    }
}
