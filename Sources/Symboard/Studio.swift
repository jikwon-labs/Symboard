import AppKit
import SwiftUI
import WebKit
import SymboardCore

// MARK: 파일 트리

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDir: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }

    static let skipped: Set<String> = [".git", ".build", "node_modules", ".swiftpm", "build", "DerivedData", ".next", "dist", "Pods"]

    /// 폴더 안 항목. onlyMarkdown 이면 .md 파일과 폴더만.
    func children(onlyMarkdown: Bool) -> [FileItem]? {
        guard isDir else { return nil }
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { u -> FileItem? in
            let dir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if dir && Self.skipped.contains(u.lastPathComponent) { return nil }
            if onlyMarkdown && !dir && u.pathExtension.lowercased() != "md" { return nil }
            return FileItem(url: u, isDir: dir)
        }
        .sorted { ($0.isDir ? 0 : 1, $0.name.lowercased()) < ($1.isDir ? 0 : 1, $1.name.lowercased()) }
    }

    /// 아래에 있는 모든 마크다운 파일(최대 limit 개).
    static func markdownFiles(under root: URL, limit: Int = 400) -> [URL] {
        var out: [URL] = []
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        for case let u as URL in e {
            if skipped.contains(u.lastPathComponent) { e.skipDescendants(); continue }
            if u.pathExtension.lowercased() == "md" { out.append(u) }
            if out.count >= limit { break }
        }
        return out
    }
}

struct FileTreeView: View {
    let root: URL
    let onlyMarkdown: Bool
    @Binding var selection: URL?

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(FileItem(url: root, isDir: true).children(onlyMarkdown: onlyMarkdown) ?? [], children: onlyMarkdown ? \FileItem.mdChildren : \FileItem.allChildren) { item in
                Label(item.name, systemImage: item.isDir ? "folder" : "doc.text")
                    .font(.system(size: 12))
                    .tag(item.url)
            }
        }
        .listStyle(.sidebar)
    }
}

extension FileItem {
    var mdChildren: [FileItem]? { children(onlyMarkdown: true) }
    var allChildren: [FileItem]? { children(onlyMarkdown: false) }
}

// MARK: 하이라이트된 코드 보기

enum CodeStyle {
    static func attributed(_ text: String, ext: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let s = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: Theme.text])
        if ext.lowercased() == "md", text.utf16.count < 400_000 { return markdown(s) }
        guard let lang = SyntaxHighlighter.language(forExtension: ext), text.utf16.count < 400_000 else { return s }
        for t in SyntaxHighlighter.tokens(text, language: lang) {
            let color: NSColor
            switch t.kind {
            case .keyword: color = NSColor(srgbRed: 0.99, green: 0.37, blue: 0.64, alpha: 1)
            case .string: color = NSColor(srgbRed: 0.99, green: 0.55, blue: 0.40, alpha: 1)
            case .comment: color = NSColor(srgbRed: 0.45, green: 0.52, blue: 0.45, alpha: 1)
            case .number: color = NSColor(srgbRed: 0.82, green: 0.75, blue: 0.45, alpha: 1)
            }
            s.addAttribute(.foregroundColor, value: color, range: t.range)
        }
        return s
    }

    /// 마크다운 원문 색: 제목·인라인 코드·굵게·링크·목록 기호.
    static func markdown(_ s: NSMutableAttributedString) -> NSAttributedString {
        let str = s.string as NSString
        let rules: [(String, NSColor)] = [
            (#"(?m)^#{1,6} .*$"#, Theme.accent),
            (#"`[^`\n]+`"#, NSColor(hex: "#E9C46A")),
            (#"\*\*[^*\n]+\*\*"#, NSColor(hex: "#ECE7E2")),
            (#"\[[^\]\n]+\]\([^)\n]+\)|\[\[[^\]\n]+\]\]"#, NSColor(hex: "#56A8F5")),
            (#"(?m)^\s*([-*]|\d+\.) "#, Theme.accent),
            (#"(?m)^>.*$"#, Theme.textDim),
            (#"(?m)^\|.*\|$"#, NSColor(hex: "#B48CF2")),
        ]
        for (p, col) in rules {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            for m in re.matches(in: s.string, range: NSRange(location: 0, length: str.length)) { s.addAttribute(.foregroundColor, value: col, range: m.range) }
        }
        return s
    }

    static func load(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "(cannot read file)" }
        if data.count > 2_000_000 { return "(file is too large to preview)" }
        if data.prefix(4096).contains(0) { return "(binary file)" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct CodeTextView: NSViewRepresentable {
    var text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        scroll.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.attributedString() != text { tv.textStorage?.setAttributedString(text) }
    }
}

/// 보드에 놓은 파일 카드: 코드는 줄 번호와 구문 색, 마크다운은 읽기 보기.
final class FileContent: NodeContent {
    let path: String
    let host: NSHostingView<AnyView>
    var view: NSView { host }

    init(node: BoardNode) {
        path = node.text ?? ""
        host = CanvasHostingView(rootView: AnyView(EmptyView()))
        reload()
    }

    private func reload() {
        let url = URL(fileURLWithPath: path)
        host.rootView = AnyView(FileCardView(url: url, text: CodeStyle.load(url)).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Open in Studio") { [weak self] in
             guard let self, let c = (NSApp.delegate as? AppDelegate)?.windowController else { return }
             c.openStudio(file: URL(fileURLWithPath: self.path))
         },
         ClosureMenuItem(title: "Reload File") { [weak self] in self?.reload() },
         ClosureMenuItem(title: "Reveal in Finder") { [weak self] in
             guard let self else { return }
             NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: self.path)])
         }]
    }
}

struct FileCardView: View {
    let url: URL
    @State var text: String

    /// 지금 프로젝트 폴더 기준 경로(밖이면 전체 경로).
    var relativePath: String {
        let root = ((NSApp.delegate as? AppDelegate)?.windowController.projectPath ?? "") + "/"
        return url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count)) : url.path
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(url.pathExtension.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: "#56A8F5"))
                    .padding(.horizontal, 4).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#56A8F5").opacity(0.15)))
                Text(url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim).lineLimit(1)
                Spacer()
                Text("\(text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)) lines").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
                if url.pathExtension.lowercased() != "md" {
                    Button { (NSApp.delegate as? AppDelegate)?.windowController.openStudio(file: url) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Open in studio")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            if url.pathExtension.lowercased() == "md" {
                HTMLPreview(html: Markdown.html(text, title: url.lastPathComponent, theme: "dark"), base: url.deletingLastPathComponent())
                // 원본처럼 바닥에 프로젝트 기준 경로와 "Open in Studio · PDF" 글 단추.
                HStack(spacing: 12) {
                    Text(relativePath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button { (NSApp.delegate as? AppDelegate)?.windowController.openStudio(file: url) } label: {
                        Label("Open in Studio", systemImage: "rectangle.portrait.and.arrow.right").font(.system(size: 11))
                    }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symText.opacity(0.8)).axName("Open in Studio")
                    Button { (NSApp.delegate as? AppDelegate)?.windowController.exportCardPDF(url) } label: {
                        Label("PDF", systemImage: "doc").font(.system(size: 11))
                    }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symText.opacity(0.8)).axName("PDF")
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            } else {
                CodeEditor(text: $text, ext: url.pathExtension, editable: false).padding(6)
            }
        }
        .background(Color.symSurface)
    }
}

// MARK: 스튜디오 상태

@MainActor
final class StudioModel: ObservableObject {
    @Published var tab = "Code"
    @Published var root: URL
    @Published var codeSelection: URL?
    @Published var mdSelection: URL? { didSet { loadMarkdown() } }
    @Published var mdText = "" { didSet { scheduleMarkdownSave() } }
    @Published var mdSavedNote = ""
    @Published var showGraph = false
    @Published var diagramText = "# One edge per line: From -> To: label\nUser -> Symboard: opens board\nSymboard -> Claude Code: launches\nSymboard -> Codex: launches\nClaude Code -> Hooks: status\nHooks -> Symboard: working / idle\n"
    @Published var status = ""
    var pinToBoard: ((URL) -> Void)?
    private var loadingMarkdown = false
    private var saveWork: DispatchWorkItem?

    init(root: URL) { self.root = root }

    func chooseRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = root
        if p.runModal() == .OK, let u = p.url { root = u; codeSelection = nil; mdSelection = nil }
    }

    // 마크다운 편집기: 0.6초 쉬면 자동 저장.
    private func loadMarkdown() {
        saveNowIfPending()
        loadingMarkdown = true
        mdText = mdSelection.map { CodeStyle.load($0) } ?? ""
        loadingMarkdown = false
        mdSavedNote = ""
    }

    private func scheduleMarkdownSave() {
        guard !loadingMarkdown, let url = mdSelection else { return }
        saveWork?.cancel()
        let text = mdText
        let work = DispatchWorkItem { [weak self] in
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                self?.mdSavedNote = "Saved \(LoopRunner.time(Date()))"
            } catch { self?.mdSavedNote = "Save failed: \(error.localizedDescription)" }
            self?.saveWork = nil
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNowIfPending() {
        guard let w = saveWork else { return }
        w.perform()
        w.cancel()
    }

    // 링크 그래프.
    func graph() -> (nodes: [String], edges: [(from: String, to: String)], paths: [String: URL]) {
        var files: [String: String] = [:]
        var paths: [String: URL] = [:]
        for u in FileItem.markdownFiles(under: root) {
            let name = u.deletingPathExtension().lastPathComponent
            if files[name] != nil { continue }
            files[name] = CodeStyle.load(u)
            paths[name] = u
        }
        return (files.keys.sorted(), Markdown.graph(files), paths)
    }

    // 문서: 마크다운 → PDF.
    private var pdfWebView: WKWebView?
    private var pdfDelegate: PDFLoadDelegate?

    func exportPDF(from md: URL, to out: URL, done: @escaping (Bool) -> Void) {
        let html = Markdown.html(CodeStyle.load(md), title: md.deletingPathExtension().lastPathComponent)
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let delegate = PDFLoadDelegate { [weak self] in
            // 웹 내용 전체를 긴 한 장으로 받은 뒤 Letter 크기 쪽으로 잘라 붙인다.
            // (화면 밖 WKWebView 의 printOperation 은 쪽 나누기가 끝나지 않아 파일이 끝없이 커졌다.)
            web.createPDF { result in
                MainActor.assumeIsolated {
                    var ok = false
                    if case .success(let data) = result { ok = Self.paginate(data, to: out) }
                    self?.pdfWebView = nil
                    self?.pdfDelegate = nil
                    done(ok)
                }
            }
        }
        web.navigationDelegate = delegate
        pdfWebView = web
        pdfDelegate = delegate
        web.loadHTMLString(html, baseURL: md.deletingLastPathComponent())
    }

    /// 긴 한 장 PDF 를 612x792 쪽들로 자른다. 쪽 수는 최대 300.
    nonisolated static func paginate(_ data: Data, to out: URL) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData), let src = CGPDFDocument(provider),
              let page = src.page(at: 1) else { return false }
        let box = page.getBoxRect(.mediaBox)
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 36
        let scale = min(1, (pageSize.width - margin * 2) / max(box.width, 1))
        let sliceH = (pageSize.height - margin * 2) / scale
        let count = min(300, max(1, Int(ceil(box.height / sliceH))))
        var media = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(out as CFURL, mediaBox: &media, nil) else { return false }
        for i in 0..<count {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2))
            // PDF 좌표는 아래가 0 이다. i 번째 조각의 위쪽이 쪽 위 여백에 오도록 옮긴다.
            let top = box.height - CGFloat(i) * sliceH
            ctx.translateBy(x: margin, y: pageSize.height - margin)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -top - box.minY)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return true
    }

    // 다이어그램 → PNG.
    func exportPNG(to out: URL) -> Bool {
        let renderer = ImageRenderer(content: DiagramView(diagram: Diagram.parse(diagramText)).padding(20).background(Color(white: 0.1)))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: out)) != nil
    }
}

final class PDFLoadDelegate: NSObject, WKNavigationDelegate {
    let onLoad: () -> Void
    init(onLoad: @escaping () -> Void) { self.onLoad = onLoad }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { self.onLoad() }
    }
}

// MARK: 화면

struct StudioView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $model.tab) {
                    ForEach(["Code", "Markdown", "Docs", "Diagram"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                Spacer()
                Text(model.root.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Button("Folder...") { model.chooseRoot() }.axName("Folder...")
            }
            .padding(8)
            Divider()
            switch model.tab {
            case "Code": CodeTab(model: model)
            case "Markdown": MarkdownTab(model: model)
            case "Docs": DocsTab(model: model)
            default: DiagramTab(model: model)
            }
            if !model.status.isEmpty {
                Divider()
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct CodeTab: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HSplitView {
            FileTreeView(root: model.root, onlyMarkdown: false, selection: $model.codeSelection)
                .id(model.root)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            VStack(spacing: 0) {
                if let u = model.codeSelection, !((try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
                    HStack {
                        Text(u.lastPathComponent).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Pin to Board") { model.pinToBoard?(u) }.axName("Pin to Board")
                    }
                    .padding(6)
                    CodeTextView(text: CodeStyle.attributed(CodeStyle.load(u), ext: u.pathExtension))
                } else {
                    Text("Select a file").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct MarkdownTab: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HSplitView {
            FileTreeView(root: model.root, onlyMarkdown: true, selection: $model.mdSelection)
                .id(model.root)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            VStack(spacing: 0) {
                HStack {
                    Text(model.mdSelection?.lastPathComponent ?? "No file").font(.system(size: 12, weight: .semibold))
                    Text(model.mdSavedNote).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Link graph", isOn: $model.showGraph).toggleStyle(.switch).controlSize(.small)
                }
                .padding(6)
                if model.showGraph {
                    LinkGraphView(model: model)
                } else if model.mdSelection != nil {
                    TextEditor(text: $model.mdText)
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    Text("Select a markdown file. Edits save automatically.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct LinkGraphView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        let g = model.graph()
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = max(60, min(geo.size.width, geo.size.height) / 2 - 70)
            let pos: [String: CGPoint] = Dictionary(uniqueKeysWithValues: g.nodes.enumerated().map { i, n in
                let a = Double(i) / Double(max(g.nodes.count, 1)) * 2 * .pi - .pi / 2
                return (n, CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
            })
            let degree = Dictionary(g.edges.flatMap { [$0.from, $0.to] }.map { ($0, 1) }, uniquingKeysWith: +)
            ZStack {
                Canvas { ctx, _ in
                    for e in g.edges {
                        guard let a = pos[e.from], let b = pos[e.to] else { continue }
                        var p = Path()
                        p.move(to: a)
                        p.addLine(to: b)
                        ctx.stroke(p, with: .color(.gray.opacity(0.6)), lineWidth: 1.2)
                    }
                }
                ForEach(g.nodes, id: \.self) { n in
                    let selected = model.mdSelection?.deletingPathExtension().lastPathComponent == n
                    Button {
                        model.showGraph = false
                        model.mdSelection = g.paths[n]
                    } label: {
                        VStack(spacing: 3) {
                            Circle().fill(selected ? Color.accentColor : Color.purple.opacity(0.8))
                                .frame(width: CGFloat(10 + min(degree[n] ?? 0, 8) * 3), height: CGFloat(10 + min(degree[n] ?? 0, 8) * 3))
                            Text(n).font(.system(size: 10)).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plainHit)
                    .position(pos[n] ?? center)
                }
                if g.nodes.isEmpty { Text("No markdown files in this folder").foregroundStyle(.secondary) }
            }
        }
    }
}

struct DocsTab: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HSplitView {
            FileTreeView(root: model.root, onlyMarkdown: true, selection: $model.mdSelection)
                .id(model.root)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            VStack(spacing: 0) {
                HStack {
                    Text(model.mdSelection?.lastPathComponent ?? "Pick a markdown file").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Export PDF...") { export() }.disabled(model.mdSelection == nil).axName("Export PDF...")
                }
                .padding(6)
                if let u = model.mdSelection {
                    HTMLPreview(html: Markdown.html(model.mdText.isEmpty ? CodeStyle.load(u) : model.mdText), base: u.deletingLastPathComponent())
                } else {
                    Spacer()
                }
            }
        }
    }

    private func export() {
        guard let md = model.mdSelection else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = md.deletingPathExtension().lastPathComponent + ".pdf"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        model.status = "Exporting..."
        model.exportPDF(from: md, to: out) { ok in model.status = ok ? "Saved \(out.path)" : "PDF export failed" }
    }
}

struct HTMLPreview: NSViewRepresentable {
    var html: String
    var base: URL?
    /// 사용자가 링크를 눌렀을 때. true 를 돌려주면 웹뷰는 이동하지 않는다.
    var onLink: ((URL) -> Bool)? = nil

    final class Coordinator: NSObject, WKNavigationDelegate {
        var last = ""
        var onLink: ((URL) -> Bool)?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let u = action.request.url {
                // 문서 안 #앵커는 그대로 두고, 그 밖의 링크는 부른 쪽이 처리한다(처리 못 하면 이동하지 않음).
                if u.fragment != nil, u.path == webView.url?.path || u.path.isEmpty { decisionHandler(.allow); return }
                _ = onLink?(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.navigationDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        w.underPageBackgroundColor = Theme.terminalBackground
        return w
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.last != html else { return }
        context.coordinator.last = html
        v.loadHTMLString(html, baseURL: base)
    }
}

struct DiagramTab: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Write one edge per line: A -> B: label").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $model.diagramText).font(.system(size: 12, design: .monospaced))
            }
            .padding(6)
            .frame(minWidth: 260, idealWidth: 300)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Export PNG...") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.png]
                        panel.nameFieldStringValue = "diagram.png"
                        guard panel.runModal() == .OK, let out = panel.url else { return }
                        model.status = model.exportPNG(to: out) ? "Saved \(out.path)" : "PNG export failed"
                    }
                }
                .padding(6)
                ScrollView([.horizontal, .vertical]) {
                    DiagramView(diagram: Diagram.parse(model.diagramText)).padding(20)
                }
            }
        }
    }
}

/// 층별로 상자를 놓고 화살표를 그린다.
struct DiagramView: View {
    var diagram: Diagram
    let boxW: CGFloat = 140, boxH: CGFloat = 44, gapX: CGFloat = 90, gapY: CGFloat = 30

    var body: some View {
        let layers = diagram.layers()
        let rows = layers.map(\.count).max() ?? 1
        let height = CGFloat(rows) * boxH + CGFloat(max(rows - 1, 0)) * gapY
        var pos: [String: CGPoint] = [:]
        for (i, layer) in layers.enumerated() {
            let colH = CGFloat(layer.count) * boxH + CGFloat(max(layer.count - 1, 0)) * gapY
            for (j, n) in layer.enumerated() {
                pos[n] = CGPoint(x: CGFloat(i) * (boxW + gapX) + boxW / 2,
                                 y: (height - colH) / 2 + CGFloat(j) * (boxH + gapY) + boxH / 2)
            }
        }
        let width = CGFloat(layers.count) * boxW + CGFloat(max(layers.count - 1, 0)) * gapX
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                let bottom = height + boxH * 0.6
                for e in diagram.edges {
                    guard let a = pos[e.from], let b = pos[e.to] else { continue }
                    let color = Color(white: 0.7)
                    if b.x > a.x {
                        let start = CGPoint(x: a.x + boxW / 2, y: a.y)
                        let end = CGPoint(x: b.x - boxW / 2, y: b.y)
                        var p = Path()
                        p.move(to: start)
                        p.addCurve(to: end, control1: CGPoint(x: start.x + gapX / 2, y: start.y), control2: CGPoint(x: end.x - gapX / 2, y: end.y))
                        ctx.stroke(p, with: .color(color), lineWidth: 1.5)
                        var head = Path()
                        head.move(to: end)
                        head.addLine(to: CGPoint(x: end.x - 8, y: end.y - 5))
                        head.addLine(to: CGPoint(x: end.x - 8, y: end.y + 5))
                        head.closeSubpath()
                        ctx.fill(head, with: .color(color))
                        if !e.label.isEmpty {
                            ctx.draw(Text(e.label).font(.system(size: 10)).foregroundColor(Color(white: 0.75)),
                                     at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10))
                        }
                    } else {
                        // 되돌아가거나 같은 층으로 가는 간선은 그림 아래로 돌아 들어간다.
                        let start = CGPoint(x: a.x, y: a.y + boxH / 2)
                        let end = CGPoint(x: b.x + (a.x == b.x ? 20 : 0), y: b.y + boxH / 2)
                        var p = Path()
                        p.move(to: start)
                        p.addCurve(to: end, control1: CGPoint(x: start.x, y: bottom + 10), control2: CGPoint(x: end.x, y: bottom + 10))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        var head = Path()
                        head.move(to: end)
                        head.addLine(to: CGPoint(x: end.x - 5, y: end.y + 8))
                        head.addLine(to: CGPoint(x: end.x + 5, y: end.y + 8))
                        head.closeSubpath()
                        ctx.fill(head, with: .color(color))
                        if !e.label.isEmpty {
                            ctx.draw(Text(e.label).font(.system(size: 10)).foregroundColor(Color(white: 0.75)),
                                     at: CGPoint(x: (start.x + end.x) / 2, y: bottom - 2))
                        }
                    }
                }
            }
            .frame(width: width, height: height + boxH * 1.4)
            ForEach(diagram.nodes, id: \.self) { n in
                Text(n)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: boxW, height: boxH)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.25, green: 0.27, blue: 0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.5, green: 0.55, blue: 0.95), lineWidth: 1))
                    .position(pos[n] ?? .zero)
            }
        }
        .frame(width: max(width, boxW), height: height + boxH * 1.4, alignment: .topLeading)
    }
}

// MARK: 창

@MainActor
final class StudioWindowController: NSWindowController {
    let studio: StudioModel

    init(root: URL, pin: @escaping (URL) -> Void) {
        studio = StudioModel(root: root)
        studio.pinToBoard = pin
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Symboard Studio"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: StudioView(model: studio))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        WindowFrames.track(window, key: "studio")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func close() {
        studio.saveNowIfPending()
        super.close()
    }
}
