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
