import Foundation
import Testing
@testable import SymboardCore

/// 나란히 선 lead 둘이 각자 콘솔을 띄울 때 자리와 선.
struct ConsoleLaneTests {
    let a = Rect(x: 0, y: 0, w: 640, h: 400)
    let b = Rect(x: 680, y: 0, w: 640, h: 400)

    @Test func childStaysUnderItsOwnLead() {
        // A 가 둘째를 띄워도 B 밑으로 들어가지 않고 A 밑 다음 줄로.
        let a1 = CanvasLayout.belowSlot(w: 640, h: 400, reference: a, obstacles: [a, b])
        #expect(a1.x == 0 && a1.y == 440)
        let a2 = CanvasLayout.belowSlot(w: 640, h: 400, reference: a, obstacles: [a, b, a1])
        #expect(a2.x == 0 && a2.y == 880)
        // B 의 첫 콘솔은 B 바로 밑.
        let b1 = CanvasLayout.belowSlot(w: 640, h: 400, reference: b, obstacles: [a, b, a1, a2])
        #expect(b1.x == 680 && b1.y == 440)
    }

    @Test func lastLeadInRowStillSpreads() {
        // 오른쪽 이웃이 없으면 예전처럼 옆으로 채운다.
        let b1 = CanvasLayout.belowSlot(w: 640, h: 400, reference: b, obstacles: [a, b])
        let b2 = CanvasLayout.belowSlot(w: 640, h: 400, reference: b, obstacles: [a, b, b1])
        #expect(b2.y == 440 && b2.x == 1360)
    }

    @Test func linkGoesAroundOtherConsole() {
        // A → A2 사이에 A1 이 있으면 선이 A1 을 가로지르지 않는다.
        let a1 = Rect(x: 0, y: 440, w: 640, h: 400), a2 = Rect(x: 0, y: 880, w: 640, h: 400)
        let id = UUID()
        let pts = ArrowRouter.linkRoutes([(id: id, from: a, to: a2)], obstacles: [a, a1, a2])[id]!
        for (u, w) in zip(pts, pts.dropFirst()) { #expect(!ArrowRouter.hits(u, w, a1)) }
        #expect(pts.first!.y == 400 && pts.last!.y == 880)
    }

    @Test func shareLinkCarriesRoute() {
        let n1 = BoardNode(kind: .terminal, frame: a, title: "A")
        let n2 = BoardNode(kind: .terminal, frame: Rect(x: 0, y: 440, w: 640, h: 400), title: "A1")
        var ws = Workspace(name: "t", nodes: [n1, n2])
        ws.links = [NodeLink(from: n1.id, to: n2.id, style: NodeLink.spawnedStyle)]
        let share = ShareBoard.make(ws, lang: .en) { _ in ("C", "#fff") }
        #expect((share.links.first?.points?.count ?? 0) >= 2)
    }
}
