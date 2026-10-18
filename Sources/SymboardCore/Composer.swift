import Foundation

/// 컴포저: 여러 노드를 한 번에 띄울 때의 배치와 역할 이름.
public enum Composer {
    public static let maxNodes = 12

    /// count 개 노드를 거의 정사각형 격자로 놓는다. center 는 격자 전체의 중심.
    public static func frames(count: Int, center: Point, size: (w: Double, h: Double), gap: Double = 24) -> [Rect] {
        let n = max(0, min(count, maxNodes))
        guard n > 0 else { return [] }
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let totalW = Double(cols) * size.w + Double(cols - 1) * gap
        let totalH = Double(rows) * size.h + Double(rows - 1) * gap
        let x0 = center.x - totalW / 2, y0 = center.y - totalH / 2
        return (0..<n).map { i in
            Rect(x: x0 + Double(i % cols) * (size.w + gap), y: y0 + Double(i / cols) * (size.h + gap), w: size.w, h: size.h)
        }
    }

    /// "Lead, Coder, Reviewer" 같은 입력을 노드 수만큼의 역할로 편다. 모자라면 비워 둔다.
    public static func roles(from text: String, count: Int) -> [String?] {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (0..<count).map { $0 < parts.count ? parts[$0] : nil }
    }

    /// 타일 개수를 n 으로 맞춘다. 늘어나는 타일은 마지막으로 고른 Fill all 값, 없으면 바로 앞 타일 값, 그것도 없으면 fallback.
    public static func resize(tiles: [String], to n: Int, fill: String?, fallback: String) -> [String] {
        let n = max(1, min(maxNodes, n))
        if n <= tiles.count { return Array(tiles.prefix(n)) }
        return tiles + Array(repeating: fill ?? tiles.last ?? fallback, count: n - tiles.count)
    }

    public static let teamColors = ["#5E5CE6", "#30B0C7", "#FF9F0A", "#FF375F", "#34C759", "#BF5AF2"]
}
