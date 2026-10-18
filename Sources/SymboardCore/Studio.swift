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
    /// 화면 테마: "paper"(흰 종이, PDF), "dark"(스튜디오 읽기).
    public static func html(_ text: String, title: String = "", theme: String = "paper") -> String {
        var body: [String] = []
        var table: [[String]] = []
        var callout: (kind: String, lines: [String])?
        var para: [String] = []
        var list: (ordered: Bool, items: [String])?
        var inCode = false
        var code: [String] = []

        func flushPara() {
            if !para.isEmpty { body.append("<p>\(inline(para.joined(separator: " ")))</p>"); para = [] }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let rows = table.filter { !$0.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
            if let head = rows.first {
                var h = "<table><thead><tr>" + head.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
                for r in rows.dropFirst() { h += "<tr>" + r.map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }
                body.append(h + "</tbody></table>")
            }
            table = []
        }
        func flushCallout() {
            guard let c = callout else { return }
            body.append("<div class='callout \(c.kind.lowercased())'><div class='callout-title'>\(c.kind.uppercased())</div><p>\(inline(c.lines.joined(separator: " ")))</p></div>")
            callout = nil
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
            if line.hasPrefix("|") && line.hasSuffix("|") && line.count > 1 {
                flushPara(); flushList(); flushCallout()
                table.append(line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            flushTable()
            if line.hasPrefix(">"), let m = line.range(of: #"^>\s*\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION)\]"#, options: .regularExpression) {
                flushPara(); flushList(); flushCallout()
                let kind = line[m].replacingOccurrences(of: #"[>\s\[\]!]"#, with: "", options: .regularExpression)
                callout = (kind, [String(line[m.upperBound...]).trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty })
                continue
            }
            if callout != nil, line.hasPrefix(">") { callout?.lines.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)); continue }
            flushCallout()
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
        flushPara(); flushList(); flushTable(); flushCallout()
        let dark = theme == "dark"
        let fg = dark ? "#ECE7E2" : "#1d1d1f", dim = dark ? "#8F8882" : "#555", line = dark ? "#2E2B28" : "#e3e1de"
        let codeBg = dark ? "#1F1D1B" : "#f4f2ef", page = dark ? "#121110" : "#ffffff"
        let css = """
        body{font:\(dark ? "14px" : "12pt") -apple-system,Helvetica,sans-serif;line-height:1.6;color:\(fg);background:\(page);margin:\(dark ? "28px 40px" : "40px")}
        h1,h2,h3{line-height:1.25;margin:1.2em 0 .5em}
        h1:after,h2:after{content:"";display:block;width:56px;height:3px;border-radius:2px;background:#F05A38;margin-top:8px}
        pre{background:\(codeBg);padding:12px;border-radius:8px;overflow-wrap:anywhere;white-space:pre-wrap}
        code{font:\(dark ? "12.5px" : "10.5pt") Menlo,monospace}
        p code,li code,td code{color:#F05A38;background:\(dark ? "rgba(240,90,56,.10)" : "rgba(240,90,56,.08)");padding:1px 5px;border-radius:4px}
        blockquote{border-left:3px solid \(line);margin:0;padding-left:12px;color:\(dim)}
        table{border-collapse:separate;border-spacing:0;width:100%;border:1px solid \(line);border-radius:10px;overflow:hidden;margin:1em 0}
        th{text-align:left;font-weight:600;background:\(codeBg)}th,td{padding:8px 12px;border-top:1px solid \(line);vertical-align:top}
        thead th{border-top:none}
        .callout{border:1px solid \(line);border-left:4px solid #56A8F5;border-radius:8px;padding:10px 14px;margin:1em 0;background:\(dark ? "rgba(86,168,245,.08)" : "#f3f8fe")}
        .callout.tip{border-left-color:#3E8E5A;background:\(dark ? "rgba(111,207,151,.08)" : "#f1faf4")}
        .callout.warning,.callout.caution{border-left-color:#E9C46A;background:\(dark ? "rgba(233,196,106,.08)" : "#fdf8ea")}
        .callout-title{font:600 11px -apple-system;letter-spacing:.08em;color:\(dim);margin-bottom:4px}.callout p{margin:0}
        a{color:#F05A38}hr{border:none;border-top:1px solid \(line)}
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

extension Markdown {
    /// 낱말 수(코드 블록 포함, 기호만 있는 토큰은 뺀다)와 읽는 데 걸리는 분(분당 200낱말, 최소 1).
    public static func wordCount(_ text: String) -> (words: Int, minutes: Int) {
        let words = text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
        return (words, max(1, Int((Double(words) / 200).rounded())))
    }
}

/// 링크 그래프용 힘 기반 배치. 같은 입력이면 같은 결과(씨앗 고정).
public enum ForceLayout {
    public static func run(count: Int, edges: [(Int, Int)], width: Double, height: Double, iterations: Int = 240) -> [Point] {
        guard count > 0 else { return [] }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11) / Double(1 << 53) }
        var p = (0..<count).map { _ in Point(x: width * (0.25 + 0.5 * rnd()), y: height * (0.25 + 0.5 * rnd())) }
        let k = sqrt(width * height / Double(count)) * 0.6
        var temp = width / 8
        for _ in 0..<iterations {
            var d = Array(repeating: Point(x: 0, y: 0), count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var dx = p[i].x - p[j].x, dy = p[i].y - p[j].y
                    var dist = hypot(dx, dy)
                    if dist < 0.01 { dx = 0.01; dy = 0; dist = 0.01 }
                    let f = k * k / dist
                    d[i].x += dx / dist * f; d[i].y += dy / dist * f
                    d[j].x -= dx / dist * f; d[j].y -= dy / dist * f
                }
            }
            for (a, b) in edges where a < count && b < count && a != b {
                let dx = p[a].x - p[b].x, dy = p[a].y - p[b].y
                let dist = max(hypot(dx, dy), 0.01)
                let f = dist * dist / k
                d[a].x -= dx / dist * f; d[a].y -= dy / dist * f
                d[b].x += dx / dist * f; d[b].y += dy / dist * f
            }
            for i in 0..<count {
                // 가운데로 살짝 당겨 흩어지지 않게.
                d[i].x += (width / 2 - p[i].x) * 0.06 * k / 10
                d[i].y += (height / 2 - p[i].y) * 0.06 * k / 10
                let len = max(hypot(d[i].x, d[i].y), 0.01)
                p[i].x = min(width - 20, max(20, p[i].x + d[i].x / len * min(len, temp)))
                p[i].y = min(height - 20, max(20, p[i].y + d[i].y / len * min(len, temp)))
            }
            temp = max(0.5, temp * 0.97)
        }
        return p
    }
}

extension Markdown {
    /// html() 결과에서 <body> 안쪽만(실시간 갱신용).
    public static func bodyHTML(_ text: String) -> String {
        let h = html(text)
        guard let a = h.range(of: "<body>"), let b = h.range(of: "</body>", options: .backwards) else { return h }
        return String(h[a.upperBound..<b.lowerBound])
    }

    /// 첫 번째 # 제목.
    public static func firstHeading(_ text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

/// 문서 스튜디오의 문서 종류와 생성 지시.
public struct DocKind: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var blurb: String
    public var icon: String
    public var focus: String

    public static let all: [DocKind] = [
        DocKind(id: "overview", title: "Overview", blurb: "The repo in one sitting", icon: "doc.text",
                focus: "what the project is for, its main features, the technologies it uses and how the major parts fit together"),
        DocKind(id: "start", title: "Getting started", blurb: "From clone to first change", icon: "figure.walk",
                focus: "prerequisites, setup, running it locally, where to make a first change and how to verify it"),
        DocKind(id: "architecture", title: "Architecture", blurb: "Modules, layers and data flow", icon: "square.3.layers.3d",
                focus: "modules and layers, how data and requests flow through them, and the important boundaries"),
        DocKind(id: "readme", title: "README", blurb: "A front page for the repo", icon: "text.alignleft",
                focus: "a polished README: short pitch, features, quick start, usage examples and project layout"),
        DocKind(id: "api", title: "API guide", blurb: "Public surface and how to call it", icon: "curlybraces",
                focus: "the public API or CLI surface, parameters, return values and short usage examples"),
        DocKind(id: "data", title: "Data model", blurb: "Entities and how they relate", icon: "cylinder",
                focus: "the data entities, their fields, relationships and where they are stored"),
        DocKind(id: "security", title: "Security notes", blurb: "Trust boundaries and risks", icon: "lock.shield",
                focus: "trust boundaries, secrets handling, input validation and the main risks with mitigations"),
    ]

    /// 깊이: quick·balanced·thorough.
    public static func prompt(kind: DocKind?, request: String?, depth: String, repoName: String) -> String {
        let size: String
        switch depth {
        case "quick": size = "Keep it to roughly 300 words. Look only at the README, manifests and the top-level layout."
        case "thorough": size = "Aim for roughly 1500 words. Read broadly across the source before writing."
        default: size = "Aim for roughly 700 words. Read the README, manifests and the key source files."
        }
        let topic = kind.map { "Write a \($0.title) document for this repository covering \($0.focus)." }
            ?? "Write a document for this repository: \(request ?? "")"
        return """
        \(topic)
        \(size)
        Write GitHub-flavored Markdown only, with no preamble and no closing remarks. Start with a single line "# \(repoName) \(kind?.title ?? "Notes")". \
        Use ## sections, tables where they help, `inline code` for paths and commands, and at most two callouts written as "> [!NOTE] ..." or "> [!TIP] ...". \
        Only state what you can see in the repository. End with a "## Summary" section.
        """
    }
}
