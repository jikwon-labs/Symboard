import Foundation

/// 명령 바에 쓴 보드 명령. 원본의 음성 명령("spawn 5 claude code agents" 등)을 글로 쳐서 쓴다.
/// 모델에 묻지 않고 정해진 꼴만 알아듣는다. 콘솔에 보내는 글과 헷갈리지 않게 `/` 로 시작하거나,
/// 고른 콘솔이 없을 때 첫 낱말이 명령 동사인 경우만 본다(부르는 쪽에서 정한다).
public enum BoardCommand: Equatable, Sendable {
    /// 새 그룹으로 count 개. agent: claude / codex / shell / custom 실행 파일 이름.
    case spawn(count: Int, agent: String)
    /// 그룹(이름 또는 "group 1" 의 번호)에 연결한 오케스트레이터.
    case orchestrator(group: String)
    /// 컴포저 프리셋(번호 1부터 또는 이름 일부).
    case preset(String)
    /// 그룹의 콘솔을 모두 닫는다(확인을 거친다).
    case closeGroup(String)

    static let words: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                       "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    static let agents: [(String, [String])] = [("claude", ["claude"]), ("codex", ["codex"]), ("shell", ["shell", "shells", "terminal", "terminals"])]
    static let fillers: Set<String> = ["can", "you", "please", "now", "me", "for", "the", "a", "an", "put", "in", "board", "on", "called", "named", "with",
                                       "thanks", "thank", "very", "much", "could", "would", "just"]

    public static func parse(_ raw: String) -> BoardCommand? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/") { text.removeFirst() }
        let tokens = text.split(whereSeparator: { " ,.?!".contains($0) }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let verbIndex = tokens.firstIndex { ["spawn", "add", "deploy", "preset", "delete", "remove", "close", "orchestrator", "wire"].contains($0) }
        guard let vi = verbIndex, tokens[..<vi].allSatisfy({ fillers.contains($0) }) else { return nil }
        let verb = tokens[vi]
        let rest = Array(tokens[(vi + 1)...]).filter { !fillers.contains($0) }

        if verb == "spawn" {
            var count = 1
            var agent: String?
            for t in rest {
                if let n = Int(t) ?? words[t] { count = n }
                for (id, names) in agents where names.contains(t) { agent = agent ?? id }
            }
            guard let agent else { return nil }
            return .spawn(count: max(1, min(count, 24)), agent: agent)
        }
        if verb == "orchestrator" || verb == "wire" || (verb == "add" && rest.contains("orchestrator")) {
            guard let g = groupName(after: rest) else { return nil }
            return .orchestrator(group: g)
        }
        if verb == "deploy" || verb == "preset" {
            let r = rest.filter { $0 != "preset" }
            guard let first = r.first else { return nil }
            return .preset((Int(first) ?? words[first]).map(String.init) ?? r.joined(separator: " "))
        }
        if ["delete", "remove", "close"].contains(verb) {
            guard rest.contains("group") || rest.contains("team"), let g = groupName(after: rest) else { return nil }
            return .closeGroup(g)
        }
        return nil
    }

    /// "group 1", "group called backend", "backend group" 에서 이름.
    static func groupName(after rest: [String]) -> String? {
        let cleaned = rest.filter { !["orchestrator", "wired", "wire", "to", "connected"].contains($0) }
        if let i = cleaned.firstIndex(where: { $0 == "group" || $0 == "team" }) {
            let after = cleaned[(i + 1)...]
            if let n = after.first { return (Int(n) ?? words[n]).map { "group \($0)" } ?? after.joined(separator: " ") }
            let before = cleaned[..<i]
            if let b = before.last { return b }
            return nil
        }
        return cleaned.last
    }

    /// 그룹 이름 맞추기: "group 2" 는 두 번째 그룹(또는 이름이 그런 그룹), 아니면 대소문자 없이 같은 이름.
    public static func matchGroup(_ name: String, in groups: [String]) -> Int? {
        let n = name.lowercased()
        if let i = groups.firstIndex(where: { $0.lowercased() == n }) { return i }
        if n.hasPrefix("group "), let k = Int(n.dropFirst(6)), k >= 1, k <= groups.count { return k - 1 }
        return groups.firstIndex { $0.lowercased().hasPrefix(n) }
    }
}

/// 명령 바 THREAD 패널에 쌓이는 한 줄. user 는 사용자가 친 글(오른쪽 말풍선), plan 은 해석한 계획, result 는 결과.
public struct ThreadEntry: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case user, plan, result }
    public let id: UUID
    public var kind: Kind
    public var text: String
    public init(id: UUID = UUID(), kind: Kind, text: String) { self.id = id; self.kind = kind; self.text = text }
}

/// THREAD 패널 기록. 오래된 것부터 버려 limit 개만 남긴다.
public struct CommandThread: Equatable, Sendable {
    public private(set) var entries: [ThreadEntry] = []
    public var limit: Int
    public init(limit: Int = 60) { self.limit = limit }

    public mutating func add(_ kind: ThreadEntry.Kind, _ text: String) {
        entries.append(ThreadEntry(kind: kind, text: text))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public mutating func clear() { entries = [] }
}

extension BoardCommand {
    /// THREAD 의 "Plan · …" 줄에 쓸 짧은 해석.
    public var plan: String {
        switch self {
        case .spawn(let n, let agent): return "Plan · spawn \(n) \(agent) console\(n == 1 ? "" : "s") in a new group"
        case .orchestrator(let g): return "Plan · add an orchestrator wired to \(g)"
        case .preset(let k): return "Plan · deploy preset \(k)"
        case .closeGroup(let g): return "Plan · close every console in \(g)"
        }
    }
}
