import AppKit
import WebKit
import SymboardCore

/// localhost 같은 주소를 띄우는 웹 타일. 노드 메뉴에서 웹 인스펙터를 연다.
final class WebContent: NSObject, NodeContent, WKNavigationDelegate, NSTextFieldDelegate {
    let nodeID: UUID
    unowned let model: AppModel
    let container = FlippedView()
    let urlField = NSTextField()
    let webView: WKWebView
    var view: NSView { container }

    init(node: BoardNode, model: AppModel) {
        nodeID = node.id
        self.model = model
        let config = WKWebViewConfiguration()
        // 오른쪽 클릭 "Inspect Element" 를 켠다.
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.isInspectable = true
        webView.navigationDelegate = self
        urlField.stringValue = node.text ?? "http://localhost:3000"
        urlField.font = .systemFont(ofSize: 12)
        urlField.bezelStyle = .roundedBezel
        urlField.target = self
        urlField.action = #selector(go)
        container.addSubview(urlField)
        container.addSubview(webView)
        container.onLayout = { [weak self] b in
            self?.urlField.frame = NSRect(x: 6, y: 4, width: b.width - 12, height: 22)
            self?.webView.frame = NSRect(x: 0, y: 30, width: b.width, height: max(0, b.height - 30))
        }
        load(urlField.stringValue)
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Reload") { [weak self] in self?.webView.reload() },
         ClosureMenuItem(title: "Open Web Inspector") { [weak self] in self?.openInspector() }]
    }

    @objc private func go() {
        var s = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "http://" + s }
        urlField.stringValue = s
        model.mutateNode(nodeID) { $0.text = s }
        load(s)
    }

    private func load(_ s: String) {
        guard let url = URL(string: s) else { return }
        webView.load(URLRequest(url: url))
    }

    /// WKWebView 는 인스펙터를 여는 공개 API 가 없다. 내부 객체가 있으면 쓰고, 없으면 오른쪽 클릭 방법을 알려 준다.
    func openInspector() {
        let sel = NSSelectorFromString("_inspector")
        if webView.responds(to: sel), let inspector = webView.perform(sel)?.takeUnretainedValue() as? NSObject,
           inspector.responds(to: NSSelectorFromString("show")) {
            inspector.perform(NSSelectorFromString("show"))
            return
        }
        let a = NSAlert()
        a.messageText = "Right-click the page and choose Inspect Element."
        a.runModal()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }

    private func showError(_ error: Error) {
        let html = "<body style='font:13px -apple-system;color:#bbb;background:#1c1c1c;padding:16px'>Could not load <b>\(urlField.stringValue)</b><br><br>\(error.localizedDescription)</body>"
        webView.loadHTMLString(html, baseURL: nil)
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
}
