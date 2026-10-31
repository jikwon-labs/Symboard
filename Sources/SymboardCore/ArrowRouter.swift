import Foundation

/// 다이어그램 화살표 길 찾기(11차). 상자 가운데끼리 비스듬히 잇던 선이 상자를 가로지르고 한 점에 몰려 어지러웠다.
/// 그래서 꺾은선(세로-가로-세로 또는 가로-세로-가로)으로 잇는다.
/// - 상자의 마주 보는 변에서 나가고 들어간다. 한 변에 선이 여럿이면 나가는 자리를 고르게 나눈다(되돌아오는 선도 따로 보인다).
/// - 꺾는 자리 후보 몇 개 중 다른 상자를 덜 지나고, 앞서 그린 선과 덜 겹치고, 짧은 길을 고른다.
public enum ArrowRouter {
    public struct Route: Equatable, Sendable {
        /// 시작점부터 화살촉 끝까지 꺾이는 점들.
        public var points: [Point]
        /// 이름표 가운데 자리(가장 긴 토막의 가운데).
        public var label: Point
    }

    enum Side { case minX, maxX, minY, maxY }

    /// obstacles: 선이 피할 상자(이어지지 않은 상자 포함). 비우면 선 끝의 상자들만 피한다.
    public static func route(_ edges: [(id: UUID, from: Rect, to: Rect)], obstacles extra: [Rect] = [], gap: Double = 8) -> [UUID: Route] {
        // 1. 선마다 나가는 변·들어가는 변을 정한다.
        struct Plan { var id: UUID; var a: Rect; var b: Rect; var vertical: Bool; var sa: Side; var sb: Side }
        var plans: [Plan] = []
        var out: [UUID: Route] = [:]
        for e in edges {
            let a = e.from, b = e.to
            let dyGap = max(b.y - (a.y + a.h), a.y - (b.y + b.h))
            let dxGap = max(b.x - (a.x + a.w), a.x - (b.x + b.w))
            if dyGap <= 0 && dxGap <= 0 {
                // 겹친 상자: 가운데끼리 바로.
                let s = Point(x: a.x + a.w / 2, y: a.y + a.h / 2), t = Point(x: b.x + b.w / 2, y: b.y + b.h / 2)
                out[e.id] = Route(points: [s, t], label: Point(x: (s.x + t.x) / 2, y: (s.y + t.y) / 2))
                continue
            }
            // 위아래로 떨어져 있으면 세로로 잇는다(층으로 나눈 배치의 기본). 옆으로 훨씬 멀 때만 가로로.
            let vertical = dyGap > 0 && dyGap * 2.5 >= dxGap
            let down = b.y + b.h / 2 > a.y + a.h / 2, right = b.x + b.w / 2 > a.x + a.w / 2
            plans.append(Plan(id: e.id, a: a, b: b, vertical: vertical,
                              sa: vertical ? (down ? .maxY : .minY) : (right ? .maxX : .minX),
                              sb: vertical ? (down ? .minY : .maxY) : (right ? .minX : .maxX)))
        }

        // 2. 한 변에 모인 선은 맞은편 끝의 순서대로 자리를 나눈다(선끼리 엇갈리지 않게).
        struct Key: Hashable { var r: Rect; var s: Side }
        func center(_ r: Rect) -> Point { Point(x: r.x + r.w / 2, y: r.y + r.h / 2) }
        var users: [Key: [(plan: Int, end: Int, other: Double)]] = [:]
        for (i, p) in plans.enumerated() {
            let ob = center(p.b), oa = center(p.a)
            users[Key(r: p.a, s: p.sa), default: []].append((i, 0, p.vertical ? ob.x : ob.y))
            users[Key(r: p.b, s: p.sb), default: []].append((i, 1, p.vertical ? oa.x : oa.y))
        }
        var ports = Array(repeating: [Point(x: 0, y: 0), Point(x: 0, y: 0)], count: plans.count)
        for (k, list) in users {
            let r = k.r
            let sorted = list.sorted { $0.other < $1.other }
            let along = (k.s == .minY || k.s == .maxY) ? r.w : r.h
            // 가운데 60% 안에서 고르게. 하나면 한가운데.
            let span = along * 0.6, n = Double(sorted.count)
            for (j, u) in sorted.enumerated() {
                let off = n == 1 ? 0 : -span / 2 + span * Double(j) / (n - 1)
                let p: Point
                switch k.s {
                case .minY: p = Point(x: r.x + r.w / 2 + off, y: r.y - gap)
                case .maxY: p = Point(x: r.x + r.w / 2 + off, y: r.y + r.h + gap)
                case .minX: p = Point(x: r.x - gap, y: r.y + r.h / 2 + off)
                case .maxX: p = Point(x: r.x + r.w + gap, y: r.y + r.h / 2 + off)
                }
                ports[u.plan][u.end] = p
            }
        }

        // 3. 꺾는 자리 후보 중 가장 깔끔한 길. 긴 선부터 정하면 짧은 선이 비켜 간다.
        let obstacles = Array(Set(edges.flatMap { [$0.from, $0.to] } + extra))
        // 상자 사이 빈 줄(돌아갈 때 지나갈 세로·가로 길).
        let laneX = obstacles.flatMap { [$0.x - 22, $0.x + $0.w + 22] }
        let laneY = obstacles.flatMap { [$0.y - 22, $0.y + $0.h + 22] }
        var drawn: [(Point, Point)] = []
        let order = plans.indices.sorted { dist(ports[$0][0], ports[$0][1]) > dist(ports[$1][0], ports[$1][1]) }
        for i in order {
            let p = plans[i], s = ports[i][0], t = ports[i][1]
            var cands: [[Point]] = []
            if p.vertical {
                let lead = p.sa == .maxY ? 1.0 : -1.0
                var ys = [(s.y + t.y) / 2, s.y + lead * 26, t.y - lead * 26]
                ys += ys.flatMap { [$0 - 12, $0 + 12] }
                for y in ys where (y - s.y) * lead >= 0 && (t.y - y) * lead >= 0 {
                    cands.append(abs(s.x - t.x) < 1 ? [s, t] : [s, Point(x: s.x, y: y), Point(x: t.x, y: y), t])
                }
            } else {
                let lead = p.sa == .maxX ? 1.0 : -1.0
                var xs = [(s.x + t.x) / 2, s.x + lead * 26, t.x - lead * 26]
                xs += xs.flatMap { [$0 - 12, $0 + 12] }
                for x in xs where (x - s.x) * lead >= 0 && (t.x - x) * lead >= 0 {
                    cands.append(abs(s.y - t.y) < 1 ? [s, t] : [s, Point(x: x, y: s.y), Point(x: x, y: t.y), t])
                }
            }
            // 바로 가는 길이 막히면 쓸 돌아가는 길: 나가자마자 꺾어 빈 줄을 따라가다 들어가기 직전에 꺾는다.
            if p.vertical {
                let lead = p.sa == .maxY ? 1.0 : -1.0
                let y1 = s.y + lead * 22, y2 = t.y - lead * 22
                for x in laneX { cands.append([s, Point(x: s.x, y: y1), Point(x: x, y: y1), Point(x: x, y: y2), Point(x: t.x, y: y2), t]) }
            } else {
                let lead = p.sa == .maxX ? 1.0 : -1.0
                let x1 = s.x + lead * 22, x2 = t.x - lead * 22
                for y in laneY { cands.append([s, Point(x: x1, y: s.y), Point(x: x1, y: y), Point(x: x2, y: y), Point(x: x2, y: t.y), t]) }
            }
            if cands.isEmpty { cands = [[s, t]] }
            let others = obstacles.filter { $0 != p.a && $0 != p.b }
            func score(_ pts: [Point]) -> Double {
                var v = 0.0
                for (u, w) in zip(pts, pts.dropFirst()) {
                    v += dist(u, w)
                    for r in others where hits(u, w, r.inset(-6)) { v += 2000 }
                    for (x, y) in drawn where overlaps(u, w, x, y) { v += 300 }
                }
                return v + Double(pts.count) * 15
            }
            let best = simplify(cands.min { score($0) < score($1) }!)
            for (u, w) in zip(best, best.dropFirst()) { drawn.append((u, w)) }
            let longest = zip(best, best.dropFirst()).max { dist($0.0, $0.1) < dist($1.0, $1.1) }!
            out[p.id] = Route(points: best, label: Point(x: (longest.0.x + longest.1.x) / 2, y: (longest.0.y + longest.1.y) / 2))
        }
        return out
    }

    static func dist(_ a: Point, _ b: Point) -> Double { hypot(b.x - a.x, b.y - a.y) }

    /// 겹친 점과 한 줄 위의 가운데 점을 뺀다(둥근 모서리가 엉뚱한 데 생기지 않게).
    static func simplify(_ pts: [Point]) -> [Point] {
        var out: [Point] = []
        for p in pts where out.last.map({ dist($0, p) > 0.5 }) ?? true {
            if out.count >= 2 {
                let a = out[out.count - 2], b = out[out.count - 1]
                if (abs(a.x - b.x) < 0.5 && abs(b.x - p.x) < 0.5) || (abs(a.y - b.y) < 0.5 && abs(b.y - p.y) < 0.5) { out.removeLast() }
            }
            out.append(p)
        }
        return out
    }

    /// 가로·세로 토막이 사각형을 지나는지.
    static func hits(_ a: Point, _ b: Point, _ r: Rect) -> Bool {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        return maxX > r.x && minX < r.x + r.w && maxY > r.y && minY < r.y + r.h
    }

    /// 두 토막이 같은 줄 위에서 겹치는지(가까이 나란히 가면 한 선처럼 보인다).
    static func overlaps(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
        let h1 = abs(a.y - b.y) < 0.5, h2 = abs(c.y - d.y) < 0.5
        if h1 && h2 && abs(a.y - c.y) < 6 {
            return min(max(a.x, b.x), max(c.x, d.x)) - max(min(a.x, b.x), min(c.x, d.x)) > 4
        }
        let v1 = abs(a.x - b.x) < 0.5, v2 = abs(c.x - d.x) < 0.5
        if v1 && v2 && abs(a.x - c.x) < 6 {
            return min(max(a.y, b.y), max(c.y, d.y)) - max(min(a.y, b.y), min(c.y, d.y)) > 4
        }
        return false
    }
}

extension Rect {
    /// 안쪽으로 d 만큼 줄인(음수면 넓힌) 사각형.
    func inset(_ d: Double) -> Rect { Rect(x: x + d, y: y + d, w: w - d * 2, h: h - d * 2) }
}
