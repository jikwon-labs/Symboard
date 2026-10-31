import Foundation

/// 에이전트가 JSON 으로 내는 다이어그램. 앱이 보드 위에 손그림풍으로 그린다.
public struct DiagramSpec: Codable, Equatable, Sendable {
    public struct Node: Codable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var sub: String?
        /// "box" 또는 "ellipse"(바깥 요소).
        public var shape: String?
        public var group: String?
        public init(id: String, label: String, sub: String? = nil, shape: String? = nil, group: String? = nil) {
            self.id = id; self.label = label; self.sub = sub; self.shape = shape; self.group = group
        }
    }
    public struct Edge: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public var label: String?
        public init(from: String, to: String, label: String? = nil) { self.from = from; self.to = to; self.label = label }
    }
    public struct Group: Codable, Equatable, Sendable {
        public var id: String
        public var label: String
        public init(id: String, label: String) { self.id = id; self.label = label }
    }

    public var title: String
    public var nodes: [Node]
    public var edges: [Edge]
    public var groups: [Group]?

    public init(title: String, nodes: [Node], edges: [Edge], groups: [Group]? = nil) {
        self.title = title; self.nodes = nodes; self.edges = edges; self.groups = groups
    }

    /// 글 속에서 첫 JSON 객체를 찾아 푼다(코드 울타리·앞뒤 말 무시). 모르는 노드를 가리키는 간선은 뺀다.
    public static func parse(_ text: String) -> DiagramSpec? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              var spec = try? JSONDecoder().decode(DiagramSpec.self, from: Data(text[a...b].utf8)) else { return nil }
        let ids = Set(spec.nodes.map(\.id))
        spec.edges = spec.edges.filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }
        return spec.nodes.isEmpty ? nil : spec
    }

    public struct Layout: Equatable, Sendable {
        public var nodes: [String: Rect]
        public var groups: [String: Rect]
        public var title: Point
    }

    /// 위에서 아래로 층을 나눈 배치. 층 = 순환을 끊은 뒤 가장 긴 경로 길이, 층 안에서는 그룹끼리 모으고 앞 층 평균 위치로 정렬.
    public func layout(origin: Point, nodeW: Double = 230, nodeH: Double = 110, gapX: Double = 70, gapY: Double = 120) -> Layout {
        let ids = nodes.map(\.id)
        var out: [String: [String]] = [:], inc: [String: [String]] = [:]
        for e in edges { out[e.from, default: []].append(e.to); inc[e.to, default: []].append(e.from) }
        // 순환 끊기: DFS 로 되돌아가는 간선 제외.
        var state: [String: Int] = [:]
        var dag: [String: [String]] = [:]
        func dfs(_ v: String) {
            state[v] = 1
            for w in out[v] ?? [] {
                if state[w] == 1 { continue }
                dag[v, default: []].append(w)
                if state[w] == nil { dfs(w) }
            }
            state[v] = 2
        }
        for v in ids where state[v] == nil { dfs(v) }
        var rank: [String: Int] = [:]
        func depth(_ v: String, _ seen: inout Set<String>) -> Int {
            if let r = rank[v] { return r }
            var best = 0
            for (u, ws) in dag where ws.contains(v) && !seen.contains(u) {
                seen.insert(u); best = max(best, depth(u, &seen) + 1); seen.remove(u)
            }
            rank[v] = best
            return best
        }
        for v in ids { var s: Set<String> = [v]; _ = depth(v, &s) }
        let maxRank = rank.values.max() ?? 0
        _ = maxRank
        var rows: [[String]] = Array(repeating: [], count: maxRank + 1)
        for v in ids { rows[rank[v] ?? 0].append(v) }
        // 그룹마다 세로 띠를 따로 준다(그룹 상자끼리 겹치지 않게). 그룹 없는 노드는 마지막 띠.
        let groupOrder = (groups ?? []).map(\.id) + [""]
        let groupOf = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, ($0.group.flatMap { g in groupOrder.contains(g) ? g : nil }) ?? "") })
        var bandWidth: [String: Int] = [:]
        for row in rows {
            var counts: [String: Int] = [:]
            for v in row { counts[groupOf[v] ?? "", default: 0] += 1 }
            for (g, c) in counts { bandWidth[g] = max(bandWidth[g] ?? 0, c) }
        }
        let bandGap = gapX + 40
        let bands = Self.bandOrder(groupOrder.filter { (bandWidth[$0] ?? 0) > 0 },
                                   width: { Double(bandWidth[$0]!) * nodeW + Double(bandWidth[$0]! - 1) * gapX + bandGap },
                                   links: edges.compactMap { e in
                                       let a = groupOf[e.from] ?? "", b = groupOf[e.to] ?? ""
                                       return a == b ? nil : (a, b)
                                   })
        var bandX: [String: Double] = [:]
        var cursor = origin.x
        for g in bands {
            bandX[g] = cursor
            cursor += Double(bandWidth[g]!) * nodeW + Double(bandWidth[g]! - 1) * gapX + bandGap
        }
        // 층·띠 안의 순서. 처음은 받은 순서, 그다음 위→아래(부모 평균 위치)·아래→위(자식 평균 위치)로 몇 번 다시 정렬해 엇갈리는 선을 줄인다.
        var order: [[String: [String]]] = rows.map { row in
            Dictionary(grouping: row, by: { groupOf[$0] ?? "" })
        }
        func positions() -> [String: Double] {
            var x: [String: Double] = [:]
            for r in order.indices {
                for g in bands {
                    guard let members = order[r][g], !members.isEmpty else { continue }
                    let full = Double(bandWidth[g]!) * nodeW + Double(bandWidth[g]! - 1) * gapX
                    let used = Double(members.count) * nodeW + Double(members.count - 1) * gapX
                    var cx = bandX[g]! + (full - used) / 2
                    for v in members { x[v] = cx; cx += nodeW + gapX }
                }
            }
            return x
        }
        for pass in 0..<6 {
            let x = positions()
            let down = pass % 2 == 0
            let rowIdx = down ? Array(order.indices) : Array(order.indices.reversed())
            for r in rowIdx {
                for g in bands {
                    guard let members = order[r][g], members.count > 1 else { continue }
                    order[r][g] = members.enumerated().sorted { a, b in
                        func bary(_ v: String, _ i: Int) -> Double {
                            let ns = (down ? inc[v] : out[v]) ?? []
                            let ps = ns.compactMap { x[$0] }
                            return ps.isEmpty ? (x[v] ?? Double(i)) : ps.reduce(0, +) / Double(ps.count)
                        }
                        let ba = bary(a.element, a.offset), bb = bary(b.element, b.offset)
                        return ba == bb ? a.offset < b.offset : ba < bb
                    }.map(\.element)
                }
            }
        }
        let xpos = positions()
        var result: [String: Rect] = [:]
        for (r, row) in rows.enumerated() {
            for v in row { result[v] = Rect(x: xpos[v]!, y: origin.y + 90 + Double(r) * (nodeH + gapY), w: nodeW, h: nodeH) }
        }
        var groupRects: [String: Rect] = [:]
        for g in groups ?? [] {
            let rs = nodes.filter { $0.group == g.id }.compactMap { result[$0.id] }
            guard !rs.isEmpty else { continue }
            let minX = rs.map(\.x).min()!, minY = rs.map(\.y).min()!
            let maxX = rs.map { $0.x + $0.w }.max()!, maxY = rs.map { $0.y + $0.h }.max()!
            groupRects[g.id] = Rect(x: minX - 28, y: minY - 52, w: maxX - minX + 56, h: maxY - minY + 80)
        }
        return Layout(nodes: result, groups: groupRects, title: Point(x: origin.x, y: origin.y - 10))
    }

    /// 그룹 띠의 왼쪽→오른쪽 순서. 그룹을 넘는 선의 길이 합(띠 가운데끼리 거리)이 가장 짧은 순서를 고른다(11차).
    /// 받은 순서는 에이전트가 적은 순서일 뿐이라, 선이 많이 오가는 그룹이 양 끝에 놓여 긴 선이 화면을 가로질렀다.
    /// 띠가 7개 이하면 모든 순서를 본다(7! = 5040). 더 많으면 받은 순서. 같으면 받은 순서에 가까운 쪽.
    static func bandOrder(_ bands: [String], width: (String) -> Double, links: [(String, String)]) -> [String] {
        guard bands.count > 2, bands.count <= 7, !links.isEmpty else { return bands }
        let w = bands.map(width)
        var best = Array(bands.indices), bestCost = Double.infinity
        var perm = Array(bands.indices)
        let index = Dictionary(uniqueKeysWithValues: bands.enumerated().map { ($0.element, $0.offset) })
        let pairs = links.compactMap { l -> (Int, Int)? in
            guard let a = index[l.0], let b = index[l.1] else { return nil }
            return (a, b)
        }
        func cost(_ p: [Int]) -> Double {
            var center = Array(repeating: 0.0, count: p.count), x = 0.0
            for i in p { center[i] = x + w[i] / 2; x += w[i] }
            // 받은 순서에서 멀어진 만큼 아주 조금 더해, 길이가 같으면 받은 순서를 지킨다.
            let drift = p.enumerated().reduce(0.0) { $0 + abs(Double($1.offset - $1.element)) }
            return pairs.reduce(0.0) { $0 + abs(center[$1.0] - center[$1.1]) } + drift
        }
        func permute(_ k: Int) {
            if k == perm.count {
                let c = cost(perm)
                if c < bestCost { bestCost = c; best = perm }
                return
            }
            for i in k..<perm.count {
                perm.swapAt(k, i); permute(k + 1); perm.swapAt(k, i)
            }
        }
        permute(0)
        return best.map { bands[$0] }
    }

    public static let kinds: [(id: String, title: String, icon: String, ask: String)] = [
        ("architecture", "Architecture", "square.3.layers.3d", "the system architecture: main components, external services and how they connect"),
        ("userflow", "User flow", "figure.walk", "the main user journey through the product, step by step"),
        ("dataflow", "Data flow", "arrow.left.arrow.right", "how data moves from inputs through processing to storage and outputs"),
        ("components", "Components", "square.grid.2x2", "the main modules or UI components and their dependencies"),
        ("request", "Request lifecycle", "clock.arrow.circlepath", "what happens to a single request from the caller to the response"),
        ("state", "State flow", "arrow.triangle.branch", "the important states and the transitions between them"),
    ]

    public static func prompt(kind: String?, describe: String?, repoName: String) -> String {
        let ask = kinds.first { $0.id == kind }?.ask ?? (describe ?? "the project")
        return """
        Look at this repository and draw a diagram of \(ask). Keep it readable: 5 to 12 nodes, short labels.
        Reply with ONLY one JSON object and nothing else, in this shape:
        {"title": "\(repoName) ...", "groups": [{"id": "g1", "label": "CLIENT"}],
         "nodes": [{"id": "n1", "label": "Browser", "sub": "two to four words", "shape": "box or ellipse", "group": "g1"}],
         "edges": [{"from": "n1", "to": "n2", "label": "short verb"}]}
        Use "ellipse" only for things outside the repository (users, browsers, third-party services). Groups are optional.
        """
    }
}
