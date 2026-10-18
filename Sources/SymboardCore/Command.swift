import Foundation

/// 아래 명령 바 입력을 대상과 본문으로 나눈다. `@이름` 은 노드 이름·팀 이름·`all` 중 하나.
public struct CommandTargets: Equatable, Sendable {
    public var nodeIDs: [UUID]
    public var body: String
    /// @ 로 적었는데 맞는 대상이 없는 이름.
    public var unknown: [String]
    /// @ 를 하나도 쓰지 않았는지.
    public var implicit: Bool

    public init(nodeIDs: [UUID], body: String, unknown: [String], implicit: Bool) {
        self.nodeIDs = nodeIDs; self.body = body; self.unknown = unknown; self.implicit = implicit
    }

    public struct Candidate: Sendable {
        public var id: UUID
        public var name: String
        public var team: String?
        public init(id: UUID, name: String, team: String?) { self.id = id; self.name = name; self.team = team }
    }

    /// 입력 맨 앞에 이어 붙은 @ 토큰만 대상으로 본다. 본문 중간의 @ 는 그대로 둔다.
    public static func parse(_ input: String, candidates: [Candidate]) -> CommandTargets {
        var words = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var ids: [UUID] = []
        var unknown: [String] = []
        var sawTarget = false
        while let w = words.first, w.hasPrefix("@"), w.count > 1 {
            words.removeFirst()
            sawTarget = true
            let name = String(w.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",:")).lowercased()
            let hits: [UUID]
            if name == "all" {
                hits = candidates.map(\.id)
            } else {
                let byName = candidates.filter { $0.name.lowercased() == name }.map(\.id)
                hits = byName.isEmpty ? candidates.filter { $0.team?.lowercased() == name }.map(\.id) : byName
            }
            if hits.isEmpty { unknown.append(name) }
            for h in hits where !ids.contains(h) { ids.append(h) }
        }
        let body = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return CommandTargets(nodeIDs: ids, body: body, unknown: unknown, implicit: !sawTarget)
    }

    /// 입력 끝에서 쓰고 있는 @ 토큰(자동 완성용). 없으면 nil.
    public static func pendingMention(in input: String) -> String? {
        guard let last = input.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }
}

/// 작업공간을 프로젝트 폴더로 묶는다.
public enum Projects {
    /// 프로젝트가 없는(1차) 작업공간에 붙일 폴더: 터미널 노드 폴더 중 가장 많은 것, 없으면 대체값.
    public static func inferPath(for ws: Workspace, fallback: String) -> String {
        var counts: [String: Int] = [:]
        for n in ws.nodes { if let c = n.terminal?.cwd { counts[c, default: 0] += 1 } }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key ?? fallback
    }

    /// 최근에 쓴 순서(작업공간 배열 순서)로 프로젝트 폴더 목록.
    public static func paths(in workspaces: [Workspace]) -> [String] {
        var seen: [String] = []
        for ws in workspaces { if let p = ws.projectPath, !seen.contains(p) { seen.append(p) } }
        return seen
    }
}

/// 콘솔에 붙이는 짧은 사람 이름.
public enum NamePool {
    public static let names = ["Ada", "Pip", "Maya", "Iris", "Dax", "Rafa", "Kai", "Zoe", "Leo", "Nova", "Otto", "Juno",
                               "Remy", "Tess", "Ivo", "Lena", "Bo", "Cleo", "Hugo", "Mira", "Nico", "Suki", "Theo", "Wren"]

    /// 쓰지 않은 첫 이름. 다 쓰면 숫자를 붙인다.
    public static func next(used: Set<String>) -> String {
        if let n = names.first(where: { !used.contains($0) }) { return n }
        var i = 2
        while true {
            for n in names where !used.contains("\(n)\(i)") { return "\(n)\(i)" }
            i += 1
        }
    }
}

/// 권한 묻기를 끄는 실행 옵션이 들어 있는지(헤더 배지용).
public enum PermissionMode {
    public static let autoFlags = ["--dangerously-skip-permissions", "--yolo", "--dangerously-bypass-approvals-and-sandbox", "--full-auto"]

    public static func label(for spec: TerminalSpec) -> String? {
        if spec.extraArgs.contains(where: { autoFlags.contains($0) }) { return "AUTO" }
        if let i = spec.extraArgs.firstIndex(of: "--permission-mode"), i + 1 < spec.extraArgs.count {
            switch spec.extraArgs[i + 1] {
            case "bypassPermissions": return "AUTO"
            case "acceptEdits": return "EDITS"
            case "plan": return "PLAN"
            default: return nil
            }
        }
        return nil
    }
}

/// 다시 열었을 때 "이어 할까요?" 를 물을 콘솔.
public enum ResumePolicy {
    public static func canResume(_ spec: TerminalSpec?) -> Bool {
        guard let spec, spec.hasLaunched, spec.sessionID != nil else { return false }
        return spec.agent == .claude || spec.agent == .codex
    }

    public static func candidates(in state: AppState) -> [UUID] {
        state.workspaces.flatMap { $0.nodes.filter { $0.kind == .terminal && canResume($0.terminal) }.map(\.id) }
    }
}

/// 칸반 카드 옮기기·달력 계산.
public enum Board {
    /// 카드를 다른(또는 같은) 열의 index 자리로 옮긴다. 1차 글자 카드는 이때 items 로 바뀐다.
    public static func move(card id: UUID, to column: UUID, at index: Int?, in columns: inout [KanbanColumn]) {
        for i in columns.indices where columns[i].items == nil { columns[i].items = columns[i].allCards; columns[i].cards = [] }
        guard let from = columns.firstIndex(where: { $0.items!.contains { $0.id == id } }),
              let to = columns.firstIndex(where: { $0.id == column }) else { return }
        let fi = columns[from].items!.firstIndex { $0.id == id }!
        let card = columns[from].items!.remove(at: fi)
        var at = min(index ?? columns[to].items!.count, columns[to].items!.count)
        if from == to && index != nil && fi < at { at = max(0, at - 1) }
        columns[to].items!.insert(card, at: min(at, columns[to].items!.count))
    }

    /// 월 격자(월요일 시작, 6주 42칸). 그달이 아닌 날도 채운다.
    public static func monthGrid(for date: Date, calendar: Calendar) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        let first = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }
}

/// 펜 획 다듬기.
public enum Ink {
    /// 너무 가까운 점을 뺀다.
    public static func simplify(_ pts: [Point], minDistance: Double = 1.5) -> [Point] {
        guard var last = pts.first else { return [] }
        var out = [last]
        for p in pts.dropFirst() where hypot(p.x - last.x, p.y - last.y) >= minDistance {
            out.append(p); last = p
        }
        if let l = pts.last, out.count > 1, out.last != l { out.append(l) }
        return out
    }

    /// Catmull-Rom 을 3차 베지어 조각으로. 각 조각은 (끝점, 제어점1, 제어점2).
    public static func bezier(_ pts: [Point]) -> [(Point, Point, Point)] {
        guard pts.count > 2 else { return pts.dropFirst().map { ($0, $0, $0) } }
        var out: [(Point, Point, Point)] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = Point(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = Point(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            out.append((p2, c1, c2))
        }
        return out
    }

    /// 점 p 가 획 가까이(반경 r)에 있는지. 선분 거리로 본다.
    public static func hits(_ s: Stroke, _ p: Point, radius r: Double) -> Bool {
        let rr = r + s.width / 2
        if s.points.count == 1 { return hypot(s.points[0].x - p.x, s.points[0].y - p.y) <= rr }
        for i in 0..<(s.points.count - 1) {
            let a = s.points[i], b = s.points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            if hypot(a.x + t * dx - p.x, a.y + t * dy - p.y) <= rr { return true }
        }
        return false
    }
}

/// 웹 타일 표시 크기 프리셋.
public struct DevicePreset: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var width: Double
    public var height: Double
    public var group: String

    public static let all: [DevicePreset] = [
        DevicePreset(id: "24in", name: "24\" 4K", width: 1920, height: 1080, group: "Monitor"),
        DevicePreset(id: "27in", name: "27\" 4K", width: 2560, height: 1440, group: "Monitor"),
        DevicePreset(id: "32in", name: "32\" 4K", width: 3008, height: 1692, group: "Monitor"),
        DevicePreset(id: "laptop", name: "Laptop", width: 1512, height: 982, group: "Monitor"),
        DevicePreset(id: "phone", name: "Phone", width: 393, height: 852, group: "Phone"),
        DevicePreset(id: "phone-max", name: "Phone Max", width: 430, height: 932, group: "Phone"),
        DevicePreset(id: "tablet", name: "Tablet", width: 820, height: 1180, group: "Tablet"),
    ]

    public static func find(_ id: String?) -> DevicePreset? { all.first { $0.id == id } }

    /// 타일 영역 안에 프리셋 비율로 맞춘 사각형과 축소 배율(pageZoom).
    public func fit(in w: Double, _ h: Double) -> (x: Double, y: Double, w: Double, h: Double, zoom: Double) {
        let z = min(w / width, h / height)
        let fw = width * z, fh = height * z
        return ((w - fw) / 2, (h - fh) / 2, fw, fh, z)
    }
}

/// 주소창 입력을 URL 로. 포트만 쓰면 localhost.
public enum WebAddress {
    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        if s.hasPrefix(":"), Int(s.dropFirst()) != nil { s = "localhost" + s }
        if Int(s) != nil { s = "localhost:" + s }
        if !s.contains("://") {
            let host = s.split(separator: "/").first.map(String.init) ?? s
            let local = host.hasPrefix("localhost") || host.hasPrefix("127.") || host.hasPrefix("0.0.0.0")
            s = (local ? "http://" : "https://") + s
        }
        return s
    }
}
