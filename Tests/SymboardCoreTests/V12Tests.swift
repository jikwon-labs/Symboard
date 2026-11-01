import Foundation
import Testing
@testable import SymboardCore

/// 12차: 기본 노드 이름은 화면에서 지금 언어로, Colorful 채움은 라이트에서 밝게.
@Suite struct DefaultNameTests {
    func node(_ title: String) -> BoardNode {
        BoardNode(kind: .checklist, frame: Rect(x: 0, y: 0, w: 10, h: 10), title: title)
    }

    @Test func defaultTitleFollowsLanguage() {
        #expect(node("Checklist").displayTitle(in: .ko) == "체크리스트")
        #expect(node("Checklist").displayTitle(in: .en) == "Checklist")
        #expect(node("Note").displayTitle(in: .ko) == "메모")
    }

    @Test func renamedTitleStays() {
        #expect(node("My tasks").displayTitle(in: .ko) == "My tasks")
        // 표에 있는 글이라도 기본 이름이 아니면 바꾸지 않는다("Done" 은 노드 기본 이름이 아니다).
        #expect(node("Done").displayTitle(in: .ko) == "Done")
    }

    @Test func everyDefaultHasKorean() {
        for t in DefaultNames.nodeTitles.union(DefaultNames.kanbanColumns) {
            #expect(Strings.ko[t] != nil, "no Korean for \(t)")
        }
    }

    @Test func kanbanColumns() {
        #expect(KanbanColumn(title: "In Progress").displayTitle(in: .ko) == "진행 중")
        #expect(KanbanColumn(title: "Shipping").displayTitle(in: .ko) == "Shipping")
    }
}

@Suite struct ShapeFillTests {
    /// DiagramMaker.dim 과 같은 계산(22%, 버림).
    func dim(_ hex: String) -> String {
        let c = ShapeFill.rgb(hex)!
        return String(format: "#%02X%02X%02X", Int(c.r * 255 * 0.22), Int(c.g * 255 * 0.22), Int(c.b * 255 * 0.22))
    }
    func luminance(_ hex: String) -> Double {
        let c = ShapeFill.rgb(hex)!
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    @Test func darkFillBecomesLightInLightMode() {
        for tint in ["#56A8F5", "#6FCF97", "#E9C46A", "#B48CF2", "#F28AB2", "#56C2C9"] {
            let d = dim(tint)
            #expect(ShapeFill.isDarkened(d))
            let l = ShapeFill.forMode(d, light: true)
            #expect(luminance(l) > 0.8, "\(tint) -> \(l)")
            // 색 계열이 남는다: 가장 강한 성분이 원래 색과 같다.
            let o = ShapeFill.rgb(tint)!, n = ShapeFill.rgb(l)!
            let strongest = { (c: (r: Double, g: Double, b: Double)) in [c.r, c.g, c.b].enumerated().max { $0.element < $1.element }!.offset }
            #expect(strongest(o) == strongest(n), "\(tint) -> \(l)")
        }
    }

    @Test func darkModeAndUserColorsUntouched() {
        #expect(ShapeFill.forMode(dim("#56A8F5"), light: false) == dim("#56A8F5"))
        #expect(ShapeFill.forMode("#C9A227", light: true) == "#C9A227")
        #expect(ShapeFill.forMode("#000000", light: true) == "#000000")
        #expect(ShapeFill.forMode("oops", light: true) == "oops")
    }
}
