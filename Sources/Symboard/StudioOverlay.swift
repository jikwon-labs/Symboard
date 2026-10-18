import AppKit
import SwiftUI
import WebKit
import SymboardCore

/// 보드 위에 뜨는 스튜디오 패널의 상태. 지금 프로젝트 폴더에 붙는다.
@MainActor
final class StudioState: ObservableObject {
    /// "Code", "Markdown", "Documents". nil 이면 닫힘.
    @Published var kind: String?
    @Published var root: URL
    /// 펼친 폴더(표준 경로).
    @Published var expanded: Set<String> = []
    @Published var selected: URL?
    @Published var text = ""
    @Published var savedText = ""
    @Published var mdMode = "Reading"
    @Published var query = ""
    @Published var note = ""
    @Published var extraRoots: [URL] = []
    /// 연 파일(탭). 둘 이상이면 위쪽에 탭 줄이 보인다.
    @Published var openFiles: [URL] = []

    init(root: URL) { self.root = root }

    var dirty: Bool { text != savedText }
    var lineCount: Int {
        if text.isEmpty { return 0 }
        let n = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return text.hasSuffix("\n") ? n - 1 : n
    }

    static func key(_ u: URL) -> String { u.standardizedFileURL.resolvingSymlinksInPath().path }
    func isExpanded(_ u: URL) -> Bool { expanded.contains(Self.key(u)) }
    func toggle(_ u: URL) { let k = Self.key(u); if expanded.contains(k) { expanded.remove(k) } else { expanded.insert(k) } }
    func isSelected(_ u: URL) -> Bool { selected.map { Self.key($0) == Self.key(u) } ?? false }
    var byteCount: Int { text.utf8.count }
    var language: String {
        guard let ext = selected?.pathExtension.lowercased(), !ext.isEmpty else { return "TXT" }
        return ext.uppercased()
    }

    func open(_ url: URL) {
        if dirty, let cur = selected { try? text.write(to: cur, atomically: true, encoding: .utf8) }
        selected = url
        if !openFiles.contains(where: { Self.key($0) == Self.key(url) }) { openFiles.append(url) }
        text = CodeStyle.load(url)
        savedText = text
        note = ""
    }

    func save() {
        guard let url = selected, dirty else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); savedText = text; note = "Saved" }
        catch { note = "Save failed" }
    }

    /// 읽기 화면에서 누른 링크. 같은 컴퓨터의 마크다운 파일이면 스튜디오에서 연다.
    /// 웹 주소는 보드의 웹 타일로 연다(다른 앱을 띄우지 않는다).
    @discardableResult
    func followLink(_ url: URL) -> Bool {
        if url.isFileURL {
            var u = url
            if u.pathExtension.isEmpty { u = u.appendingPathExtension("md") }
            guard FileManager.default.fileExists(atPath: u.path) else { note = "Not found: \(u.lastPathComponent)"; return false }
            open(u)
            mdMode = "Reading"
            return true
        }
        if let scheme = url.scheme, ["http", "https"].contains(scheme) {
            MainWindowController.current?.openWebTile(url.absoluteString)
            return true
        }
        return false
    }

    /// 탭 닫기. 지금 탭이면 남은 탭 중 마지막으로 옮긴다(고친 내용은 저장).
    func closeTab(_ url: URL) {
        let k = Self.key(url)
        let wasCurrent = selected.map { Self.key($0) == k } ?? false
        if wasCurrent, dirty { try? text.write(to: url, atomically: true, encoding: .utf8); savedText = text }
        openFiles.removeAll { Self.key($0) == k }
        if wasCurrent {
            if let next = openFiles.last { open(next) } else { selected = nil; text = ""; savedText = "" }
        }
    }

    /// 경로를 루트 기준 조각으로(브레드크럼).
    var crumbs: [String] {
        guard let s = selected else { return [] }
        let r = Self.key(root), p = Self.key(s)
        let rel = p.hasPrefix(r) ? String(p.dropFirst(r.count)) : s.lastPathComponent
        return rel.split(separator: "/").map(String.init)
    }

    func markdownFiles() -> [URL] { FileItem.markdownFiles(under: root) }
}

// MARK: 패널

struct StudioOverlay: View {
    @ObservedObject var studio: StudioState
    let c: MainWindowController

    var body: some View {
        if let kind = studio.kind {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { c.closeStudio() }
                Group {
                    if kind == "Documents" {
                        DocumentsStudio(docs: c.docStudio, c: c)
                    } else {
                        HStack(spacing: 0) {
                            sidebar(kind).frame(width: 300)
                            Divider().overlay(Color.symBorder)
                            VStack(spacing: 0) {
                                topBar(kind)
                                Divider().overlay(Color.symBorder)
                                if kind == "Code" && studio.openFiles.count > 1 {
                                    tabRow
                                    Divider().overlay(Color.symBorder)
                                }
                                content(kind)
                            }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                .padding(.leading, 84).padding(.trailing, 76).padding(.top, 58).padding(.bottom, 92)
            }
            .environment(\.locale, Locale(identifier: "en_US"))
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind { case "Markdown": return "doc.text"; case "Documents": return "doc.richtext"; default: return "chevron.left.forwardslash.chevron.right" }
    }

    func sidebar(_ kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: Self.icon(kind)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symAccent)
                    .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10).fill(Color.symAccent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.symText)
                    Text(studio.root.lastPathComponent).font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
                Spacer()
                Button { c.studioAddFolder() } label: { Image(systemName: "plus").frame(width: 26, height: 26) }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Add a folder")
            }
            if kind == "Markdown" {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.symDim)
                    TextField("", text: $studio.query, prompt: Text("Search files").foregroundColor(Color.symDim))
                        .textFieldStyle(.plain).foregroundStyle(Color.symText)
                }
                .font(.system(size: 12)).padding(8).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
            }
            Divider().overlay(Color.symBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if kind == "Markdown" && !studio.query.isEmpty {
                        ForEach(studio.markdownFiles().filter { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(studio.query) }, id: \.self) { u in
                            TreeRow(url: u, isDir: false, depth: 0, studio: studio, hideExt: true)
                        }
                    } else {
                        ForEach([studio.root] + studio.extraRoots, id: \.self) { r in
                            ForEach(StudioTree.children(of: r, markdownOnly: kind == "Markdown"), id: \.url) { item in
                                TreeNode(item: item, depth: 0, studio: studio, markdownOnly: kind == "Markdown")
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder func topBar(_ kind: String) -> some View {
        HStack(spacing: 8) {
            if kind == "Markdown" {
                Image(systemName: "doc.text").foregroundStyle(Color.symDim)
                Text(studio.selected?.lastPathComponent ?? "No file").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                let w = Markdown.wordCount(studio.text)
                if studio.selected != nil {
                    Text("\(w.words) words · ~\(w.minutes) min").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(["Reading", "Source", "Graph"], id: \.self) { m in
                        Button(m) { studio.mdMode = m }.buttonStyle(ChipStyle(on: studio.mdMode == m))
                    }
                }
                Button { c.studioAddToBoard() } label: { Label("Add to Board", systemImage: "rectangle.on.rectangle") }.buttonStyle(PillButtonStyle())
                Button { c.studioExportPDF() } label: { Label("Export PDF", systemImage: "arrow.down.doc") }.buttonStyle(PillButtonStyle(prominent: true))
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color.symAccent).font(.system(size: 11))
                ForEach(Array(studio.crumbs.enumerated()), id: \.offset) { i, part in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Color.symDim) }
                    Text(part).font(.system(size: 12, weight: i == studio.crumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(i == studio.crumbs.count - 1 ? Color.symText : Color.symDim)
                }
                if studio.selected != nil {
                    Text(studio.language).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: "#56A8F5"))
                        .padding(.horizontal, 5).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#56A8F5").opacity(0.15)))
                    Text("\(studio.lineCount) lines · \(Self.bytes(studio.byteCount))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                    if studio.dirty { Text("• Edited").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: "#E9C46A")) }
                    else if !studio.note.isEmpty, studio.note != "Saved" { Text(studio.note).font(.system(size: 11)).foregroundStyle(Color.symAccent) }
                }
                Spacer()
                Button { c.studioAddFolder() } label: { Label("Add folder", systemImage: "folder.badge.plus") }.buttonStyle(PillButtonStyle())
                // 원본처럼 저장하면 단추 자체가 흐린 "✓ Saved" 로 바뀌고, 다시 고치면 Save 로 돌아온다.
                let justSaved = !studio.dirty && studio.note == "Saved"
                Button { studio.save() } label: {
                    Label(justSaved ? "Saved" : "Save", systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                }
                .buttonStyle(PillButtonStyle()).axName(justSaved ? "Saved" : "Save")
                .keyboardShortcut("s", modifiers: .command).disabled(!studio.dirty)
                Button { c.studioInsert() } label: { Label("Insert", systemImage: "rectangle.on.rectangle") }.buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(studio.selected == nil)
            }
            Button { c.closeStudio() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.tip("Close studio")
                .buttonStyle(.plainHit).foregroundStyle(Color.symDim).padding(.leading, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    static func bytes(_ n: Int) -> String { n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024) }

    /// 연 파일 탭 줄(코드 스튜디오, 둘 이상일 때).
    var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(studio.openFiles, id: \.self) { u in
                    let on = studio.isSelected(u)
                    HStack(spacing: 6) {
                        Button { if !on { studio.open(u) } } label: {
                            Text(u.lastPathComponent).font(.system(size: 12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.symText : Color.symDim)
                        }
                        .buttonStyle(.plainHit).axName("Tab \(u.lastPathComponent)")
                        if on && studio.dirty { Circle().fill(Color(hex: "#E9C46A")).frame(width: 6, height: 6) }
                        Button { studio.closeTab(u) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle()) }
                            .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Close \(u.lastPathComponent)")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.symRaised : Color.clear))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    @ViewBuilder func content(_ kind: String) -> some View {
        if studio.selected == nil {
            VStack(spacing: 8) {
                Image(systemName: Self.icon(kind)).font(.system(size: 28)).foregroundStyle(Color.symDim)
                Text("Pick a file on the left").font(.system(size: 13)).foregroundStyle(Color.symDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if kind == "Markdown" {
            switch studio.mdMode {
            case "Source": CodeEditor(text: $studio.text, ext: "md").padding(12)
            case "Graph": LinkGraph2(studio: studio)
            default: HTMLPreview(html: Markdown.html(studio.text, title: studio.selected?.lastPathComponent ?? "", theme: "dark"),
                                 base: studio.selected?.deletingLastPathComponent(),
                                 onLink: { url in studio.followLink(url) })
            }
        } else {
            CodeEditor(text: $studio.text, ext: studio.selected?.pathExtension ?? "").padding(12)
        }
    }
}

// MARK: 파일 나무

enum StudioTree {
    static func children(of url: URL, markdownOnly: Bool) -> [FileItem] {
        FileItem(url: url, isDir: true).children(onlyMarkdown: markdownOnly) ?? []
    }

    static func icon(_ url: URL, isDir: Bool, open: Bool) -> (String, Color) {
        if isDir { return (open ? "folder.fill" : "folder", Color.symAccent) }
        switch url.pathExtension.lowercased() {
        case "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb", "java", "kt", "c", "h", "cpp", "m", "sh":
            return ("chevron.left.forwardslash.chevron.right", Color(hex: "#56A8F5"))
        case "md", "txt": return ("doc.text", Color.symDim)
        case "json", "yml", "yaml", "toml", "plist": return ("curlybraces", Color(hex: "#E9C46A"))
        case "png", "jpg", "jpeg", "svg", "gif", "webp": return ("photo", Color(hex: "#B48CF2"))
        case "css", "scss", "html": return ("paintbrush", Color(hex: "#F28AB2"))
        default: return ("doc", Color.symDim)
        }
    }
}

struct TreeNode: View {
    let item: FileItem
    let depth: Int
    @ObservedObject var studio: StudioState
    let markdownOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeRow(url: item.url, isDir: item.isDir, depth: depth, studio: studio, hideExt: markdownOnly)
            if item.isDir && studio.isExpanded(item.url) {
                ForEach(StudioTree.children(of: item.url, markdownOnly: markdownOnly), id: \.url) { child in
                    TreeNode(item: child, depth: depth + 1, studio: studio, markdownOnly: markdownOnly)
                }
            }
        }
    }
}

struct TreeRow: View {
    let url: URL
    let isDir: Bool
    let depth: Int
    @ObservedObject var studio: StudioState
    var hideExt = false

    var body: some View {
        let open = studio.isExpanded(url)
        let sel = studio.isSelected(url)
        let ic = StudioTree.icon(url, isDir: isDir, open: open)
        Button {
            if isDir { studio.toggle(url) } else { studio.open(url) }
        } label: {
            HStack(spacing: 6) {
                if isDir { Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.symDim).frame(width: 10) }
                else { Spacer().frame(width: 10) }
                Image(systemName: ic.0).font(.system(size: 11)).foregroundStyle(ic.1).frame(width: 16)
                Text(hideExt && !isDir ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
                    .font(.system(size: 12, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? Color.symText : Color.symText.opacity(0.82)).lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 14 + 4).padding(.vertical, 4).padding(.trailing, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(sel ? Color.symAccent.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plainHit)
    }
}

// MARK: 코드 편집기(줄 번호·구문 색)

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var ext: String
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = editable
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.backgroundColor = Theme.terminalBackground
        tv.insertionPointColor = Theme.accent
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        tv.delegate = context.coordinator
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.terminalBackground
        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = Theme.border.cgColor
        context.coordinator.apply(tv, text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { context.coordinator.apply(tv, text) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ p: CodeEditor) { parent = p }

        func apply(_ tv: NSTextView, _ s: String) {
            let sel = tv.selectedRanges
            tv.textStorage?.setAttributedString(CodeStyle.attributed(s, ext: parent.ext))
            tv.selectedRanges = sel.filter { $0.rangeValue.upperBound <= (s as NSString).length }
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            // 입력 중에도 색을 다시 입힌다(작은 파일 기준).
            if tv.string.utf16.count < 200_000, let storage = tv.textStorage {
                let colored = CodeStyle.attributed(tv.string, ext: parent.ext)
                storage.beginEditing()
                colored.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: colored.length)) { v, r, _ in
                    if let v { storage.addAttribute(.foregroundColor, value: v, range: r) }
                }
                storage.endEditing()
            }
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

/// 왼쪽 줄 번호 막대.
final class LineNumberRuler: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        Theme.terminalBackground.setFill()
        bounds.fill()
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let s = tv.string as NSString
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = s.substring(to: chars.location).components(separatedBy: "\n").count
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: Theme.textDim]
        var idx = chars.location
        let inset = tv.textContainerInset.height
        while idx <= NSMaxRange(chars) {
            let lineRange = s.lineRange(for: NSRange(location: min(idx, max(s.length - 1, 0)), length: 0))
            let g = lm.glyphIndexForCharacter(at: min(idx, max(s.length - 1, 0)))
            var r = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            if s.length == 0 { r = NSRect(x: 0, y: 0, width: 0, height: 15) }
            let y = r.minY + inset - visible.minY
            let str = NSAttributedString(string: "\(line)", attributes: attrs)
            let w = str.size().width
            str.draw(at: NSPoint(x: ruleThickness - w - 8, y: y + 1))
            line += 1
            if NSMaxRange(lineRange) <= idx { break }
            idx = NSMaxRange(lineRange)
            if idx >= s.length { break }
        }
    }
}

// MARK: 링크 그래프

struct LinkGraph2: View {
    @ObservedObject var studio: StudioState
    @State private var hover: Int?
    @State private var layout: (names: [String], urls: [URL], edges: [(Int, Int)], points: [Point], size: CGSize)?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let l = layout, l.size == geo.size {
                    let current = l.urls.firstIndex(of: studio.selected ?? URL(fileURLWithPath: "/"))
                    let neighbors = Set(l.edges.flatMap { e -> [Int] in hover == e.0 ? [e.1] : (hover == e.1 ? [e.0] : []) })
                    Canvas { ctx, _ in
                        for (a, b) in l.edges {
                            var p = Path()
                            p.move(to: CGPoint(x: l.points[a].x, y: l.points[a].y))
                            p.addLine(to: CGPoint(x: l.points[b].x, y: l.points[b].y))
                            let lit = hover == a || hover == b
                            ctx.stroke(p, with: .color(lit ? Color.symAccent.opacity(0.8) : Color.symDim.opacity(0.25)), lineWidth: lit ? 1.5 : 1)
                        }
                        for (i, pt) in l.points.enumerated() {
                            let deg = l.edges.filter { $0.0 == i || $0.1 == i }.count
                            let r = CGFloat(3 + min(deg, 8))
                            let lit = i == hover || neighbors.contains(i)
                            let col: Color = i == current ? .symAccent : (lit ? Color(hex: "#E9C46A") : Color.symText.opacity(hover == nil ? 0.7 : 0.3))
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(col))
                        }
                    }
                    ForEach(Array(l.points.enumerated()), id: \.offset) { i, pt in
                        let show = i == hover || neighbors.contains(i) || i == current
                        Text(l.names[i]).font(.system(size: 10, weight: i == current ? .semibold : .regular))
                            .foregroundStyle(show ? Color.symText : Color.symDim.opacity(hover == nil ? 0.7 : 0.25))
                            .fixedSize()
                            .position(x: pt.x, y: pt.y + 14)
                            .opacity(show || l.points.count < 40 ? 1 : 0)
                        // 점과 이름을 함께 덮는 넉넉한 누름 자리(점만 20pt 이면 잘 안 눌렸다).
                        // 단추로 둔다(onTapGesture 는 이 패널에서 자동 입력 도구의 클릭을 받지 못했다).
                        Button { studio.open(l.urls[i]); studio.mdMode = "Reading" } label: {
                            Rectangle().fill(Color.white.opacity(0.001)).frame(width: 90, height: 40).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hover = $0 ? i : (hover == i ? nil : hover) }
                        .position(x: pt.x, y: pt.y + 6)
                    }
                }
                HStack {
                    Text("Link graph · \(layout?.names.count ?? 0) notes").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.symDim)
                    Spacer()
                }
                .padding(12)
            }
            .onAppear { build(geo.size) }
            .onChange(of: geo.size) { _, s in build(s) }
        }
        .background(Theme.terminalBackground.swiftUI)
    }

    func build(_ size: CGSize) {
        guard size.width > 50 else { return }
        let urls = studio.markdownFiles()
        var texts: [String: String] = [:]
        for u in urls { texts[u.path] = (try? String(contentsOf: u, encoding: .utf8)) ?? "" }
        let names = urls.map { $0.deletingPathExtension().lastPathComponent }
        var index: [String: Int] = [:]
        for (i, u) in urls.enumerated() { index[u.deletingPathExtension().lastPathComponent.lowercased()] = i; index[u.lastPathComponent.lowercased()] = i }
        var edges: [(Int, Int)] = []
        for (i, u) in urls.enumerated() {
            for link in Markdown.links(in: texts[u.path] ?? "") {
                let key = (link as NSString).lastPathComponent.lowercased()
                if let j = index[key] ?? index[(key as NSString).deletingPathExtension], j != i { edges.append((i, j)) }
            }
        }
        let pts = ForceLayout.run(count: urls.count, edges: edges, width: Double(size.width), height: Double(size.height - 20), iterations: 200)
            .map { Point(x: $0.x, y: $0.y + 20) }
        layout = (names, urls, edges, pts, size)
    }
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}

