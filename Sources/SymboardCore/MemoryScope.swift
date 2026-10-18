import Foundation

/// 메모리 범위: 전역 또는 레포(가장 가까운 .git 이 있는 폴더).
public enum MemoryScope {
    public static func repoRoot(for path: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        var dir = (path as NSString).standardizingPath
        while true {
            if fileExists(dir + "/.git") { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }

    /// 노드에 보낼 글. 제목이 있으면 맨 위에 둔다.
    public static func text(for note: MemoryNote) -> String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = note.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? body : "\(title)\n\(body)"
    }
}

/// 레포 스캔: 에이전트가 한 줄에 하나씩 내는 JSON 사실을 실시간으로 꺼낸다.
public struct FactStream: Sendable {
    public struct Fact: Equatable, Sendable {
        public var category: String
        public var title: String
        public var body: String
        public init(category: String, title: String, body: String) { self.category = category; self.title = title; self.body = body }
    }

    public static let categories = ["Architecture", "Structure", "Commands", "Conventions", "Gotchas", "Context"]
    private var buffer = ""

    public init() {}

    /// 새로 들어온 글 조각을 넣고, 완성된 줄에서 찾은 사실을 돌려준다.
    public mutating func feed(_ text: String) -> [Fact] {
        buffer += text
        var out: [Fact] = []
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<nl])
            buffer.removeSubrange(...nl)
            if let f = Self.parse(line) { out.append(f) }
        }
        return out
    }

    /// 끝났을 때 남은 줄.
    public mutating func finish() -> [Fact] {
        defer { buffer = "" }
        return Self.parse(buffer).map { [$0] } ?? []
    }

    public static func parse(_ raw: String) -> Fact? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- ") { line.removeFirst(2) }
        guard let a = line.firstIndex(of: "{"), let b = line.lastIndex(of: "}"), a < b,
              let obj = try? JSONSerialization.jsonObject(with: Data(line[a...b].utf8)) as? [String: Any],
              let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
              let body = (obj["body"] as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
        let cat = (obj["category"] as? String).flatMap { c in categories.first { $0.lowercased() == c.lowercased() } } ?? "Context"
        return Fact(category: cat, title: title, body: body)
    }
}
