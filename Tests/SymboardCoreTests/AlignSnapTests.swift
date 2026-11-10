import Foundation
import Testing
@testable import SymboardCore

@Suite struct AlignSnapTests {
    typealias Guide = AlignSnap.Guide
    let other = Rect(x: 100, y: 100, w: 200, h: 100)

    @Test func snapsLeftEdges() {
        // 아래쪽에서 왼쪽 가장자리가 4 만큼 어긋남 → 붙는다. 세로는 멀어서 그대로.
        let r = AlignSnap.snap(Rect(x: 104, y: 400, w: 150, h: 80), to: [other], threshold: 6)
        #expect(r.rect == Rect(x: 100, y: 400, w: 150, h: 80))
        #expect(r.guides == [Guide(axis: .vertical, position: 100, from: 100, to: 480)])
    }

    @Test func snapsRightEdgesAndCenters() {
        // 오른쪽 가장자리: 끄는 쪽 끝 297 → 300.
        let right = AlignSnap.snap(Rect(x: 147, y: 400, w: 150, h: 80), to: [other], threshold: 6)
        #expect(right.rect.x == 150)
        #expect(right.guides == [Guide(axis: .vertical, position: 300, from: 100, to: 480)])
        // 가운데: 끄는 쪽 가운데 203 → 200.
        let mid = AlignSnap.snap(Rect(x: 128, y: 400, w: 150, h: 80), to: [other], threshold: 6)
        #expect(mid.rect.x == 125)
        #expect(mid.guides == [Guide(axis: .vertical, position: 200, from: 100, to: 480)])
    }

    @Test func snapsEdgeToOppositeEdge() {
        // 끄는 쪽 왼쪽이 상대 오른쪽(300)에 붙는다. 같은 줄에 나란히 세울 때.
        let r = AlignSnap.snap(Rect(x: 303, y: 400, w: 150, h: 80), to: [other], threshold: 6)
        #expect(r.rect.x == 300)
    }

    @Test func staysWhenOutOfRange() {
        let m = Rect(x: 110, y: 400, w: 150, h: 80)
        let r = AlignSnap.snap(m, to: [other], threshold: 6)
        #expect(r.rect == m)
        #expect(r.guides.isEmpty)
        #expect(AlignSnap.snap(m, to: [], threshold: 6).rect == m)
        #expect(AlignSnap.snap(Rect(x: 101, y: 400, w: 150, h: 80), to: [other], threshold: 0).rect.x == 101)
    }

    @Test func centerDoesNotSnapToEdge() {
        // 끄는 쪽 가운데(100)가 상대 왼쪽 가장자리(100)와 같아도 맞춤으로 치지 않는다.
        let m = Rect(x: 28, y: 400, w: 150, h: 80)   // 가운데 103, 가장자리 28·178 은 모두 멀다
        #expect(AlignSnap.snap(m, to: [other], threshold: 6).rect == m)
    }

    @Test func snapsBothAxesIndependently() {
        // 오른쪽 옆에서 위쪽 가장자리(100)에 붙고, 왼쪽은 상대 오른쪽(300)에 붙는다.
        let r = AlignSnap.snap(Rect(x: 302, y: 97, w: 150, h: 80), to: [other], threshold: 6)
        #expect(r.rect == Rect(x: 300, y: 100, w: 150, h: 80))
        #expect(r.guides.contains(Guide(axis: .vertical, position: 300, from: 100, to: 200)))
        #expect(r.guides.contains(Guide(axis: .horizontal, position: 100, from: 100, to: 450)))
        #expect(r.guides.count == 2)
    }

    @Test func picksNearestAndMergesGuides() {
        // 둘 다 범위 안이면 더 가까운 쪽(x 102)에 붙는다.
        let near = Rect(x: 102, y: 600, w: 50, h: 50)
        let r = AlignSnap.snap(Rect(x: 103, y: 400, w: 150, h: 80), to: [other, near], threshold: 6)
        #expect(r.rect.x == 102)
        #expect(r.guides == [Guide(axis: .vertical, position: 102, from: 400, to: 650)])
        // 같은 줄에 선 노드가 둘이면 선 하나로 잇는다.
        let below = Rect(x: 100, y: 600, w: 80, h: 50)
        let both = AlignSnap.snap(Rect(x: 103, y: 400, w: 150, h: 80), to: [other, below], threshold: 6)
        #expect(both.guides == [Guide(axis: .vertical, position: 100, from: 100, to: 650)])
    }

    @Test func sameSizeShowsAllMatchingLines() {
        // 크기가 같은 노드를 세로로 맞추면 왼쪽·가운데·오른쪽 세 줄이 다 맞는다.
        let r = AlignSnap.snap(Rect(x: 98, y: 400, w: 200, h: 100), to: [other], threshold: 6)
        #expect(r.rect.x == 100)
        #expect(r.guides.map(\.position) == [100, 200, 300])
    }
}
