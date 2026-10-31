import Foundation
import Testing
@testable import SymboardCore

@Suite struct ArrowRouterTests {
    func box(_ x: Double, _ y: Double) -> Rect { Rect(x: x, y: y, w: 200, h: 100) }

    /// 꺾은선은 가로·세로 토막으로만 이어지고, 끝 상자 밖에서 시작해 끝난다.
    @Test func orthogonalAndOutside() throws {
        let a = box(0, 0), b = box(400, 300), id = UUID()
        let r = try #require(ArrowRouter.route([(id: id, from: a, to: b)])[id])
        for (u, w) in zip(r.points, r.points.dropFirst()) { #expect(abs(u.x - w.x) < 0.5 || abs(u.y - w.y) < 0.5) }
        #expect(r.points.first!.y >= a.y + a.h)   // 아래 변에서 나간다
        #expect(r.points.last!.y <= b.y)           // 위 변으로 들어간다
    }

    /// 사이에 있는 상자(이어지지 않은 상자 포함)를 돌아간다.
    @Test func detoursAroundBlockingBox() throws {
        let a = box(0, 0), b = box(0, 600), wall = Rect(x: -100, y: 250, w: 400, h: 100), id = UUID()
        let r = try #require(ArrowRouter.route([(id: id, from: a, to: b)], obstacles: [wall])[id])
        for (u, w) in zip(r.points, r.points.dropFirst()) { #expect(!ArrowRouter.hits(u, w, wall)) }
    }

    /// 오가는 두 선(a→b, b→a)은 다른 자리에서 나가 겹치지 않는다.
    @Test func backAndForthSeparate() throws {
        let a = box(0, 0), b = box(0, 400), x = UUID(), y = UUID()
        let rs = ArrowRouter.route([(id: x, from: a, to: b), (id: y, from: b, to: a)])
        let p = try #require(rs[x]), q = try #require(rs[y])
        #expect(abs(p.points.first!.x - q.points.last!.x) > 10)
    }
}

@Suite struct DiagramLayoutTests {
    /// 다시 정렬한 배치도 상자끼리 겹치지 않는다.
    @Test func noOverlap() {
        let spec = DiagramSpec(title: "t", nodes: (0..<8).map { .init(id: "n\($0)", label: "n\($0)", group: $0 < 4 ? "g1" : nil) },
                               edges: [.init(from: "n0", to: "n5"), .init(from: "n1", to: "n4"), .init(from: "n4", to: "n7"), .init(from: "n5", to: "n6"), .init(from: "n2", to: "n3")],
                               groups: [.init(id: "g1", label: "G")])
        let rs = Array(spec.layout(origin: Point(x: 0, y: 0)).nodes.values)
        #expect(rs.count == 8)
        for i in rs.indices { for j in rs.indices where i < j {
            let a = rs[i], b = rs[j]
            #expect(!(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h))
        } }
    }

    /// 선이 많이 오가는 그룹끼리 붙는다(받은 순서 A,B,C 에서 A↔C 만 이어지면 A,C 가 이웃).
    @Test func bandsWithLinksSitTogether() {
        let order = DiagramSpec.bandOrder(["A", "B", "C"], width: { _ in 100 }, links: [("A", "C"), ("C", "A")])
        let i = order.firstIndex(of: "A")!, j = order.firstIndex(of: "C")!
        #expect(abs(i - j) == 1)
        // 이어진 선이 없으면 받은 순서 그대로.
        #expect(DiagramSpec.bandOrder(["A", "B", "C"], width: { _ in 100 }, links: []) == ["A", "B", "C"])
    }
}
