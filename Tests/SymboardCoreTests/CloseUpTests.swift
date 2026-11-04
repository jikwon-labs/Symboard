import Foundation
import Testing
@testable import SymboardCore

@Suite struct CloseUpTests {
    @Test func fitsConsoleToScreen() {
        // 600×400 콘솔, 1448×848 화면 → 여백 24 를 빼고 1400×800. 가로 2.33, 세로 2 → 2.
        let z = CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 600, h: 400), width: 1448, height: 848, minZoom: 0.1)
        #expect(z == 2)
        // 큰 콘솔은 1 보다 작게.
        let z2 = CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 2000, h: 1000), width: 1048, height: 548, minZoom: 0.1)
        #expect(abs(z2 - 0.5) < 0.0001)
    }

    @Test func capsAndGuards() {
        #expect(CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 100, h: 100), width: 3000, height: 3000, minZoom: 0.1) == CloseUp.maxZoom)
        #expect(CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 100000, h: 100000), width: 1000, height: 1000, minZoom: 0.1) == 0.1)
        #expect(CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 0, h: 100), width: 1000, height: 1000, minZoom: 0.1) == 1)
        #expect(CloseUp.zoom(fitting: Rect(x: 0, y: 0, w: 100, h: 100), width: 10, height: 10, minZoom: 0.1) == 1)
    }

    @Test func toggles() {
        let a = UUID(), b = UUID(), ws = UUID(), other = UUID()
        #expect(CloseUp.step(current: nil, target: a, workspaceID: ws) == .enter)
        let c = CloseUp(nodeID: a, previous: Viewport(center: Point(x: 5, y: 6), zoom: 0.4), workspaceID: ws)
        #expect(CloseUp.step(current: c, target: a, workspaceID: ws) == .restore)
        // 다른 콘솔이면 그 콘솔로 들어간다(되돌아갈 자리는 처음 것을 그대로 둔다 — 앱이 정한다).
        #expect(CloseUp.step(current: c, target: b, workspaceID: ws) == .enter)
        #expect(CloseUp.step(current: c, target: a, workspaceID: other) == .enter)
        #expect(CloseUp.center(of: Rect(x: 10, y: 20, w: 100, h: 50)) == Point(x: 60, y: 45))
    }
}
