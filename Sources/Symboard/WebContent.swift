import AppKit
import SwiftUI
import WebKit
import SymboardCore

/// 웹 타일 화면 상태.
@MainActor
final class WebTileState: ObservableObject {
    @Published var tabs: [String]
    @Published var titles: [String]
    @Published var active: Int
    @Published var device: String?
    @Published var address = ""
    @Published var canBack = false
    @Published var canForward = false
    @Published var loading = false
    /// 페이지의 console 출력(인스펙터 Console 탭).
    @Published var console: [(level: String, text: String)] = []

    init(tabs: [String], active: Int, device: String?) {
        self.tabs = tabs.isEmpty ? [""] : tabs
        self.titles = Array(repeating: "", count: max(tabs.count, 1))
        self.active = min(active, max(tabs.count - 1, 0))
        self.device = device
        address = self.tabs[self.active]
    }
}

/// 브라우저 탭·주소줄·표시 크기를 가진 웹 타일. 탭마다 WKWebView 하나.
final class WebContent: NSObject, NodeContent, WKNavigationDelegate, WKScriptMessageHandler {
    let nodeID: UUID
    unowned let model: AppModel
    let state: WebTileState
    let container = FlippedView()
    private let chromeHost: NSView
    private let startHost: NSView
    private let stage = FlippedView()
    private var views: [WKWebView] = []
    var view: NSView { container }
    static let barHeight: CGFloat = 68

    var webView: WKWebView { views[state.active] }

    init(node: BoardNode, model: AppModel) {
        nodeID = node.id
        self.model = model
        let tabs = node.tabs ?? [node.text ?? ""]
        state = WebTileState(tabs: tabs, active: node.activeTab ?? 0, device: node.device)
        var chromeRef: WebContent?
        chromeHost = CanvasHostingView(rootView: AnyView(EmptyView()))
        startHost = CanvasHostingView(rootView: AnyView(EmptyView()))
        super.init()
        chromeRef = self
        (chromeHost as! NSHostingView<AnyView>).rootView = AnyView(WebTileBar(state: state, web: chromeRef!).environment(\.colorScheme, .dark))
        (startHost as! NSHostingView<AnyView>).rootView = AnyView(WebStartPage { [weak self] url in self?.navigate(url) }.environment(\.colorScheme, .dark))
        stage.wantsLayer = true
        stage.layer?.backgroundColor = NSColor.black.cgColor
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(hex: "#0B0B0A").cgColor
        container.addSubview(stage)
        container.addSubview(startHost)
        container.addSubview(chromeHost)
        for url in state.tabs { views.append(makeWebView(load: url)) }
        container.onLayout = { [weak self] _ in self?.layoutStage() }
        show(tab: state.active)
    }

    private func makeWebView(load url: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let hook = """
        (function(){ ['log','info','warn','error'].forEach(function(l){ var o=console[l]; console[l]=function(){ try{ window.webkit.messageHandlers.symConsole.postMessage({level:l, text:Array.prototype.map.call(arguments,function(a){ try{ return typeof a==='string'?a:JSON.stringify(a);}catch(e){return String(a);} }).join(' ')}); }catch(e){} o.apply(console, arguments); }; });
        window.addEventListener('error', function(e){ try{ window.webkit.messageHandlers.symConsole.postMessage({level:'error', text:String(e.message)}); }catch(_){} }); })();
        """
        config.userContentController.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(WeakScriptHandler(self), name: "symConsole")
        let w = WKWebView(frame: .zero, configuration: config)
        w.isInspectable = true
        w.navigationDelegate = self
        if let u = URL(string: url), !url.isEmpty { w.load(URLRequest(url: u)) }
        return w
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Reload") { [weak self] in self?.webView.reload() },
         ClosureMenuItem(title: "Open Inspector Tile") { [weak self] in self?.openInspector() }]
    }

    func teardown() {
        for v in views { v.configuration.userContentController.removeScriptMessageHandler(forName: "symConsole") }
    }

    // MARK: 배치

    private func layoutStage() {
        let b = container.bounds
        chromeHost.frame = NSRect(x: 0, y: 0, width: b.width, height: Self.barHeight)
        let area = NSRect(x: 0, y: Self.barHeight, width: b.width, height: max(0, b.height - Self.barHeight))
        startHost.frame = area
        if let d = DevicePreset.find(state.device) {
            let f = d.fit(in: Double(area.width), Double(area.height))
            stage.frame = NSRect(x: f.x, y: Double(area.minY) + f.y, width: f.w, height: f.h)
            webView.pageZoom = CGFloat(f.zoom)
        } else {
            stage.frame = area
            webView.pageZoom = 1
        }
        webView.frame = stage.bounds
    }

    private func show(tab i: Int) {
        guard views.indices.contains(i) else { return }
        for v in views where v.superview != nil { v.removeFromSuperview() }
        state.active = i
        stage.addSubview(views[i])
        state.address = state.tabs[i]
        startHost.isHidden = !state.tabs[i].isEmpty
        stage.isHidden = state.tabs[i].isEmpty
        updateNav()
        layoutStage()
        persist()
    }

    private func persist() {
        let tabs = state.tabs, active = state.active, device = state.device
        model.mutateNode(nodeID) { n in
            n.tabs = tabs; n.activeTab = active; n.device = device
            n.text = tabs[active]
            n.title = "Web"
        }
    }

    private func updateNav() {
        state.canBack = webView.canGoBack
        state.canForward = webView.canGoForward
        state.loading = webView.isLoading
    }

    // MARK: 동작

    func navigate(_ input: String) {
        let url = WebAddress.normalize(input)
        state.tabs[state.active] = url
        state.address = url
        if let u = URL(string: url), !url.isEmpty { webView.load(URLRequest(url: u)) }
        show(tab: state.active)
    }

    func newTab() {
        state.tabs.append("")
        state.titles.append("")
        views.append(makeWebView(load: ""))
        show(tab: state.tabs.count - 1)
    }

    func closeTab(_ i: Int) {
        guard state.tabs.count > 1, views.indices.contains(i) else { return }
        views[i].removeFromSuperview()
        views.remove(at: i)
        state.tabs.remove(at: i)
        state.titles.remove(at: i)
        show(tab: min(state.active >= i ? max(state.active - 1, 0) : state.active, state.tabs.count - 1))
    }

    func select(_ i: Int) { show(tab: i) }
    func back() { webView.goBack() }
    func forward() { webView.goForward() }
    func reload() { webView.reload() }

    func setDevice(_ id: String?) {
        state.device = id
        layoutStage()
        persist()
    }

    /// 인스펙터를 옆 타일로 띄우고 연결선으로 잇는다.
    func openInspector() {
        guard let c = (NSApp.delegate as? AppDelegate)?.windowController, let me = model.node(nodeID) else { return }
        if let existing = model.selectedWorkspace.nodes.first(where: { $0.kind == .inspector && $0.text == nodeID.uuidString }) {
            c.focus(nodeID: existing.id); return
        }
        c.addNode(kind: .inspector, size: CGSize(width: 440, height: 360), title: "Inspector",
                  at: Point(x: me.frame.x + me.frame.w + 80, y: me.frame.y + 60)) { $0.text = self.nodeID.uuidString }
        if let insp = model.selectedWorkspace.nodes.last, let wsID = model.workspaceID(containing: nodeID) {
            model.mutateWorkspace(wsID) { $0.links = ($0.links ?? []) + [NodeLink(from: self.nodeID, to: insp.id)] }
            c.currentCanvas?.layoutLinks()
            // 웹 타일 오른쪽에 붙어 생겨 화면 끝이면 오른쪽 막대 밑으로 들어간다. 둘 다 보이게 화면을 옮긴다.
            c.reveal([me.frame, insp.frame])
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { updateNav() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let i = views.firstIndex(of: webView) {
            state.titles[i] = webView.title ?? ""
            if let u = webView.url?.absoluteString, !u.hasPrefix("about:") { state.tabs[i] = u; if i == state.active { state.address = u } }
        }
        updateNav()
        persist()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error, in: webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error, in: webView) }

    private func showError(_ error: Error, in w: WKWebView) {
        updateNav()
        let html = "<body style='font:13px -apple-system;color:#8F8882;background:#121110;padding:24px'>Could not load <b style='color:#ECE7E2'>\(state.address)</b><br><br>\(error.localizedDescription)</body>"
        w.loadHTMLString(html, baseURL: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        state.console.append((d["level"] as? String ?? "log", d["text"] as? String ?? ""))
        if state.console.count > 500 { state.console.removeFirst(state.console.count - 500) }
    }
}

/// WKUserContentController 가 처리기를 강하게 잡아 생기는 순환을 끊는다.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(u, didReceive: m) }
}

struct WebTileBar: View {
    @ObservedObject var state: WebTileState
    let web: WebContent
    @State private var editing = ""

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(state.tabs.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: "globe").font(.system(size: 9))
                        Text(tabTitle(i)).font(.system(size: 11)).lineLimit(1)
                        if state.tabs.count > 1 {
                            Button { web.closeTab(i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plainHit).tip("Close tab")
                        }
                    }
                    .foregroundStyle(i == state.active ? Color.symText : Color.symDim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: 170)
                    .background(RoundedRectangle(cornerRadius: 7).fill(i == state.active ? Color.symRaised : Color.clear))
                    .onTapGesture { web.select(i) }
                }
                Button { web.newTab() } label: { Image(systemName: "plus").font(.system(size: 10)) }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("New tab")
                Spacer()
                if let d = DevicePreset.find(state.device) {
                    Text("\(d.name)  " + String(Int(d.width)) + " × " + String(Int(d.height))).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.symAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.symAccent.opacity(0.12)))
                }
            }
            HStack(spacing: 8) {
                Button(action: web.back) { Image(systemName: "chevron.left") }.disabled(!state.canBack).tip("Back")
                Button(action: web.forward) { Image(systemName: "chevron.right") }.disabled(!state.canForward).tip("Forward")
                Button(action: web.reload) { Image(systemName: state.loading ? "xmark" : "arrow.clockwise") }.tip(state.loading ? "Stop" : "Reload")
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 10)).foregroundStyle(Color.symDim)
                    TextField("", text: $state.address, prompt: Text("Address or :port").foregroundColor(Color.symDim))
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                        .autoFocus(state.address.isEmpty)
                        .onSubmit { web.navigate(state.address) }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.symRaised))
                Menu {
                    Button("Fit to tile") { web.setDevice(nil) }
                    ForEach(["Monitor", "Phone", "Tablet"], id: \.self) { g in
                        Section(g) {
                            ForEach(DevicePreset.all.filter { $0.group == g }) { d in
                                Button(d.name + "  " + String(Int(d.width)) + " × " + String(Int(d.height))) { web.setDevice(d.id) }
                            }
                        }
                    }
                } label: { Image(systemName: "display") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).hint("Display size")
                Button(action: web.openInspector) { Image(systemName: "ladybug") }.tip("Open inspector tile")
            }
            .buttonStyle(.plainHit)
            .foregroundStyle(Color.symText.opacity(0.85))
            .font(.system(size: 12))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.symSurface)
    }

    func tabTitle(_ i: Int) -> String {
        if !state.titles[i].isEmpty { return state.titles[i] }
        let u = state.tabs[i]
        if u.isEmpty { return "New tab" }
        return URL(string: u)?.host.map { h in URL(string: u)?.port.map { "\(h):\($0)" } ?? h } ?? u
    }
}

/// 빈 탭의 시작 화면: localhost 포트와 빠른 열기.
struct WebStartPage: View {
    var open: (String) -> Void
    @State private var port = ""

    static let ports = ["3000", "3001", "4200", "5173", "8000", "8080"]
    static let quick: [(String, String, String, String)] = [
        ("GitHub", "github.com", "chevron.left.forwardslash.chevron.right", "#9A938C"),
        ("MDN Web Docs", "developer.mozilla.org", "book", "#56A8F5"),
        ("npm", "npmjs.com", "shippingbox", "#E8564A"),
    ]

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Label("Open a page", systemImage: "globe").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText)
            Text("LOCALHOST").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color(hex: "#6FCF97"))
                Text("http://localhost:").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.symDim).fixedSize()
                TextField("", text: $port, prompt: Text("3000").foregroundColor(Color.symDim.opacity(0.6)))
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.symText)
                    .onSubmit { open(":" + (port.isEmpty ? "3000" : port)) }
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
            HStack(spacing: 6) {
                ForEach(Self.ports, id: \.self) { p in
                    Button { open(":" + p) } label: {
                        HStack(spacing: 4) { Circle().fill(Color.symDim).frame(width: 4, height: 4); Text(":" + p).fixedSize() }
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symText)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.symRaised))
                    }
                    .buttonStyle(.plainHit).axName("Open port \(p)")
                }
            }
            Text("QUICK OPEN").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim).padding(.top, 4)
            ForEach(Self.quick, id: \.1) { q in
                Button { open(q.1) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: q.2).foregroundStyle(Color(hex: q.3)).frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: q.3).opacity(0.15)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText)
                            Text(q.1).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
                        }
                        Spacer()
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                }
                .buttonStyle(.plainHit).axName("Open \(q.0)")
            }
            Text("or type any address above").font(.system(size: 11)).foregroundStyle(Color.symDim)
        }
        .padding(16)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.symSurface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.symBorder))
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0B0B0A"))
    }
}

/// 위에서 아래로 놓는 단순 컨테이너.
final class FlippedView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        onLayout?(bounds)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onLayout?(bounds)
    }
}
