import AppKit
import SwiftUI
import WebKit
import SymboardCore

/// 문서 스튜디오: 로그인한 CLI 로 레포 문서를 써서 PDF 로 낸다. 만든 문서는 레포별 라이브러리에 남는다.
@MainActor
final class DocStudioState: ObservableObject {
    unowned let model: AppModel
    weak var c: MainWindowController?
    @Published var agent = "claude"
    @Published var depth = "balanced"
    @Published var selected: String = DocKind.all[0].id
    @Published var request = ""
    /// 생성 중인 종류 id 와 글.
    @Published var generating: String?
    @Published var live = ""
    @Published var activity = ""
    @Published var startedAt = Date()
    @Published var view = "paper"
    @Published var error: String?
    @Published private(set) var library: [String: String] = [:]
    private var job: AgentJob?

    init(model: AppModel) { self.model = model }

    var repo: String { c?.projectPath ?? NSHomeDirectory() }
    var repoName: String { (repo as NSString).lastPathComponent }

    /// ~/Library/Application Support/Symboard/docs/<레포 이름-해시>/
    var folder: URL {
        var h: UInt64 = 1469598103934665603
        for b in repo.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return model.store.directory.appendingPathComponent("docs/\(repoName)-\(String(h, radix: 36).prefix(6))", isDirectory: true)
    }

    func url(for id: String) -> URL { folder.appendingPathComponent("\(id).md") }

    func reload() {
        var lib: [String: String] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "md" { lib[f.deletingPathExtension().lastPathComponent] = (try? String(contentsOf: f, encoding: .utf8)) ?? "" }
        library = lib
    }

    /// 깊이별 지난 소요 시간(prefs.json).
    func timing(_ d: String) -> String {
        let t = Prefs.shared.double("docTiming.\(d)")
        return t > 0 ? String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) : "not timed"
    }

    func generate(kind id: String?) {
        guard generating == nil else { return }
        let kind = id.flatMap { k in DocKind.all.first { $0.id == k } }
        let docID = id ?? "custom-" + String(Int(Date().timeIntervalSince1970))
        let prompt = DocKind.prompt(kind: kind, request: id == nil ? request : nil, depth: depth, repoName: repoName)
        selected = docID
        generating = docID
        live = ""
        activity = "Starting \(AgentCatalog.choice(id: agent)?.name ?? agent)..."
        error = nil
        startedAt = Date()
        let j = AgentJob(.init(agent: agent, prompt: prompt, cwd: repo, tools: "Read,Glob,Grep"))
        job = j
        j.onActivity = { [weak self] a in self?.activity = "Reading · \(a)" }
        j.onText = { [weak self] t in
            self?.live += t
            self?.activity = "Writing"
        }
        j.onDone = { [weak self] text, ok in
            guard let self else { return }
            let started = self.startedAt
            self.generating = nil
            self.job = nil
            guard ok, !text.isEmpty else { self.error = "The CLI did not return a document."; return }
            try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
            try? text.write(to: self.url(for: docID), atomically: true, encoding: .utf8)
            Prefs.shared.set(Date().timeIntervalSince(started), for: "docTiming.\(self.depth)")
            self.request = ""
            self.reload()
        }
        j.start()
    }

    func stop() {
        job?.cancel()
        job = nil
        generating = nil
        activity = "Stopped"
    }

    var currentText: String { generating == selected ? live : (library[selected] ?? "") }
    var title: String {
        Markdown.firstHeading(currentText) ?? DocKind.all.first { $0.id == selected }?.title ?? "Document"
    }
}

struct DocumentsStudio: View {
    @ObservedObject var docs: DocStudioState
    let c: MainWindowController

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 320)
            Divider().overlay(Color.symBorder)
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Color.symBorder)
                content
            }
        }
        .onAppear { docs.reload() }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symAccent)
                    .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10).fill(Color.symAccent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Documents").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.symText)
                    Text("Turn this repo into a PDF, written by your own CLI.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
            }
            HStack(spacing: 6) {
                ForEach(["claude", "codex"], id: \.self) { a in
                    Button { docs.agent = a } label: { AgentBadge(choice: AgentCatalog.choice(id: a)!, size: 28) }.tip("Write with \(a)")
                        .buttonStyle(.plainHit)
                        .overlay(Circle().stroke(docs.agent == a ? Color.symAccent : .clear, lineWidth: 1.5).padding(-4))
                        .opacity(AgentCatalog.shared.installed.contains(a) ? 1 : 0.35)
                        .tip(AgentCatalog.choice(id: a)!.name)
                }
            }
            HStack(spacing: 6) {
                ForEach([("quick", "Quick", "hare"), ("balanced", "Balanced", "scalemass"), ("thorough", "Thorough", "tortoise")], id: \.0) { d in
                    Button { docs.depth = d.0 } label: {
                        VStack(spacing: 2) {
                            Label(d.1, systemImage: d.2).font(.system(size: 12, weight: .semibold))
                            Text(docs.timing(d.0)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(docs.depth == d.0 ? Color.symText : Color.symDim)
                        .background(RoundedRectangle(cornerRadius: 9).fill(docs.depth == d.0 ? Color.symAccent.opacity(0.12) : Color.symRaised.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(docs.depth == d.0 ? Color.symAccent.opacity(0.7) : .clear))
                    }
                    .buttonStyle(.plainHit)
                }
            }
            Divider().overlay(Color.symBorder)
            Text("DOCUMENTS").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(DocKind.all) { k in row(id: k.id, title: k.title, sub: k.blurb, icon: k.icon) }
                    ForEach(docs.library.keys.filter { $0.hasPrefix("custom-") }.sorted(), id: \.self) { id in
                        row(id: id, title: Markdown.firstHeading(docs.library[id] ?? "") ?? "Custom", sub: "From your request", icon: "text.bubble")
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("", text: $docs.request, prompt: Text("Ask for any document...").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText)
                    .autoFocus()
                    .onSubmit { if !docs.request.isEmpty { docs.generate(kind: nil) } }
                Button { docs.generate(kind: nil) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(docs.request.isEmpty ? Color.symRaised : Color.symAccent))
                }
                .buttonStyle(.plainHit).disabled(docs.request.isEmpty || docs.generating != nil)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
        }
        .padding(14)
    }

    func row(id: String, title: String, sub: String, icon: String) -> some View {
        let sel = docs.selected == id
        return Button { docs.selected = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(sel ? Color.symAccent : Color.symDim).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                    Text(sub).font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
                Spacer()
                if docs.generating == id { Circle().fill(Color.symAccent).frame(width: 7, height: 7) }
                else if docs.library[id] != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "#6FCF97")) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 9).fill(sel ? Color.symAccent.opacity(0.10) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plainHit)
    }

    var agentName: String { AgentCatalog.choice(id: docs.agent)?.name ?? docs.agent }

    var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext").foregroundStyle(Color.symAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(docs.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText).lineLimit(1)
                if docs.generating == nil, !docs.currentText.isEmpty {
                    let w = Markdown.wordCount(docs.currentText)
                    Text("\(w.words) words · ~\(w.minutes) min read").font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
            }
            if docs.generating == docs.selected {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 6) {
                        Circle().fill(Color.symAccent).frame(width: 6, height: 6)
                        Text("Writing with \(agentName) · \(Int(ctx.date.timeIntervalSince(docs.startedAt)))s")
                    }
                    .font(.system(size: 11)).foregroundStyle(Color.symText.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.symRaised))
                }
            }
            Spacer()
            if docs.generating == docs.selected {
                Button { docs.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(PillButtonStyle())
                    .foregroundStyle(Color(hex: "#E8564A"))
            } else if !docs.currentText.isEmpty {
                HStack(spacing: 2) {
                    Button { docs.view = "paper" } label: { Image(systemName: "text.alignleft") }.buttonStyle(ChipStyle(on: docs.view == "paper")).tip("Paper view")
                    Button { docs.view = "source" } label: { Image(systemName: "doc.plaintext") }.buttonStyle(ChipStyle(on: docs.view == "source"))
                }
                Button { docs.generate(kind: docs.selected.hasPrefix("custom-") ? nil : docs.selected) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(ChipStyle(on: false)).tip("Regenerate")
                Button { c.placeDocumentCard(docs.selected) } label: { Image(systemName: "rectangle.on.rectangle") }
                    .buttonStyle(ChipStyle(on: false)).tip("Send to board")
                Button { c.studioExportDocPDF(docs.selected) } label: { Label("Export PDF", systemImage: "arrow.down.doc") }.buttonStyle(PillButtonStyle(prominent: true))
            }
            Button { c.closeStudio() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.tip("Close studio")
                .buttonStyle(.plainHit).foregroundStyle(Color.symDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder var content: some View {
        if docs.currentText.isEmpty && docs.generating != docs.selected {
            let k = DocKind.all.first { $0.id == docs.selected }
            VStack(spacing: 10) {
                Image(systemName: k?.icon ?? "doc.text").font(.system(size: 34)).foregroundStyle(Color.symAccent)
                Text(k?.title ?? "Document").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.symText)
                Text(k?.blurb ?? "").font(.system(size: 13)).foregroundStyle(Color.symDim)
                Button { docs.generate(kind: k?.id) } label: { Label("Generate with \(agentName)", systemImage: "sparkles") }
                    .buttonStyle(PillButtonStyle(prominent: true)).disabled(docs.generating != nil || k == nil)
                Text("Saved to this repo's library when it finishes.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                if let e = docs.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.symAccent) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if docs.view == "source" && docs.generating != docs.selected {
            CodeEditor(text: .constant(docs.currentText), ext: "md", editable: false).padding(12)
        } else {
            VStack(spacing: 6) {
                PaperView(markdown: docs.currentText, streaming: docs.generating == docs.selected)
                if docs.generating == docs.selected {
                    Text(docs.activity).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim).padding(.bottom, 8)
                }
            }
        }
    }
}

/// 흰 종이 위 문서. 생성 중에는 본문만 바꿔 넣어 깜빡이지 않게 한다.
struct PaperView: NSViewRepresentable {
    var markdown: String
    var streaming: Bool

    final class Coordinator { var loaded = false; var last = ""; var pending: DispatchWorkItem? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    static let shell = """
    <!doctype html><html><head><meta charset='utf-8'><style>
    html{background:#121110}body{margin:0;padding:28px 0 60px}
    .paper{max-width:760px;margin:0 auto;background:#fff;border-radius:14px;box-shadow:0 18px 50px rgba(0,0,0,.55);padding:56px 64px;
      font:15px -apple-system,Helvetica,sans-serif;line-height:1.65;color:#1d1d1f;min-height:300px}
    h1{font-size:30px;margin:0 0 .6em}h2{font-size:20px;margin:1.6em 0 .5em}h3{font-size:16px}
    h1:after,h2:after{content:"";display:block;width:64px;height:3px;border-radius:2px;background:#F05A38;margin-top:10px}
    p code,li code,td code{color:#D9482A;background:rgba(240,90,56,.08);padding:1px 5px;border-radius:4px;font:13px Menlo,monospace}
    pre{background:#f6f4f1;padding:12px;border-radius:8px;white-space:pre-wrap}pre code{font:12.5px Menlo,monospace}
    table{border-collapse:separate;border-spacing:0;width:100%;border:1px solid #ece8e3;border-radius:10px;overflow:hidden}
    th{text-align:left;background:#f6f4f1}th,td{padding:8px 12px;border-top:1px solid #ece8e3}thead th{border-top:none}
    .callout{border:1px solid #f3cfc4;border-left:4px solid #F05A38;border-radius:10px;padding:12px 16px;margin:1.2em 0;background:#fdf3ef}
    .callout.tip{border-color:#cfe8d6;border-left-color:#3E8E5A;background:#f1faf4}
    .callout-title{font:700 11px -apple-system;letter-spacing:.1em;color:#D9482A;margin-bottom:4px}.callout.tip .callout-title{color:#3E8E5A}
    .callout p{margin:0}blockquote{border-left:3px solid #ddd;margin:0;padding-left:12px;color:#555}
    .skel{height:12px;border-radius:6px;background:linear-gradient(90deg,#eee,#f6f6f6,#eee);margin:14px 0}
    .caret{display:inline-block;width:8px;height:16px;background:#F05A38;vertical-align:-2px;animation:b 1s steps(2) infinite}
    @keyframes b{50%{opacity:0}}
    </style></head><body><div class='paper' id='c'></div></body></html>
    """

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.setValue(false, forKey: "drawsBackground")
        w.underPageBackgroundColor = Theme.terminalBackground
        w.loadHTMLString(Self.shell, baseURL: nil)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        let co = context.coordinator
        let key = markdown + (streaming ? "|s" : "")
        guard co.last != key else { return }
        co.last = key
        co.pending?.cancel()
        let body: String
        if markdown.isEmpty {
            body = "<div class='skel' style='width:55%;height:26px'></div>" + (0..<6).map { i in "<div class='skel' style='width:\([92, 85, 96, 70, 88, 60][i])%'></div>" }.joined()
        } else {
            body = Markdown.bodyHTML(markdown) + (streaming ? "<span class='caret'></span>" : "")
        }
        let js = "document.getElementById('c').innerHTML = \(InspectorModel.jsString(body));" + (streaming ? "window.scrollTo(0, document.body.scrollHeight);" : "")
        // 조각이 잦으면 0.25초에 한 번만 바꾼다.
        let work = DispatchWorkItem { w.evaluateJavaScript(js) }
        co.pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (co.loaded ? 0.25 : 0.6), execute: work)
        co.loaded = true
    }
}

/// 보드 위 문서 카드: DOCUMENT 라벨, CLI 배지, 제목, 종이 미리보기.
final class DocumentCardContent: NodeContent {
    let host: NSView
    var view: NSView { host }

    init(node: BoardNode) {
        let url = URL(fileURLWithPath: node.text ?? "")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        host = CanvasHostingView(rootView: DocumentCardView(text: text, agent: node.role ?? "claude", url: url).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}
}

struct DocumentCardView: View {
    let text: String
    let agent: String
    let url: URL
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("DOCUMENT").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symAccent)
                if let ch = AgentCatalog.choice(id: agent) { AgentBadge(choice: ch, size: 16) }
                Text(Markdown.firstHeading(text) ?? url.deletingPathExtension().lastPathComponent).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText).lineLimit(1)
                Spacer()
                Text("\(Markdown.wordCount(text).words) words").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            PaperView(markdown: text, streaming: false)
        }
        .background(Color.symSurface)
    }
}
