import Foundation

/// 노드를 끌 때 옆 노드와 줄 맞추기. 끄는 노드의 왼쪽·가운데·오른쪽(세로는 위·가운데·아래)이
/// 다른 노드의 같은 줄에 가까워지면 그 줄에 붙이고, 어디에 맞았는지 안내선으로 돌려준다.
/// 가장자리는 가장자리끼리(왼쪽↔오른쪽 포함), 가운데는 가운데끼리만 맞춘다.
public enum AlignSnap {
    /// 안내선 하나. `vertical` 이면 x = `position` 인 세로선이고 `from`~`to` 는 y 범위다. `horizontal` 은 그 반대.
    public struct Guide: Equatable, Sendable {
        public enum Axis: Equatable, Sendable { case vertical, horizontal }
        public var axis: Axis
        public var position: Double
        public var from: Double
        public var to: Double

        public init(axis: Axis, position: Double, from: Double, to: Double) {
            self.axis = axis; self.position = position; self.from = from; self.to = to
        }
    }

    public struct Result: Equatable, Sendable {
        /// 붙인 뒤의 자리. 크기는 바뀌지 않는다.
        public var rect: Rect
        public var guides: [Guide]
    }

    /// `moving` 을 `others` 에 맞춘다. `threshold` 는 붙는 거리(캔버스 좌표). 가로와 세로는 따로 본다.
    public static func snap(_ moving: Rect, to others: [Rect], threshold: Double) -> Result {
        guard threshold > 0, !others.isEmpty else { return Result(rect: moving, guides: []) }
        var r = moving
        let dx = bestDelta(lines(r.x, r.w), others.map { lines($0.x, $0.w) }, threshold)
        let dy = bestDelta(lines(r.y, r.h), others.map { lines($0.y, $0.h) }, threshold)
        if let dx { r.x += dx }
        if let dy { r.y += dy }
        var guides: [Guide] = []
        if dx != nil {
            guides += matched(lines(r.x, r.w), others.map { (lines($0.x, $0.w), $0.y, $0.y + $0.h) }, span: (r.y, r.y + r.h))
                .map { Guide(axis: .vertical, position: $0.0, from: $0.1, to: $0.2) }
        }
        if dy != nil {
            guides += matched(lines(r.y, r.h), others.map { (lines($0.y, $0.h), $0.x, $0.x + $0.w) }, span: (r.x, r.x + r.w))
                .map { Guide(axis: .horizontal, position: $0.0, from: $0.1, to: $0.2) }
        }
        return Result(rect: r, guides: guides)
    }

    /// 한 축의 세 줄: 시작 가장자리, 가운데, 끝 가장자리.
    private struct Lines { var lo: Double; var mid: Double; var hi: Double }

    private static func lines(_ origin: Double, _ length: Double) -> Lines {
        Lines(lo: origin, mid: origin + length / 2, hi: origin + length)
    }

    /// 끄는 쪽 줄과 상대 줄의 짝(끄는 쪽 값, 상대 값).
    private static func pairs(_ a: Lines, _ b: Lines) -> [(Double, Double)] {
        [(a.lo, b.lo), (a.lo, b.hi), (a.hi, b.lo), (a.hi, b.hi), (a.mid, b.mid)]
    }

    /// 붙는 거리 안에서 가장 조금 움직이면 되는 만큼. 없으면 nil.
    private static func bestDelta(_ a: Lines, _ others: [Lines], _ threshold: Double) -> Double? {
        var best: Double?
        for b in others {
            for (m, o) in pairs(a, b) {
                let d = o - m
                if abs(d) <= threshold, best == nil || abs(d) < abs(best!) { best = d }
            }
        }
        return best
    }

    /// 붙인 뒤 실제로 겹친 줄마다 (위치, 시작, 끝). 같은 줄에 맞은 노드가 여럿이면 선 하나로 잇는다.
    private static func matched(_ a: Lines, _ others: [(Lines, Double, Double)], span: (Double, Double)) -> [(Double, Double, Double)] {
        var out: [(Double, Double, Double)] = []
        for (b, lo, hi) in others {
            for (m, o) in pairs(a, b) where abs(o - m) < 0.01 {
                if let i = out.firstIndex(where: { abs($0.0 - o) < 0.01 }) {
                    out[i].1 = min(out[i].1, lo); out[i].2 = max(out[i].2, hi)
                } else {
                    out.append((o, min(span.0, lo), max(span.1, hi)))
                }
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}
