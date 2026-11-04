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
final class WebContent: NSObject, NodeContent, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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
        (chromeHost as! NSHostingView<AnyView>).rootView = AnyView(WebTileBar(state: state, web: chromeRef!).localized())
        (startHost as! NSHostingView<AnyView>).rootView = AnyView(WebStartPage { [weak self] url in self?.navigate(url) }.localized())
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
        // 공유 보기 중계(15차). 격리 세계에만 여는 통로라 페이지 스크립트는 보낼 수 없다.
        config.userContentController.add(WeakScriptHandler(self), contentWorld: WebMirror.world, name: WebMirror.handlerName)
        let w = WKWebView(frame: .zero, configuration: config)
        w.isInspectable = true
        w.navigationDelegate = self
        w.uiDelegate = self
        if let u = URL(string: url), !url.isEmpty { w.load(URLRequest(url: u)) }
        return w
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: L("Reload")) { [weak self] in self?.webView.reload() },
         ClosureMenuItem(title: L("Open Inspector Tile")) { [weak self] in self?.openInspector() }]
    }

    func teardown() {
        onMirror = nil
        // 새 창 요청으로 만든 탭은 연 탭과 userContentController 를 함께 쓴다. 한 번씩만 뗀다.
        var seen = Set<ObjectIdentifier>()
        for v in views where seen.insert(ObjectIdentifier(v.configuration.userContentController)).inserted {
            v.configuration.userContentController.removeScriptMessageHandler(forName: "symConsole")
            v.configuration.userContentController.removeScriptMessageHandler(forName: WebMirror.handlerName, contentWorld: WebMirror.world)
        }
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
        ensureMirror()
    }

    private func persist() {
        let tabs = state.tabs, active = state.active, device = state.device
        model.mutateNode(nodeID) { n in
            n.tabs = tabs; n.activeTab = active; n.device = device
            n.text = tabs[active]
            // 원본처럼 타일 머리에 지금 페이지 제목.
            let t = self.state.titles.indices.contains(active) ? self.state.titles[active] : ""
            n.title = t.isEmpty ? "Web" : t
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

    /// 콘솔 링크로 연다(15차): 이미 연 탭이면 그 탭, 지금 탭이 시작 화면이면 거기, 아니면 새 탭.
    func open(_ url: String) {
        if let i = state.tabs.firstIndex(of: url) { show(tab: i); return }
        if !state.tabs[state.active].isEmpty { newTab() }
        navigate(url)
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
        // 원본처럼 화면 크기를 고르면 타일도 그 비율로 바뀐다(폭은 그대로, 높이를 맞춤. 폰은 높이를 지키고 폭을 맞춤).
        if let d = DevicePreset.find(id), let node = model.node(nodeID) {
            let head = Double(Self.barHeight) + 28
            var f = node.frame
            if d.width >= d.height {
                f.h = f.w * d.height / d.width + head
            } else {
                f.w = max(260, (f.h - head) * d.width / d.height)
            }
            model.mutateNode(nodeID) { $0.frame = f }
            NotificationCenter.default.post(name: .nodesChanged, object: model.workspaceID(containing: nodeID))
        }
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

    // MARK: WKUIDelegate

    /// 페이지가 새 창을 열려 할 때(`target="_blank"` 링크, `window.open`). 이 타일의 새 탭으로 연다.
    /// WebKit 이 준 설정으로 만든 웹뷰를 돌려줘야 요청(POST 포함)과 opener 가 그대로 이어진다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let w = WKWebView(frame: .zero, configuration: configuration)
        w.isInspectable = true
        w.navigationDelegate = self
        w.uiDelegate = self
        let url = navigationAction.request.url?.absoluteString ?? ""
        // 빈 주소면 시작 화면이 덮지 않게 about:blank 로 둔다(다 읽으면 실제 주소로 바뀐다).
        state.tabs.append(url.isEmpty ? "about:blank" : url)
        state.titles.append("")
        views.append(w)
        show(tab: views.count - 1)
        return w
    }

    /// 페이지가 `window.close()` 로 자기 창을 닫으면 그 탭을 닫는다.
    func webViewDidClose(_ webView: WKWebView) {
        if let i = views.firstIndex(of: webView) { closeTab(i) }
    }

    // MARK: 공유 보기 중계(15차)

    /// 공유 서버가 이 타일의 페이지 기록을 받는 곳. 정해지면 지금 탭을 기록하고, 비우면 기록을 멈춘다.
    var onMirror: ((WebMirror.Message) -> Void)? {
        didSet {
            if onMirror == nil { stopMirror() } else if oldValue == nil { ensureMirror() }
        }
    }
    /// 기록기를 넣은 탭.
    private weak var mirrored: WKWebView?
    private var mirrorBusy = false

    /// 지금 탭에 기록기가 돌게 한다. 탭이 바뀌었으면 앞 탭을 멈추고, 페이지가 바뀌어 기록기가 사라졌으면 다시 넣는다.
    /// 공유 서버가 1초마다, 탭을 바꾸거나 페이지를 다 읽었을 때도 부른다.
    func ensureMirror() {
        guard onMirror != nil, !mirrorBusy else { return }
        let w = webView
        if let old = mirrored, old !== w {
            old.evaluateJavaScript(WebMirror.stopScript, in: nil, in: WebMirror.world) { _ in }
            mirrored = nil
        }
        guard w.url != nil, !stage.isHidden, let script = WebMirror.injectScript else {
            mirrored = nil
            onMirror?(.off)
            return
        }
        mirrorBusy = true
        w.evaluateJavaScript(WebMirror.aliveScript, in: nil, in: WebMirror.world) { [weak self, weak w] result in
            guard let self, let w else { return }
            guard self.onMirror != nil, w === self.webView else { self.mirrorBusy = false; return }
            if (try? result.get()) as? String == "on" {
                // 이미 기록 중인 탭으로 돌아왔으면 전체 장면부터 다시 보낸다.
                if self.mirrored !== w {
                    self.mirrored = w
                    w.evaluateJavaScript(WebMirror.fullScript, in: nil, in: WebMirror.world) { _ in }
                }
                self.mirrorBusy = false
                return
            }
            self.mirrored = w
            w.evaluateJavaScript(script, in: nil, in: WebMirror.world) { [weak self] r in
                guard let self else { return }
                self.mirrorBusy = false
                let out = (try? r.get()) as? String
                if out != "started" && out != "again" {
                    self.mirrored = nil
                    self.onMirror?(.off)
                }
            }
        }
    }

    /// 새로 온 사람이 받을 기록이 너무 커졌을 때 전체 장면을 새로 찍게 한다.
    func requestFullMirror() {
        mirrored?.evaluateJavaScript(WebMirror.fullScript, in: nil, in: WebMirror.world) { _ in }
    }

    private func stopMirror() {
        mirrored?.evaluateJavaScript(WebMirror.stopScript, in: nil, in: WebMirror.world) { _ in }
        mirrored = nil
    }

    // MARK: 원격 조작(공유 조작 링크)

    /// 조작 링크에서 온 웹 동작을 지금 탭 페이지에 넣는다. 맥 화면의 창에 붙어 있어야 한다(다른 작업공간이면 false).
    /// 마우스·특수 키는 맥에서 직접 누른 것과 같은 NSEvent 로 웹뷰에 바로 넣어, 사이트가 사람 입력으로 받는다
    /// (창 hitTest 를 거치지 않아 다른 노드가 덮고 있어도 된다). 누르면 웹뷰가 키 입력 초점을 가져간다(맥에서 누른 것과 같다).
    /// 글자는 맥 입력기(한글 등)가 다시 해석하지 않게 페이지에 insertText 로 넣고, 휠은 그 자리의 스크롤 칸을 스크롤한다.
    func remoteInput(_ w: SymboardCore.ShareLink.WebInput) -> Bool {
        let view = webView
        guard let window = view.window, view.url != nil, !stage.isHidden else { return false }
        let mods = Self.modifierFlags(w)
        let now = ProcessInfo.processInfo.systemUptime
        switch w.type {
        case "down", "up", "drag":
            guard let x = w.x, let y = w.y else { return false }
            let p = windowPoint(x: x, y: y, in: view)
            func mouse(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: mods, timestamp: now, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: w.clicks ?? 1, pressure: type == .leftMouseUp ? 0 : 1)
            }
            switch w.type {
            case "down":
                window.makeFirstResponder(view)
                // 마우스를 올린 상태(hover)를 먼저 맞춘다.
                if let move = mouse(.mouseMoved) { view.mouseMoved(with: move) }
                guard let e = mouse(.leftMouseDown) else { return false }
                view.mouseDown(with: e)
            case "up":
                guard let e = mouse(.leftMouseUp) else { return false }
                view.mouseUp(with: e)
            default:
                guard let e = mouse(.leftMouseDragged) else { return false }
                view.mouseDragged(with: e)
            }
            return true
        case "wheel":
            guard let x = w.x, let y = w.y else { return false }
            view.callAsyncJavaScript(Self.wheelScript, arguments: ["x": x, "y": y, "dx": w.dx ?? 0, "dy": w.dy ?? 0],
                                     in: nil, in: WebMirror.world) { _ in }
            return true
        case "key":
            guard let key = w.key else { return false }
            if key == "a" {
                window.makeFirstResponder(view)
                return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: view, from: nil)
            }
            guard let k = Self.specialKeys[key] else { return false }
            let chars = String(Character(UnicodeScalar(k.char)!))
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: now,
                                               windowNumber: window.windowNumber, context: nil, characters: chars,
                                               charactersIgnoringModifiers: chars, isARepeat: false, keyCode: k.code) else { return false }
                if type == .keyDown { view.keyDown(with: e) } else { view.keyUp(with: e) }
            }
            return true
        case "text":
            guard let text = w.text else { return false }
            view.callAsyncJavaScript(Self.textScript, arguments: ["t": text], in: nil, in: WebMirror.world) { _ in }
            return true
        default:
            return false
        }
    }

    /// 페이지 화면 CSS 픽셀 → 창 좌표. 표시 크기(pageZoom)와 캔버스 배율은 convert 가 함께 맞춘다.
    private func windowPoint(x: Double, y: Double, in view: WKWebView) -> NSPoint {
        let z = Double(view.pageZoom)
        let local = NSPoint(x: x * z, y: view.isFlipped ? y * z : Double(view.bounds.height) - y * z)
        return view.convert(local, to: nil)
    }

    private static func modifierFlags(_ w: SymboardCore.ShareLink.WebInput) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if w.shift == true { f.insert(.shift) }
        if w.alt == true { f.insert(.option) }
        if w.meta == true { f.insert(.command) }
        if w.ctrl == true { f.insert(.control) }
        return f
    }

    /// 브라우저 키 이름 → (macOS 키 코드, 글자). 화살표 등은 NSEvent 기능 키 글자.
    private static let specialKeys: [String: (code: UInt16, char: UInt32)] = [
        "Enter": (36, 0x0D), "Backspace": (51, 0x7F), "Tab": (48, 0x09), "Escape": (53, 0x1B),
        "Delete": (117, 0xF728), "ArrowLeft": (123, 0xF702), "ArrowRight": (124, 0xF703),
        "ArrowDown": (125, 0xF701), "ArrowUp": (126, 0xF700), "Home": (115, 0xF729), "End": (119, 0xF72B),
        "PageUp": (116, 0xF72C), "PageDown": (121, 0xF72D),
    ]

    /// 그 자리에서 스크롤할 수 있는 가장 가까운 칸을, 없으면 페이지를 스크롤한다.
    private static let wheelScript = """
    var el = document.elementFromPoint(x, y);
    function can(e) {
      if (!e || e === document.body || e === document.documentElement) return false;
      var s = getComputedStyle(e), sc = /(auto|scroll|overlay)/;
      return (sc.test(s.overflowY) && e.scrollHeight > e.clientHeight && dy) || (sc.test(s.overflowX) && e.scrollWidth > e.clientWidth && dx);
    }
    while (el && !can(el)) el = el.parentElement;
    (el || window).scrollBy({ left: dx, top: dy, behavior: 'instant' });
    return true;
    """

    /// 지금 초점이 있는 입력칸에 글자를 넣는다. execCommand 는 사람이 친 것과 같은 input 이벤트를 낸다.
    private static let textScript = """
    var el = document.activeElement;
    if (!el) return false;
    if (document.execCommand('insertText', false, t)) return true;
    if ('value' in el && typeof el.value === 'string') {
      var a = el.selectionStart == null ? el.value.length : el.selectionStart, b = el.selectionEnd == null ? a : el.selectionEnd;
      el.value = el.value.slice(0, a) + t + el.value.slice(b);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      return true;
    }
    return false;
    """

    // MARK: WKNavigationDelegate

    /// 웹 주소가 아닌 링크(mailto:, tel:, 앱 주소 등)는 웹뷰가 열지 못하므로 누른 것만 맥 기본 앱에 넘긴다.
    /// Cmd+클릭한 링크는 이 타일의 새 탭으로 연다.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if !Self.inPageSchemes.contains(scheme) {
            // 사람이 누른 링크만 넘긴다. 페이지가 스스로 앱 주소로 보내는 것(자동 이동)은 막기만 한다.
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated, navigationAction.modifierFlags.contains(.command),
           scheme == "http" || scheme == "https" {
            decisionHandler(.cancel)
            newTab()
            navigate(url.absoluteString)
            return
        }
        decisionHandler(.allow)
    }

    /// 웹뷰 안에서 여는 주소 종류. 그 밖은 맥 기본 앱으로 넘긴다.
    static let inPageSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { updateNav() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let i = views.firstIndex(of: webView) {
            state.titles[i] = webView.title ?? ""
            // 제목은 didFinish 뒤에 채워지는 때가 있어 한 번 더 읽는다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
                guard let self, let webView, let j = self.views.firstIndex(of: webView), let t = webView.title, !t.isEmpty,
                      self.state.titles[j] != t else { return }
                self.state.titles[j] = t
                self.persist()
            }
            if let u = webView.url?.absoluteString, !u.hasPrefix("about:") { state.tabs[i] = u; if i == state.active { state.address = u } }
        }
        updateNav()
        persist()
        if webView === self.webView { ensureMirror() }
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
        if message.name == WebMirror.handlerName {
            // 지금 기록 중인 탭에서 온 것만 받는다(멈추는 중인 앞 탭의 마지막 묶음은 버린다).
            guard message.webView === mirrored, let json = d["d"] as? String else { return }
            onMirror?(.events(reset: d["r"] as? Bool ?? false, json: json))
            return
        }
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
                            Button { web.closeTab(i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plainHit).tip(L("Close tab"))
                        }
                    }
                    .foregroundStyle(i == state.active ? Color.symText : Color.symDim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: 170)
                    .background(RoundedRectangle(cornerRadius: 7).fill(i == state.active ? Color.symRaised : Color.clear))
                    .onTapGesture { web.select(i) }
                }
                Button { web.newTab() } label: { Image(systemName: "plus").font(.system(size: 10)) }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("New tab"))
                Spacer()
                if let d = DevicePreset.find(state.device) {
                    Text("\(d.name)  " + String(Int(d.width)) + " × " + String(Int(d.height))).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.symAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.symAccent.opacity(0.12)))
                }
            }
            HStack(spacing: 8) {
                Button(action: web.back) { Image(systemName: "chevron.left") }.disabled(!state.canBack).tip(L("Back"))
                Button(action: web.forward) { Image(systemName: "chevron.right") }.disabled(!state.canForward).tip(L("Forward"))
                Button(action: web.reload) { Image(systemName: state.loading ? "xmark" : "arrow.clockwise") }.tip(state.loading ? "Stop" : "Reload")
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 10)).foregroundStyle(Color.symDim)
                    TextField("", text: $state.address, prompt: Text(L("Address or :port")).foregroundColor(Color.symDim))
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                        .autoFocus(state.address.isEmpty)
                        .onSubmit { web.navigate(state.address) }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.symRaised))
                Menu {
                    Button(L("Fit to tile")) { web.setDevice(nil) }
                    ForEach(["Monitor", "Phone", "Tablet"], id: \.self) { g in
                        Section(g) {
                            ForEach(DevicePreset.all.filter { $0.group == g }) { d in
                                Button(d.name + "  " + String(Int(d.width)) + " × " + String(Int(d.height))) { web.setDevice(d.id) }
                            }
                        }
                    }
                } label: { Image(systemName: "display") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).hint(L("Display size"))
                Button(action: web.openInspector) { Image(systemName: "ladybug") }.tip(L("Open inspector tile"))
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
            Label(L("Open a page"), systemImage: "globe").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText)
            Text(L("LOCALHOST")).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color(hex: "#6FCF97"))
                Text(L("http://localhost:")).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.symDim).fixedSize()
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
            Text(L("QUICK OPEN")).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim).padding(.top, 4)
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
            Text(L("or type any address above")).font(.system(size: 11)).foregroundStyle(Color.symDim)
        }
        .padding(16)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.symSurface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.symBorder))
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.symSurface)
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
