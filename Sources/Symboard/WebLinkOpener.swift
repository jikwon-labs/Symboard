import AppKit
import SymboardCore

/// 콘솔의 링크를 웹 타일로 연다(15차).
/// - Cmd+클릭: 그 콘솔과 선으로 이은 웹 타일(없으면 옆에 새로). Cmd+Shift+클릭: 기본 브라우저.
/// - claude 가 답에 링크를 쓰면 세션 기록(JSONL)에서 읽어 같은 웹 타일에 자동으로 연다(설정에서 끔).
@MainActor
final class WebLinkOpener {
    unowned let controller: MainWindowController
    private var model: AppModel { controller.model }
    private var tails: [UUID: ChatTail] = [:]
    /// 콘솔마다 세션 기록에 나온 주소(Cmd+클릭한 조각을 온전한 주소로 되돌릴 때 쓴다).
    private var known: [UUID: [String]] = [:]
    /// 콘솔마다 이미 자동으로 연 주소. 같은 주소를 다시 말해도 또 열지 않는다.
    private var autoOpened: [UUID: Set<String>] = [:]
    private var timer: Timer?

    init(controller: MainWindowController) { self.controller = controller }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    // MARK: 클릭

    /// 콘솔 줄에서 Cmd+클릭한 자리. 주소가 아니면 아무것도 하지 않는다.
    func commandClick(text: String, index: Int, in consoleID: UUID, external: Bool) {
        guard let url = ConsoleWebLinks.url(at: index, in: text, known: known[consoleID] ?? []) else { return }
        open(url, from: consoleID, external: external)
    }

    /// external 이면 기본 브라우저, 아니면 콘솔과 이은 웹 타일.
    func open(_ url: String, from consoleID: UUID, external: Bool) {
        if external {
            if let u = URL(string: WebAddress.normalize(url)) { NSWorkspace.shared.open(u) }
            return
        }
        showInTile(url, from: consoleID, focus: true)
    }

    // MARK: 웹 타일

    /// 콘솔과 선으로 이은 웹 타일에 주소를 연다. 없으면 콘솔 옆에 새로 놓고 잇는다.
    /// focus 면 타일을 고르고 화면을 그리로 옮긴다(Cmd+클릭). 자동 열기는 보던 화면을 그대로 둔다.
    @discardableResult
    func showInTile(_ url: String, from consoleID: UUID, focus: Bool) -> Bool {
        guard let wsID = model.workspaceID(containing: consoleID),
              let ws = model.state.workspaces.first(where: { $0.id == wsID }) else { return false }
        let address = WebAddress.normalize(url)
        let canvas = controller.existingCanvas(for: wsID)
        let linked = (ws.links ?? []).filter { $0.from == consoleID && $0.style == ConsoleWebLinks.linkStyle }
            .compactMap { l in ws.nodes.first { $0.id == l.to && $0.kind == .web } }
        if let tile = linked.last {
            if let web = canvas?.nodeViews[tile.id]?.content as? WebContent {
                web.open(address)
            } else {
                // 아직 화면이 없는 작업공간: 저장된 탭에만 더한다.
                model.mutateNode(tile.id) { n in
                    var tabs = n.tabs ?? [n.text ?? ""]
                    if let i = tabs.firstIndex(of: address) { n.activeTab = i }
                    else if tabs.count == 1, tabs[0].isEmpty { tabs[0] = address; n.activeTab = 0 }
                    else { tabs.append(address); n.activeTab = tabs.count - 1 }
                    n.tabs = tabs
                    n.text = address
                }
            }
            if focus { reveal(tile.id, in: wsID) }
            return true
        }
        // 새 타일은 지금 보는 작업공간에만 놓는다(자리 찾기가 보는 작업공간 기준).
        guard wsID == model.selectedWorkspace.id else { return false }
        let f = controller.besideFrame(w: 900, h: 620, near: consoleID)
        let node = BoardNode(kind: .web, frame: f, title: "Web", text: address)
        var withTabs = node
        withTabs.tabs = [address]
        model.addNode(withTabs, to: wsID)
        model.mutateWorkspace(wsID) { w in
            var links = w.links ?? []
            links.append(NodeLink(from: consoleID, to: node.id, style: ConsoleWebLinks.linkStyle))
            w.links = links
        }
        canvas?.reloadNodes()
        canvas?.layoutLinks()
        if focus { reveal(node.id, in: wsID) }
        return true
    }

    private func reveal(_ id: UUID, in wsID: UUID) {
        guard wsID == model.selectedWorkspace.id, let n = model.node(id) else { return }
        controller.currentCanvas?.select(id)
        controller.glideReveal([n.frame])
    }

    // MARK: 자동 열기

    /// claude 콘솔의 세션 기록에서 새 답을 읽어 주소를 모은다. 처음 읽는 기록(앱을 켰을 때 등)은 모으기만 하고 열지 않는다.
    private func poll() {
        var live = Set<UUID>()
        let auto = ConsoleWebLinks.autoOpen(Prefs.shared)
        for ws in model.state.workspaces {
            for n in ws.nodes where n.kind == .terminal {
                guard let spec = n.terminal, spec.agent == .claude, let path = Self.transcriptPath(spec, model: model) else { continue }
                live.insert(n.id)
                var tail = tails[n.id] ?? ChatTail(path: path)
                let firstRead = tails[n.id] == nil || tail.path != path
                if tail.path != path { tail = ChatTail(path: path) }
                let fresh = tail.readNew()
                tails[n.id] = tail
                let urls = fresh.filter { $0.role == "assistant" }.flatMap { ConsoleWebLinks.urls(in: $0.text) }
                guard !urls.isEmpty else { continue }
                ConsoleWebLinks.remember(urls, in: &known[n.id, default: []])
                if firstRead {
                    autoOpened[n.id, default: []].formUnion(urls)
                    continue
                }
                guard auto else { continue }
                for u in urls where !autoOpened[n.id, default: []].contains(u) {
                    autoOpened[n.id, default: []].insert(u)
                    if showInTile(u, from: n.id, focus: false), ws.id == model.selectedWorkspace.id {
                        controller.chrome.flash(String(format: L("Opened %@ in a web tile"), u))
                    }
                }
            }
        }
        for id in tails.keys where !live.contains(id) { tails[id] = nil; known[id] = nil; autoOpened[id] = nil }
    }

    /// claude 콘솔의 세션 기록 파일. 세션 id 를 아직 모르면 nil.
    static func transcriptPath(_ spec: TerminalSpec, model: AppModel) -> String? {
        guard spec.agent == .claude, let sid = spec.sessionID else { return nil }
        let profile = spec.profileID.flatMap { pid in model.state.profiles.first { $0.id == pid } }
        let base = (profile?.agent == .claude ? profile?.configDir : nil) ?? (NSHomeDirectory() + "/.claude")
        return "\(base)/projects/\(LaunchPlanner.claudeProjectDirName(for: LaunchPlanner.resolvedPath(spec.cwd)))/\(sid).jsonl"
    }
}
