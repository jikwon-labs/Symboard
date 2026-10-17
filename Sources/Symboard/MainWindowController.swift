import AppKit
import SymboardCore

/// 메인 창: 위쪽 작업공간 탭과 도구 막대, 가운데 보드, 오른쪽 패널.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel
    let scrollView = BoardScrollView(frame: .zero)
    let tabBar = WorkspaceTabBar()
    let toolbarStack = NSStackView()
    let split = NSSplitView()
    let sidePanel = SidePanelController()
    private var canvases: [UUID: CanvasView] = [:]
    private var shownWorkspaceID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var penButton: NSButton!

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Symboard"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameAutosaveName("SymboardMain")
        window.minSize = NSSize(width: 800, height: 500)
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("SymboardMain") { window.center() }
        buildUI()
        observe()
        showWorkspace(model.selectedWorkspace.id)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 화면 구성

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let top = NSView()
        top.wantsLayer = true
        top.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor

        toolbarStack.orientation = .horizontal
        toolbarStack.spacing = 6
        toolbarStack.addArrangedSubview(toolButton("New Terminal", symbol: "terminal", action: #selector(newTerminalMenu(_:))))
        penButton = toolButton("Pen", symbol: "pencil.tip", action: #selector(togglePen))
        penButton.setButtonType(.pushOnPushOff)
        toolbarStack.addArrangedSubview(penButton)
        toolbarStack.addArrangedSubview(toolButton("Panel", symbol: "sidebar.right", action: #selector(togglePanel)))

        tabBar.model = model
        [tabBar, toolbarStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            top.addSubview($0)
        }

        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(scrollView)
        split.addArrangedSubview(sidePanel.view)
        sidePanel.model = model
        sidePanel.onFocusNode = { [weak self] id in self?.focus(nodeID: id) }

        [top, split].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 64),
            tabBar.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 80),
            tabBar.topAnchor.constraint(equalTo: top.topAnchor, constant: 4),
            tabBar.heightAnchor.constraint(equalToConstant: 24),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: top.trailingAnchor, constant: -10),
            toolbarStack.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 12),
            toolbarStack.bottomAnchor.constraint(equalTo: top.bottomAnchor, constant: -6),
            toolbarStack.trailingAnchor.constraint(lessThanOrEqualTo: top.trailingAnchor, constant: -10),
            split.topAnchor.constraint(equalTo: top.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidePanel.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
        split.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.split.setPosition(self.split.bounds.width - 300, ofDividerAt: 0)
        }
    }

    func toolButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.imagePosition = .imageLeading
        b.font = .systemFont(ofSize: 12)
        b.controlSize = .regular
        return b
    }

    func addToolButton(_ b: NSButton) { toolbarStack.addArrangedSubview(b) }

    private var eventMonitor: Any?

    private func observe() {
        // 노드 안 어디를 눌러도 그 노드를 선택한다. Option/Cmd 스크롤은 노드 안에서도 보드로 보낸다.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      let hit = self.window?.contentView?.hitTest(event.locationInWindow) else { return event }
                var v: NSView? = hit
                while let cur = v, !(cur is NodeView) { v = cur.superview }
                guard let nodeView = v as? NodeView else { return event }
                if event.type == .leftMouseDown {
                    nodeView.beginInteraction()
                    return event
                }
                if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                    self.scrollView.scrollWheel(with: event)
                    return nil
                }
                return event
            }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .workspacesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.workspacesChanged() }
        })
        observers.append(nc.addObserver(forName: .nodesChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let id = note.object as? UUID else { return }
                self?.canvases[id]?.reloadNodes()
                self?.sidePanel.reload()
            }
        })
        observers.append(nc.addObserver(forName: .statusTick, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatuses() }
        })
        observers.append(nc.addObserver(forName: .canvasDoubleClick, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let p = note.userInfo?["point"] as? Point else { return }
                self?.newTerminal(at: p)
            }
        })
    }

    // MARK: 작업공간

    private func workspacesChanged() {
        tabBar.reload()
        // 지워진 작업공간의 캔버스는 버린다.
        let ids = Set(model.state.workspaces.map(\.id))
        for id in canvases.keys where !ids.contains(id) { canvases[id] = nil }
        if shownWorkspaceID != model.selectedWorkspace.id { showWorkspace(model.selectedWorkspace.id) }
        sidePanel.reload()
    }

    func canvas(for id: UUID) -> CanvasView {
        if let c = canvases[id] { return c }
        let c = CanvasView(workspaceID: id, model: model)
        c.onSelect = { [weak self] nid in self?.sidePanel.selectedNodeID = nid }
        canvases[id] = c
        return c
    }

    var currentCanvas: CanvasView? { shownWorkspaceID.flatMap { canvases[$0] } }

    func showWorkspace(_ id: UUID) {
        captureViewports()
        shownWorkspaceID = id
        let c = canvas(for: id)
        c.tool = penButton.state == .on ? .pen : .select
        scrollView.documentView = c
        tabBar.reload()
        let vp = model.workspace(id)?.viewport ?? Viewport()
        // 레이아웃이 끝난 뒤에 중앙을 맞춘다.
        DispatchQueue.main.async { [weak self] in
            self?.scrollView.center(on: vp.center, zoom: vp.zoom)
        }
        sidePanel.reload()
    }

    /// 현재 보이는 위치·배율을 모델에 적는다.
    func captureViewports() {
        guard let id = shownWorkspaceID, scrollView.documentView != nil else { return }
        let vp = Viewport(center: scrollView.visibleCenter, zoom: scrollView.magnification)
        if model.workspace(id)?.viewport != vp { model.mutateWorkspace(id) { $0.viewport = vp } }
    }

    func windowDidResize(_ notification: Notification) {}

    func windowWillClose(_ notification: Notification) { captureViewports() }

    private func refreshStatuses() {
        for c in canvases.values {
            for (id, v) in c.nodeViews where model.node(id)?.kind == .terminal {
                v.setStatus(model.sessions.status(of: id))
            }
        }
        sidePanel.refreshStatuses()
        captureViewports()
    }

    func focus(nodeID: UUID) {
        guard let wsID = model.workspaceID(containing: nodeID), let node = model.node(nodeID) else { return }
        if wsID != shownWorkspaceID { model.selectWorkspace(wsID) }
        let c = canvas(for: wsID)
        let center = Point(x: node.frame.x + node.frame.w / 2, y: node.frame.y + node.frame.h / 2)
        scrollView.center(on: center, zoom: max(scrollView.magnification, 0.8))
        c.select(nodeID)
        if let s = model.sessions.session(for: nodeID) { window?.makeFirstResponder(s.view) }
    }

    // MARK: 동작

    func newTerminal() { newTerminal(at: nil) }

    func newTerminal(at point: Point?) {
        guard let spec = NewTerminalDialog.run(profiles: model.state.profiles) else { return }
        addTerminal(spec: spec, at: point)
    }

    @discardableResult
    func addTerminal(spec: TerminalSpec, at point: Point?, size: CGSize = CGSize(width: 640, height: 400),
                     title: String? = nil, teamID: UUID? = nil, role: String? = nil) -> BoardNode {
        let frame: Rect
        if let point { frame = Rect(x: point.x, y: point.y, w: size.width, h: size.height) }
        else { frame = model.suggestedFrame(size: size, near: scrollView.visibleCenter) }
        let name = title ?? Self.defaultTitle(for: spec)
        let node = BoardNode(kind: .terminal, frame: frame, title: name, terminal: spec, teamID: teamID, role: role)
        model.addNode(node)
        currentCanvas?.select(node.id)
        return node
    }

    static func defaultTitle(for spec: TerminalSpec) -> String {
        let folder = (spec.cwd as NSString).lastPathComponent
        switch spec.agent {
        case .custom: return "\(((spec.executable ?? "") as NSString).lastPathComponent) - \(folder)"
        default: return "\(spec.agent.displayName) - \(folder)"
        }
    }

    func addNode(kind: NodeKind, size: CGSize, title: String, configure: (inout BoardNode) -> Void = { _ in }) {
        var node = BoardNode(kind: kind, frame: model.suggestedFrame(size: size, near: scrollView.visibleCenter), title: title)
        configure(&node)
        model.addNode(node)
        currentCanvas?.select(node.id)
    }

    @objc func togglePen() {
        let on = penButton.state == .on
        currentCanvas?.tool = on ? .pen : .select
    }

    func showPanel(tab: String) {
        if split.isSubviewCollapsed(sidePanel.view) || sidePanel.view.isHidden { togglePanel() }
        sidePanel.state.tab = tab
    }

    @objc func togglePanel() {
        let collapsed = split.isSubviewCollapsed(sidePanel.view)
        sidePanel.view.isHidden = !collapsed
        split.adjustSubviews()
        if collapsed { split.setPosition(split.bounds.width - 300, ofDividerAt: 0) }
    }

    @objc func zoomIn(_ sender: Any?) { scrollView.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { scrollView.zoom(by: 0.8) }
    @objc func zoomReset(_ sender: Any?) {
        scrollView.center(on: scrollView.visibleCenter, zoom: 1)
    }
    @objc func newWorkspace(_ sender: Any?) { tabBar.addWorkspace() }
    @objc func newTerminalMenu(_ sender: Any?) { newTerminal() }
    @objc func nextWorkspace(_ sender: Any?) { cycleWorkspace(1) }
    @objc func previousWorkspace(_ sender: Any?) { cycleWorkspace(-1) }

    private func cycleWorkspace(_ delta: Int) {
        let list = model.state.workspaces
        guard let i = model.state.selectedIndex, list.count > 1 else { return }
        model.selectWorkspace(list[(i + delta + list.count) % list.count].id)
    }

    /// 보드 위 모든 노드가 보이게 맞춘다.
    @objc func zoomToFit(_ sender: Any?) {
        let nodes = model.selectedWorkspace.nodes
        guard !nodes.isEmpty else { scrollView.center(on: Point(x: 0, y: 0), zoom: 1); return }
        let minX = nodes.map(\.frame.x).min()!, minY = nodes.map(\.frame.y).min()!
        let maxX = nodes.map { $0.frame.x + $0.frame.w }.max()!, maxY = nodes.map { $0.frame.y + $0.frame.h }.max()!
        let size = scrollView.frame.size
        let zoom = min(size.width / (maxX - minX + 80), size.height / (maxY - minY + 80), 1)
        scrollView.center(on: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2), zoom: zoom)
    }
}

/// 위쪽 작업공간 탭.
final class WorkspaceTabBar: NSStackView {
    weak var model: AppModel?

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 4
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let model else { return }
        for ws in model.state.workspaces {
            let b = TabButton(title: ws.name, target: self, action: #selector(tabClicked(_:)))
            b.workspaceID = ws.id
            b.bezelStyle = .recessed
            b.showsBorderOnlyWhileMouseInside = false
            b.setButtonType(.pushOnPushOff)
            b.state = ws.id == model.selectedWorkspace.id ? .on : .off
            b.font = .systemFont(ofSize: 12, weight: b.state == .on ? .semibold : .regular)
            b.menu = tabMenu(for: ws.id)
            addArrangedSubview(b)
        }
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New workspace")!, target: self, action: #selector(addClicked))
        add.bezelStyle = .recessed
        add.toolTip = "New workspace"
        addArrangedSubview(add)
    }

    private func tabMenu(for id: UUID) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem(title: "Rename...") { [weak self] in
            guard let model = self?.model, let ws = model.workspace(id) else { return }
            if let name = Prompt.text(title: "Rename workspace", value: ws.name), !name.isEmpty { model.renameWorkspace(id, to: name) }
        })
        m.addItem(ClosureMenuItem(title: "Delete Workspace") { [weak self] in
            guard let model = self?.model, model.state.workspaces.count > 1 else { NSSound.beep(); return }
            let a = NSAlert()
            a.messageText = "Delete this workspace?"
            a.informativeText = "All nodes in it will be closed."
            a.addButton(withTitle: "Delete")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { model.removeWorkspace(id) }
        })
        return m
    }

    @objc private func tabClicked(_ sender: TabButton) {
        guard let id = sender.workspaceID else { return }
        model?.selectWorkspace(id)
        reload()
    }

    @objc private func addClicked() { addWorkspace() }

    func addWorkspace() {
        guard let model else { return }
        let name = Prompt.text(title: "New workspace", value: "Workspace \(model.state.workspaces.count + 1)")
        guard let name, !name.isEmpty else { return }
        model.addWorkspace(name: name)
    }
}

final class TabButton: NSButton {
    var workspaceID: UUID?
}
