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
