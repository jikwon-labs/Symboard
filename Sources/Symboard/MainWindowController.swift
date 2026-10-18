import AppKit
import SwiftUI
import SymboardCore

/// 메인 창: 꽉 찬 보드 위에 떠 있는 막대들(위쪽 바, 좌우 세로 막대, 아래 명령 바, 배율, 브랜치 칩).
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: AppModel
    let chrome = ChromeModel()
    let scrollView = BoardScrollView(frame: .zero)
    let sidePanel = SidePanelController()
    private let panelContainer = NSView()
    private var homeHost: NSView!
    private var canvases: [UUID: CanvasView] = [:]
    private var shownWorkspaceID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var gitTimer: Timer?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Symboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.canvas
        window.setFrameAutosaveName("SymboardMain")
        window.minSize = NSSize(width: 900, height: 560)
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("SymboardMain") { window.center() }
        model.assignProjects(fallback: NewTerminalDialog.lastCwd)
        buildUI()
        observe()
        sidePanel.addTab("Memory", view: AnyView(MemoryPanelView(memory: model.memory, panel: sidePanel.state)))
        sidePanel.addTab("Profiles", view: AnyView(ProfilesPanelView(profiles: model.profiles) { [weak self] p in
            self?.addTerminal(spec: TerminalSpec(agent: p.agent, cwd: self?.projectPath ?? NewTerminalDialog.lastCwd, profileID: p.id), at: nil,
                              title: "\(p.agent.displayName) (\(p.name))")
        }))
        sidePanel.addTab("Usage", view: AnyView(UsagePanelView(store: model.usage)))
        sidePanel.addTab("Loops", view: AnyView(LoopPanelView(runner: model.loops) { [weak self] in self?.newLoop(for: nil) }))
        showWorkspace(model.selectedWorkspace.id)
        refreshGit()
        gitTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGit() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 지금 프로젝트 폴더. 새 노드의 기본 작업 폴더가 된다.
    var projectPath: String { model.selectedWorkspace.projectPath ?? NewTerminalDialog.lastCwd }

    // MARK: 화면 구성

    private func host<V: View>(_ v: V) -> NSHostingView<V> {
        let h = NSHostingView(rootView: v)
        h.translatesAutoresizingMaskIntoConstraints = false
        return h
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        let home = HiddenAwareHostingView(rootView: HomeView(model: model, c: self))
        home.translatesAutoresizingMaskIntoConstraints = false
        home.isHidden = true
        homeHost = home
        content.addSubview(home)

        sidePanel.model = model
        sidePanel.onFocusNode = { [weak self] id in self?.focus(nodeID: id) }
        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.wantsLayer = true
        panelContainer.layer?.cornerRadius = 16
        panelContainer.layer?.masksToBounds = true
        panelContainer.layer?.borderWidth = 1
        panelContainer.layer?.borderColor = Theme.border.cgColor
        panelContainer.layer?.backgroundColor = Theme.surface.cgColor
        panelContainer.isHidden = true
        panelContainer.addSubview(sidePanel.view)
        content.addSubview(panelContainer)

        let topLeft = host(TopLeftBar(model: model, chrome: chrome, c: self))
        let topRight = host(TopRightBar(chrome: chrome, c: self))
        let left = host(LeftRail(chrome: chrome, c: self))
        let right = host(RightRail(chrome: chrome, c: self))
        let bottom = host(BottomBar(chrome: chrome, c: self))
        let branch = host(BranchChip(chrome: chrome))
        let zoom = host(ZoomControl(chrome: chrome, c: self))
        let hint = host(HintBanner(chrome: chrome))
        let selection = host(SelectionPanel(model: model, chrome: chrome, c: self))
        for v in [topLeft, topRight, left, right, bottom, branch, zoom, hint, selection] as [NSView] { content.addSubview(v) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            home.topAnchor.constraint(equalTo: content.topAnchor),
            home.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            home.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            home.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            topLeft.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            topLeft.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 84),
            topRight.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            topRight.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            left.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            bottom.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            branch.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            branch.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            zoom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            zoom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            selection.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 10),
            selection.centerYAnchor.constraint(equalTo: left.centerYAnchor),
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            panelContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: 54),
            panelContainer.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -12),
            panelContainer.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -12),
            panelContainer.widthAnchor.constraint(equalToConstant: 340),
            sidePanel.view.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            sidePanel.view.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            sidePanel.view.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            sidePanel.view.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
        ])
    }

    private var eventMonitor: Any?
    private var keyMonitor: Any?

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
                    // 놓기·지우개 도구일 때는 노드 위를 눌러도 캔버스가 받는다.
                    if self.chrome.tool != .select && self.chrome.tool != .pen, let canvas = nodeView.canvas {
                        canvas.mouseDown(with: event)
                        return nil
                    }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return event }
                if event.keyCode == 53, self.chrome.tool != .select {
                    self.setTool(.select)
                    return nil
                }
                // 캔버스에 초점이 있을 때 Delete 는 고른 글자·스티키·이미지를 지운다.
                if [51, 117].contains(event.keyCode), self.window?.firstResponder === self.currentCanvas,
                   let id = self.currentCanvas?.selectedNodeID, let n = self.model.node(id), NodeView.isHeaderless(n.kind) {
                    self.deleteSelection()
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportMoved() }
        })
    }

    private func viewportMoved() {
        let pct = Int((scrollView.magnification * 100).rounded())
        if chrome.zoomPercent != pct { chrome.zoomPercent = pct }
    }

    // MARK: 작업공간

    private func workspacesChanged() {
        // 지워진 작업공간의 캔버스는 버린다.
        let ids = Set(model.state.workspaces.map(\.id))
        for id in canvases.keys where !ids.contains(id) { canvases[id] = nil }
        if shownWorkspaceID != model.selectedWorkspace.id { showWorkspace(model.selectedWorkspace.id) }
        sidePanel.reload()
        refreshGit()
    }

    func canvas(for id: UUID) -> CanvasView {
        if let c = canvases[id] { return c }
        let c = CanvasView(workspaceID: id, model: model)
        c.controller = self
        c.onSelect = { [weak self] nid in
            self?.sidePanel.selectedNodeID = nid
            if self?.chrome.selectedNodeID != nid { self?.chrome.selectedNodeID = nid }
        }
        canvases[id] = c
        return c
    }

    var currentCanvas: CanvasView? { shownWorkspaceID.flatMap { canvases[$0] } }

    func showWorkspace(_ id: UUID) {
        captureViewports()
        shownWorkspaceID = id
        let c = canvas(for: id)
        c.tool = chrome.tool
        scrollView.documentView = c
        let vp = model.workspace(id)?.viewport ?? Viewport()
        // 레이아웃이 끝난 뒤에 중앙을 맞춘다.
        DispatchQueue.main.async { [weak self] in
            self?.scrollView.center(on: vp.center, zoom: vp.zoom)
        }
        sidePanel.reload()
    }

    /// 지금 보이는 위치·배율을 모델에 적는다.
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
        currentCanvas?.layoutGroups()
        let live = model.sessions.liveCount
        if chrome.liveCount != live { chrome.liveCount = live }
        let loops = model.selectedWorkspace.loops.filter(\.enabled).count
        if chrome.loopBadge != loops { chrome.loopBadge = loops }
        captureViewports()
    }

    private var gitBusy = false
    func refreshGit() {
        guard !gitBusy else { return }
        gitBusy = true
        let path = projectPath
        Task { @MainActor in
            let out = await GitRunner.run(["status", "--porcelain=v2", "--branch"], cwd: path)
            gitBusy = false
            if out.code == 0 {
                let s = GitStatus.parse(out.out)
                chrome.branch = s.branch
                chrome.changeCount = s.changes.count
            } else {
                chrome.branch = nil
                chrome.changeCount = 0
            }
        }
    }

    func focus(nodeID: UUID) {
        guard let wsID = model.workspaceID(containing: nodeID), let node = model.node(nodeID) else { return }
        if chrome.showingHome { setHome(false) }
        if wsID != shownWorkspaceID { model.selectWorkspace(wsID) }
        let c = canvas(for: wsID)
        let center = Point(x: node.frame.x + node.frame.w / 2, y: node.frame.y + node.frame.h / 2)
        scrollView.center(on: center, zoom: max(scrollView.magnification, 0.8))
        c.select(nodeID)
        if let s = model.sessions.session(for: nodeID) { window?.makeFirstResponder(s.view) }
    }

    // MARK: 프로젝트·홈

    func setHome(_ on: Bool) {
        chrome.showingHome = on
        homeHost.isHidden = !on
        scrollView.isHidden = on
    }

    func goHome() { captureViewports(); setHome(true) }

    func openProject(_ path: String) {
        NewTerminalDialog.lastCwd = path
        if let ws = model.state.workspaces.first(where: { $0.projectPath == path }) {
            model.selectWorkspace(ws.id)
        } else {
            let ws = model.addWorkspace(name: "Workspace 1")
            model.mutateWorkspace(ws.id) { $0.projectPath = path }
        }
        setHome(false)
        refreshGit()
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a project folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url.path)
    }

    func closeProject() { goHome() }

    func closeWorkspace(_ id: UUID) {
        guard let ws = model.workspace(id) else { return }
        let siblings = model.state.workspaces.filter { $0.projectPath == ws.projectPath }
        if !ws.nodes.isEmpty {
            let a = NSAlert()
            a.messageText = "Close \(ws.name)?"
            let terms = ws.nodes.filter { $0.kind == .terminal }.count
            a.informativeText = terms > 0 ? "\(terms) console\(terms == 1 ? "" : "s") in it will be stopped." : "Everything on it will be removed."
            a.addButton(withTitle: "Close")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        if siblings.count <= 1 {
            // 프로젝트의 마지막 작업공간이면 빈 것으로 바꿔 둔다.
            let fresh = model.addWorkspace(name: "Workspace 1")
            model.mutateWorkspace(fresh.id) { $0.projectPath = ws.projectPath }
        }
        model.removeWorkspace(id)
    }

    func renameWorkspace(_ id: UUID) {
        guard let ws = model.workspace(id), let name = Prompt.text(title: "Rename workspace", value: ws.name), !name.isEmpty else { return }
        model.renameWorkspace(id, to: name)
    }

    // MARK: 도구

    func setTool(_ t: BoardTool) {
        chrome.tool = t
        currentCanvas?.tool = t
    }

    func openStudio(tab: String) {
        showStudio(root: URL(fileURLWithPath: projectPath))
        studio?.studio.tab = tab
    }

    func openShapes() { chrome.flash("Shapes come with the whiteboard tools") }

    func openDiagram() { openStudio(tab: "Diagram") }

    func showPanel(tab: String) {
        sidePanel.state.tab = tab
        panelContainer.isHidden = false
        chrome.panelOpen = true
    }

    func togglePanel(tab: String) {
        if !panelContainer.isHidden && sidePanel.state.tab == tab {
            panelContainer.isHidden = true
            chrome.panelOpen = false
        } else { showPanel(tab: tab) }
    }

    func openUsage() { togglePanel(tab: "Usage") }
    func openProfiles() { togglePanel(tab: "Profiles") }
    func openLoops() { togglePanel(tab: "Loops") }
    func openMemory() { togglePanel(tab: "Memory") }
    func openMission() { togglePanel(tab: "Mission") }
    func openSettings() { chrome.flash("Settings: drag folders onto Home to add projects") }

    /// 놓기 도구로 캔버스를 눌렀을 때.
    func place(_ p: Placement, at point: Point) {
        let s = p.size
        let origin = Point(x: point.x - s.width / 2, y: point.y - 20)
        switch p {
        case .agent(let id):
            let choice = AgentCatalog.choice(id: id) ?? AgentCatalog.shared.lastChoice
            addTerminal(spec: choice.spec(cwd: projectPath), at: origin, size: s)
        case .text:
            addNode(kind: .text, size: s, title: "Text", at: origin) { $0.text = ""; $0.style = NodeStyle(fontSize: 44, font: "hand") }
            if let id = currentCanvas?.selectedNodeID {
                DispatchQueue.main.async { [weak self] in self?.currentCanvas?.nodeViews[id]?.setEditing(true) }
            }
        case .sticky:
            addNode(kind: .sticky, size: s, title: "Note", at: origin) { $0.text = ""; $0.colorHex = "#E9C46A" }
        case .checklist:
            addNode(kind: .checklist, size: s, title: "Checklist", at: origin) { $0.checklist = [] }
        case .kanban:
            addNode(kind: .kanban, size: s, title: "Board", at: origin) {
                $0.kanban = ["Backlog", "To Do", "In Progress", "Done"].map { KanbanColumn(title: $0) }
            }
        case .web:
            addNode(kind: .web, size: s, title: "Web", at: origin) { $0.text = "http://localhost:3000" }
        }
        setTool(.select)
    }

    /// 선택한 노드를 옆에 하나 더 만든다. 터미널은 같은 CLI 로 새 세션.
    func duplicateSelection() {
        guard let id = currentCanvas?.selectedNodeID, let n = model.node(id) else {
            chrome.flash("Select something to duplicate"); return
        }
        var copy = BoardNode(kind: n.kind, frame: Rect(x: n.frame.x + 40, y: n.frame.y + 40, w: n.frame.w, h: n.frame.h), title: n.title,
                             terminal: n.terminal, text: n.text, colorHex: n.colorHex, checklist: n.checklist, kanban: n.kanban,
                             strokes: n.strokes, teamID: n.teamID, role: n.role)
        copy.style = n.style
        if var spec = copy.terminal {
            spec.sessionID = nil
            spec.hasLaunched = false
            copy.terminal = spec
            copy.title = nextName()
        }
        model.addNode(copy)
        currentCanvas?.select(copy.id)
    }

    func renameTeam(_ id: UUID) {
        guard let t = model.selectedWorkspace.teams.first(where: { $0.id == id }),
              let name = Prompt.text(title: "Rename group", value: t.name), !name.isEmpty else { return }
        model.mutateWorkspace(model.selectedWorkspace.id) { ws in
            if let i = ws.teams.firstIndex(where: { $0.id == id }) { ws.teams[i].name = name }
        }
        currentCanvas?.layoutGroups()
    }

    func ungroup(_ id: UUID) {
        model.mutateWorkspace(model.selectedWorkspace.id) { ws in
            for i in ws.nodes.indices where ws.nodes[i].teamID == id { ws.nodes[i].teamID = nil }
            ws.teams.removeAll { $0.id == id }
            ws.links?.removeAll { $0.to == id || $0.from == id }
        }
        currentCanvas?.layoutGroups()
    }

    /// 그룹의 콘솔을 모두 닫는다. 이름을 보여 주고 한 번 묻는다.
    func closeTeam(_ id: UUID) {
        let ids = model.selectedWorkspace.nodes.filter { $0.teamID == id }.map(\.id)
        closeNodes(ids)
    }

    /// 여러 노드를 닫기 전에 이름을 늘어놓고 확인한다.
    func closeNodes(_ ids: [UUID]) {
        let nodes = ids.compactMap { model.node($0) }
        guard !nodes.isEmpty else { return }
        if nodes.count > 1 {
            let names = nodes.map(\.title)
            let shown = names.prefix(5).joined(separator: ", ") + (names.count > 5 ? " +\(names.count - 5)" : "")
            chrome.confirm = PendingConfirm(message: "\(shown): about to close \(nodes.count) consoles", button: "Close \(nodes.count)") { [weak self] in
                self?.removeNodes(nodes.map(\.id))
            }
            return
        }
        removeNodes(nodes.map(\.id))
    }

    private func removeNodes(_ ids: [UUID]) {
        for n in ids.compactMap({ model.node($0) }) {
            currentCanvas?.nodeViews[n.id]?.content.teardown()
            model.removeNode(n.id)
        }
        let wsID = model.selectedWorkspace.id
        model.mutateWorkspace(wsID) { ws in
            let used = Set(ws.nodes.compactMap(\.teamID))
            ws.teams.removeAll { !used.contains($0.id) }
        }
        currentCanvas?.layoutGroups()
    }

    func deleteSelection() {
        guard let id = currentCanvas?.selectedNodeID else { return }
        currentCanvas?.nodeViews[id]?.content.teardown()
        currentCanvas?.select(nil)
        model.removeNode(id)
    }

    /// 아래 명령 바 입력을 대상 노드에 보낸다.
    func runCommand() {
        var text = chrome.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // "/close @이름..." 은 보내지 않고 그 콘솔들을 닫는다(여럿이면 확인).
        let closing = text.hasPrefix("/close")
        if closing { text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) + " _" }
        let ws = model.selectedWorkspace
        let cands = ws.nodes.filter { $0.kind == .terminal }.map { n in
            CommandTargets.Candidate(id: n.id, name: n.title, team: n.teamID.flatMap { t in ws.teams.first { $0.id == t }?.name })
        }
        let parsed = CommandTargets.parse(text, candidates: cands)
        var targets = parsed.nodeIDs
        if parsed.implicit, let sel = currentCanvas?.selectedNodeID, model.node(sel)?.kind == .terminal { targets = [sel] }
        if !parsed.unknown.isEmpty { chrome.flash("No console named @\(parsed.unknown[0])"); return }
        if closing {
            chrome.command = ""
            closeNodes(targets)
            return
        }
        guard !targets.isEmpty, !parsed.body.isEmpty else {
            chrome.flash(parsed.body.isEmpty ? "Type something to send" : "Select a console or start with @name")
            return
        }
        for id in targets { model.sessions.session(for: id)?.sendText(parsed.body, submit: true) }
        chrome.command = ""
        chrome.flash("Sent to \(targets.count) console\(targets.count == 1 ? "" : "s")")
    }

    /// New console / Spawn N: 마지막으로 고른 CLI 를 화면 가운데 근처에 띄운다.
    func spawnQuick(count: Int) {
        let choice = AgentCatalog.shared.lastChoice
        if count == 1 {
            addTerminal(spec: choice.spec(cwd: projectPath), at: nil)
        } else {
            launchTeam(spec: choice.spec(cwd: projectPath), count: count, teamName: "Team", roles: [])
        }
    }

    func spawnPreset(_ p: ComposerPreset) {
        let specs = p.parts.flatMap { part in Array(repeating: (AgentCatalog.choice(id: part.agentID) ?? AgentCatalog.shared.lastChoice).spec(cwd: projectPath), count: part.count) }
        launchTeam(specs: specs, teamName: p.name, roles: [])
    }

    /// 모든 콘솔 프로세스를 잠시 멈추거나 다시 돌린다.
    func pauseAll(_ pause: Bool) {
        let n = model.sessions.signalAll(pause ? SIGSTOP : SIGCONT)
        chrome.flash(pause ? "Paused \(n) console\(n == 1 ? "" : "s")" : "Resumed \(n) console\(n == 1 ? "" : "s")")
    }

    func newTerminal() { newTerminal(at: nil) }

    func newTerminal(at point: Point?) {
        NewTerminalDialog.lastCwd = projectPath
        guard let spec = NewTerminalDialog.run(profiles: model.state.profiles) else { return }
        addTerminal(spec: spec, at: point)
    }

    @discardableResult
    func addTerminal(spec: TerminalSpec, at point: Point?, size: CGSize = CGSize(width: 640, height: 400),
                     title: String? = nil, teamID: UUID? = nil, role: String? = nil) -> BoardNode {
        let frame: Rect
        if let point { frame = Rect(x: point.x, y: point.y, w: size.width, h: size.height) }
        else { frame = model.suggestedFrame(size: size, near: scrollView.visibleCenter) }
        let name = title ?? nextName()
        let node = BoardNode(kind: .terminal, frame: frame, title: name, terminal: spec, teamID: teamID, role: role)
        model.addNode(node)
        currentCanvas?.select(node.id)
        return node
    }

    /// 이 작업공간에서 아직 안 쓴 짧은 이름.
    func nextName() -> String {
        NamePool.next(used: Set(model.selectedWorkspace.nodes.filter { $0.kind == .terminal }.map(\.title)))
    }

    static func defaultTitle(for spec: TerminalSpec) -> String {
        let folder = (spec.cwd as NSString).lastPathComponent
        switch spec.agent {
        case .custom: return "\(((spec.executable ?? "") as NSString).lastPathComponent) - \(folder)"
        default: return "\(spec.agent.displayName) - \(folder)"
        }
    }

    func addNode(kind: NodeKind, size: CGSize, title: String, at point: Point? = nil, configure: (inout BoardNode) -> Void = { _ in }) {
        var frame = model.suggestedFrame(size: size, near: scrollView.visibleCenter)
        if let point { frame.x = point.x; frame.y = point.y }
        var node = BoardNode(kind: kind, frame: frame, title: title)
        configure(&node)
        model.addNode(node)
        currentCanvas?.select(node.id)
    }

    func newLoop(for nodeID: UUID?) {
        guard let rule = LoopDialog.run(nodes: model.selectedWorkspace.nodes, preselect: nodeID ?? currentCanvas?.selectedNodeID) else { return }
        model.loops.add(rule)
        showPanel(tab: "Loops")
    }

    var studio: StudioWindowController?

    @objc func openStudio(_ sender: Any?) {
        showStudio(root: URL(fileURLWithPath: projectPath))
    }

    func showStudio(root: URL?) {
        if studio == nil {
            studio = StudioWindowController(root: root ?? URL(fileURLWithPath: projectPath)) { [weak self] url in
                self?.pinFile(url)
            }
        } else if let root { studio?.studio.root = root }
        studio?.showWindow(nil)
    }

    /// 스튜디오에서 고른 파일을 보드에 노드로 고정한다.
    func pinFile(_ url: URL) {
        addNode(kind: .file, size: CGSize(width: 560, height: 420), title: url.lastPathComponent) { $0.text = url.path }
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func openComposer(_ sender: Any?) {
        NewTerminalDialog.lastCwd = projectPath
        guard let r = ComposerDialog.run() else { return }
        launchTeam(spec: r.spec, count: r.count, teamName: r.teamName, roles: r.roles)
    }

    /// 노드 여러 개를 격자로 띄우고 새 팀으로 묶는다.
    @discardableResult
    func launchTeam(spec: TerminalSpec, count: Int, teamName: String, roles: [String?]) -> Team {
        launchTeam(specs: Array(repeating: spec, count: count), teamName: teamName, roles: roles)
    }

    @discardableResult
    func launchTeam(specs: [TerminalSpec], teamName: String, roles: [String?], colorHex: String? = nil) -> Team {
        let wsID = model.selectedWorkspace.id
        let color = colorHex ?? Composer.teamColors[model.selectedWorkspace.teams.count % Composer.teamColors.count]
        let team = Team(name: teamName, colorHex: color)
        model.mutateWorkspace(wsID) { $0.teams.append(team) }
        let frames = Composer.frames(count: specs.count, center: scrollView.visibleCenter, size: (w: 520, h: 330))
        for (i, f) in frames.enumerated() {
            let role = i < roles.count ? roles[i] : nil
            addTerminal(spec: specs[i], at: Point(x: f.x, y: f.y), size: CGSize(width: f.w, height: f.h),
                        teamID: team.id, role: role)
        }
        zoomToFit(nil)
        return team
    }

    func addImageFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addImage(url: url, at: nil)
    }

    func addImage(url: URL, at point: Point?) {
        let size = NSImage(contentsOf: url)?.size ?? CGSize(width: 400, height: 300)
        let scale = min(1, 520 / max(size.width, 1))
        let s = CGSize(width: size.width * scale, height: size.height * scale)
        var frame = model.suggestedFrame(size: s, near: scrollView.visibleCenter)
        if let point { frame.x = point.x; frame.y = point.y }
        let node = BoardNode(kind: .image, frame: frame, title: url.lastPathComponent, text: url.path, strokes: [])
        model.addNode(node)
        currentCanvas?.select(node.id)
    }

    func setPen(_ on: Bool) { setTool(on ? .pen : .select) }

    @objc func zoomIn(_ sender: Any?) { scrollView.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { scrollView.zoom(by: 0.8) }
    @objc func zoomReset(_ sender: Any?) {
        scrollView.center(on: scrollView.visibleCenter, zoom: 1)
    }
    @objc func newWorkspace(_ sender: Any?) {
        let n = model.state.workspaces.filter { $0.projectPath == model.selectedWorkspace.projectPath }.count + 1
        let path = model.selectedWorkspace.projectPath
        let ws = model.addWorkspace(name: "Workspace \(n)")
        model.mutateWorkspace(ws.id) { $0.projectPath = path }
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
    }
    @objc func newTerminalMenu(_ sender: Any?) { newTerminal() }
    @objc func nextWorkspace(_ sender: Any?) { cycleWorkspace(1) }
    @objc func previousWorkspace(_ sender: Any?) { cycleWorkspace(-1) }

    private func cycleWorkspace(_ delta: Int) {
        let list = model.state.workspaces.filter { $0.projectPath == model.selectedWorkspace.projectPath }
        guard let i = list.firstIndex(where: { $0.id == model.selectedWorkspace.id }), list.count > 1 else { return }
        model.selectWorkspace(list[(i + delta + list.count) % list.count].id)
    }

    /// 보드 위 모든 노드가 보이게 맞춘다. 떠 있는 막대에 가리지 않게 여백을 둔다.
    @objc func zoomToFit(_ sender: Any?) {
        let nodes = model.selectedWorkspace.nodes
        guard !nodes.isEmpty else { scrollView.center(on: Point(x: 0, y: 0), zoom: 1); return }
        let minX = nodes.map(\.frame.x).min()!, minY = nodes.map(\.frame.y).min()!
        let maxX = nodes.map { $0.frame.x + $0.frame.w }.max()!, maxY = nodes.map { $0.frame.y + $0.frame.h }.max()!
        let size = scrollView.frame.size
        let zoom = min((size.width - 160) / (maxX - minX + 40), (size.height - 220) / (maxY - minY + 40), 1)
        scrollView.center(on: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2 + 20 / max(zoom, 0.1)), zoom: zoom)
    }
}

/// 숨겨져 있을 때 클릭을 가로채지 않는 호스팅 뷰.
final class HiddenAwareHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : super.hitTest(point) }
}

/// 아래 Presets 메뉴의 미리 정한 조합.
struct ComposerPreset: Identifiable {
    struct Part { var agentID: String; var count: Int }
    var id: String { name }
    var name: String
    var parts: [Part]

    static let all: [ComposerPreset] = [
        ComposerPreset(name: "Pair: 2 Claude", parts: [Part(agentID: "claude", count: 2)]),
        ComposerPreset(name: "Mixed: 2 Claude + 2 Codex", parts: [Part(agentID: "claude", count: 2), Part(agentID: "codex", count: 2)]),
        ComposerPreset(name: "Shells: 3", parts: [Part(agentID: "shell", count: 3)]),
    ]
}
