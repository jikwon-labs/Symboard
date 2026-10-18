import Foundation

/// `git status --porcelain=v2 --branch` 결과.
public struct GitStatus: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        /// 두 글자 상태(XY). 추적 안 된 파일은 "??".
        public var code: String
        public var path: String
    }

    public var branch: String
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var changes: [Change]

    public var isClean: Bool { changes.isEmpty }

    public static func parse(_ text: String) -> GitStatus {
        var s = GitStatus(branch: "(unknown)", upstream: nil, ahead: 0, behind: 0, changes: [])
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("# branch.head ") {
                s.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.upstream ") {
                s.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { s.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { s.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("u ") {
                // 1 XY sub mH mI mW hH hI path
                let f = line.split(separator: " ", maxSplits: 8)
                if f.count >= 9 { s.changes.append(Change(code: String(f[1]), path: String(f[8]))) }
            } else if line.hasPrefix("2 ") {
                // 2 XY sub mH mI mW hH hI Xscore path<TAB>orig
                let f = line.split(separator: " ", maxSplits: 9)
                if f.count >= 10 {
                    let path = f[9].split(separator: "\t").first.map(String.init) ?? String(f[9])
                    s.changes.append(Change(code: String(f[1]), path: path))
                }
            } else if line.hasPrefix("? ") {
                s.changes.append(Change(code: "??", path: String(line.dropFirst(2))))
            }
        }
        return s
    }
}

/// git 카드 보조: 로그·줄 수·상태 글자·상대 시간.
public enum GitInfo {
    public struct Commit: Equatable, Sendable {
        public var hash: String
        public var subject: String
        public var author: String
        public var date: Date
    }

    /// 형식 `%h%x1f%s%x1f%an%x1f%ct` 로 받은 줄들.
    public static let logFormat = "%h%x1f%s%x1f%an%x1f%ct"

    public static func parseLog(_ text: String) -> [Commit] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let t = Double(f[3]) else { return nil }
            return Commit(hash: f[0], subject: f[1], author: f[2], date: Date(timeIntervalSince1970: t))
        }
    }

    /// `git diff --numstat` 합계(더한 줄, 뺀 줄). 이진 파일("-")은 0.
    public static func numstat(_ text: String) -> (Int, Int) {
        var a = 0, d = 0
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t")
            guard f.count >= 2 else { continue }
            a += Int(f[0]) ?? 0
            d += Int(f[1]) ?? 0
        }
        return (a, d)
    }

    /// 두 글자 XY 를 화면용 한 글자로: M 수정, A 추가, D 삭제, R 이름 바꿈, U 새 파일(추적 안 됨).
    public static func letter(_ code: String) -> String {
        if code == "??" { return "U" }
        for ch in ["D", "R", "A", "M"] where code.contains(ch) { return ch }
        return "M"
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s") ago" }
        if s < 60 { return plural(max(s, 1), "second") }
        if s < 3600 { return plural(s / 60, "minute") }
        if s < 86400 { return plural(s / 3600, "hour") }
        if s < 86400 * 14 { return plural(s / 86400, "day") }
        if s < 86400 * 60 { return plural(s / (86400 * 7), "week") }
        return plural(s / (86400 * 30), "month")
    }

    /// 고른 파일로 기본 커밋 메시지: "Update 3 files" / "Add a.swift".
    public static func defaultMessage(_ changes: [GitStatus.Change]) -> String {
        if changes.count == 1 {
            let c = changes[0]
            let name = (c.path as NSString).lastPathComponent
            switch letter(c.code) { case "U", "A": return "Add \(name)"; case "D": return "Remove \(name)"; default: return "Update \(name)" }
        }
        let added = changes.filter { ["U", "A"].contains(letter($0.code)) }.count
        let rest = changes.count - added
        var parts: [String] = []
        if added > 0 { parts.append("add \(added) file\(added == 1 ? "" : "s")") }
        if rest > 0 { parts.append("update \(rest) file\(rest == 1 ? "" : "s")") }
        let s = parts.joined(separator: ", ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
