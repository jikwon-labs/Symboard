import Foundation

// MARK: 코드 하이라이트

/// 가벼운 문법 색칠. 정확한 파서가 아니라 미리보기용으로 주석·문자열·숫자·키워드만 가른다.
public enum SyntaxHighlighter {
    public enum Kind: String, Sendable { case keyword, string, comment, number }

    public struct Token: Equatable, Sendable {
        public var range: NSRange
        public var kind: Kind
    }

    static let keywords: [String: Set<String>] = [
        "swift": ["import", "let", "var", "func", "struct", "class", "enum", "protocol", "extension", "if", "else", "guard", "return",
                  "for", "in", "while", "switch", "case", "default", "break", "continue", "true", "false", "nil", "self", "Self",
                  "public", "private", "internal", "fileprivate", "static", "final", "override", "init", "throws", "throw", "try",
                  "async", "await", "some", "any", "where", "do", "catch", "defer", "lazy", "weak", "unowned", "mutating"],
        "js": ["import", "export", "from", "const", "let", "var", "function", "return", "if", "else", "for", "while", "switch",
               "case", "default", "break", "continue", "true", "false", "null", "undefined", "class", "extends", "new", "this",
               "async", "await", "try", "catch", "finally", "throw", "typeof", "interface", "type", "enum", "of", "in"],
        "py": ["import", "from", "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
               "True", "False", "None", "with", "as", "try", "except", "finally", "raise", "lambda", "yield", "async", "await", "pass"],
        "sh": ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "export", "local", "in"],
    ]

    public static func language(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "java", "kt", "go", "rs", "c", "h", "cpp", "m", "cs": return "js"
        case "py": return "py"
        case "sh", "bash", "zsh": return "sh"
        default: return nil
        }
    }

    public static func tokens(_ text: String, language: String) -> [Token] {
        let ns = text as NSString
        var out: [Token] = []
        let hashComment = language == "py" || language == "sh"
        let comment = hashComment ? #"#[^\n]*"# : #"//[^\n]*|/\*[\s\S]*?\*/"#
        let string = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#
        // 주석과 문자열을 한 번에 찾아야 문자열 안의 // 를 주석으로 보지 않는다.
        let re = try! NSRegularExpression(pattern: "(\(comment))|(\(string))")
        var covered = IndexSet()
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let kind: Kind = m.range(at: 1).location != NSNotFound ? .comment : .string
            out.append(Token(range: m.range, kind: kind))
            covered.insert(integersIn: m.range.location..<(m.range.location + m.range.length))
        }
        let words = try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b|\b\d+(?:\.\d+)?\b"#)
        let kw = keywords[language] ?? []
        for m in words.matches(in: text, range: NSRange(location: 0, length: ns.length)) where !covered.contains(m.range.location) {
            let w = ns.substring(with: m.range)
            if w.first?.isNumber == true { out.append(Token(range: m.range, kind: .number)) }
            else if kw.contains(w) { out.append(Token(range: m.range, kind: .keyword)) }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }
}

// MARK: 마크다운

public enum Markdown {
    /// 다른 마크다운 파일로 가는 링크 대상. [[이름]] 과 [글](경로.md) 둘 다 본다. 확장자 없는 이름으로 돌려준다.
    public static func links(in text: String) -> [String] {
        var out: [String] = []
        let wiki = try! NSRegularExpression(pattern: #"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]"#)
        let md = try! NSRegularExpression(pattern: #"\]\(([^)\s]+?\.md)(?:#[^)]*)?\)"#)
        let ns = text as NSString
        for m in wiki.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces))
        }
        for m in md.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let path = ns.substring(with: m.range(at: 1))
            if path.contains("://") { continue }
            out.append(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.lowercased()).inserted }
    }

    /// 파일 이름(확장자 없음) → 링크 대상들. 존재하는 파일로 가는 간선만 남긴다.
    public static func graph(_ files: [String: String]) -> [(from: String, to: String)] {
        let names = Dictionary(files.keys.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var edges: [(String, String)] = []
        for (name, text) in files.sorted(by: { $0.key < $1.key }) {
            for l in links(in: text) {
                if let target = names[l.lowercased()], target != name { edges.append((name, target)) }
            }
        }
        return edges
    }

    /// PDF 로 내보낼 HTML. 제목·목록·인용·코드 블록·굵게·기울임·인라인 코드·링크·가로줄만 다룬다.
    public static func html(_ text: String, title: String = "") -> String {
        var body: [String] = []
        var para: [String] = []
        var list: (ordered: Bool, items: [String])?
        var inCode = false
        var code: [String] = []

        func flushPara() {
            if !para.isEmpty { body.append("<p>\(inline(para.joined(separator: " ")))</p>"); para = [] }
        }
        func flushList() {
            if let l = list {
                let tag = l.ordered ? "ol" : "ul"
                body.append("<\(tag)>" + l.items.map { "<li>\(inline($0))</li>" }.joined() + "</\(tag)>")
                list = nil
            }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    body.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>")
                    code = []
                    inCode = false
                } else { flushPara(); flushList(); inCode = true }
                continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { flushPara(); flushList(); continue }
            if let h = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[h] == " " {
                flushPara(); flushList()
                let level = min(6, line.distance(from: line.startIndex, to: h))
                body.append("<h\(level)>\(inline(String(line[h...]).trimmingCharacters(in: .whitespaces)))</h\(level)>")
                continue
            }
            if line == "---" || line == "***" { flushPara(); flushList(); body.append("<hr>"); continue }
            if line.hasPrefix("> ") { flushPara(); flushList(); body.append("<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>"); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushPara()
                if list?.ordered == true { flushList() }
                if list == nil { list = (false, []) }
                list?.items.append(String(line.dropFirst(2)))
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flushPara()
                if list?.ordered == false { flushList() }
                if list == nil { list = (true, []) }
                list?.items.append(String(line[line.index(dot, offsetBy: 2)...]))
                continue
            }
            flushList()
            para.append(line)
        }
        if inCode { body.append("<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>") }
        flushPara(); flushList()
        let css = """
        body{font:12pt -apple-system,Helvetica,sans-serif;line-height:1.5;color:#1d1d1f;margin:40px}
        h1,h2,h3{line-height:1.2}pre{background:#f4f4f6;padding:10px;border-radius:6px;overflow-wrap:anywhere;white-space:pre-wrap}
        code{font:10.5pt Menlo,monospace}blockquote{border-left:3px solid #ccc;margin:0;padding-left:12px;color:#555}
        """
        return "<!doctype html><html><head><meta charset='utf-8'><title>\(escape(title))</title><style>\(css)</style></head><body>\(body.joined(separator: "\n"))</body></html>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func inline(_ s: String) -> String {
        var t = escape(s)
        let rules: [(String, String)] = [
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"\*\*([^*]+)\*\*"#, "<strong>$1</strong>"),
            (#"(?<![*\w])\*([^*]+)\*(?![*\w])"#, "<em>$1</em>"),
            (#"\[\[([^\]]+)\]\]"#, "<em>$1</em>"),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, "<a href=\"$2\">$1</a>"),
        ]
        for (p, r) in rules {
            t = (try! NSRegularExpression(pattern: p)).stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: r)
        }
        return t
    }
}

// MARK: 다이어그램

/// "A -> B: 라벨" 줄로 쓰는 간단한 흐름도.
public struct Diagram: Equatable, Sendable {
    public struct Edge: Equatable, Sendable {
        public var from: String
        public var to: String
        public var label: String
    }

    public var nodes: [String]
    public var edges: [Edge]

    public static func parse(_ text: String) -> Diagram {
        var nodes: [String] = []
        var edges: [Edge] = []
        func add(_ n: String) { if !n.isEmpty && !nodes.contains(n) { nodes.append(n) } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            var main = line
            var label = ""
            if let colon = line.range(of: ":", options: .backwards), line.contains("->") {
                main = String(line[..<colon.lowerBound])
                label = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            let parts = main.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 1 { add(parts[0]); continue }
            for p in parts { add(p) }
            for i in 0..<(parts.count - 1) where !parts[i].isEmpty && !parts[i + 1].isEmpty {
                edges.append(Edge(from: parts[i], to: parts[i + 1], label: i == parts.count - 2 ? label : ""))
            }
        }
        return Diagram(nodes: nodes, edges: edges)
    }

    /// 순환을 만드는 간선(깊이 우선 탐색에서 아직 탐색 중인 노드로 돌아가는 간선). 층을 나눌 때 빼고 본다.
    public func backEdges() -> Set<Int> {
        var state: [String: Int] = [:] // 1 탐색 중, 2 끝
        var back = Set<Int>()
        func visit(_ n: String) {
            state[n] = 1
            for (i, e) in edges.enumerated() where e.from == n {
                switch state[e.to] {
                case 1: back.insert(i)
                case nil: visit(e.to)
                default: break
                }
            }
            state[n] = 2
        }
        for n in nodes where state[n] == nil { visit(n) }
        return back
    }

    /// 왼쪽에서 오른쪽으로 층을 나눈다. 순환 간선을 뺀 그래프에서 들어오는 가장 긴 경로로 층을 정한다.
    public func layers() -> [[String]] {
        let back = backEdges()
        let forward = edges.enumerated().filter { !back.contains($0.offset) && $0.element.from != $0.element.to }.map(\.element)
        var level: [String: Int] = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        for _ in 0..<max(nodes.count, 1) {
            var changed = false
            for e in forward {
                let want = (level[e.from] ?? 0) + 1
                if want > (level[e.to] ?? 0) { level[e.to] = want; changed = true }
            }
            if !changed { break }
        }
        let maxL = level.values.max() ?? 0
        return (0...maxL).map { l in nodes.filter { level[$0] == l } }.filter { !$0.isEmpty }
    }
}
