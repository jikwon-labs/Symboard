import AppKit
import Combine
import SwiftUI
import SymboardCore

/// 메인 창: 꽉 찬 보드 위에 떠 있는 막대들(위쪽 바, 좌우 세로 막대, 아래 명령 바, 배율, 브랜치 칩).
/// 본 창. Ctrl+Tab 은 키 감시(local monitor)·메뉴까지 오지 않고 창의 키 보기 순환에 먼저 쓰여서, 창이 받기 전에 가로챈다.
final class BoardWindow: NSWindow {
    var keyIntercept: ((NSEvent) -> Bool)?
    /// 보드 되돌리기(9차). 글을 고치는 칸(명령 바·스티커 편집)에 되돌릴 입력이 있으면 그 글부터 되돌리고, 없으면 보드를 되돌린다.
    /// 명령 바 입력칸이 거의 늘 초점을 갖고 있어서, 글 쪽에 되돌릴 것이 없을 때도 글로 보내면 ⌘Z 가 아무 일도 하지 않았다.
    var boardUndo: ((_ redo: Bool) -> Void)?
    var boardCanUndo: ((_ redo: Bool) -> Bool)?

    private func textCan(redo: Bool) -> Bool {
        guard firstResponder is NSText, let um = undoManager else { return false }
        return redo ? um.canRedo : um.canUndo
    }

    @objc func undo(_ sender: Any?) {
        if textCan(redo: false) { undoManager?.undo() } else { boardUndo?(false) }
    }

    @objc func redo(_ sender: Any?) {
        if textCan(redo: true) { undoManager?.redo() } else { boardUndo?(true) }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return textCan(redo: false) || (boardCanUndo?(false) ?? false) }
        if item.action == #selector(redo(_:)) { return textCan(redo: true) || (boardCanUndo?(true) ?? false) }
        return super.validateUserInterfaceItem(item)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let f = keyIntercept, f(event) { return }
        super.sendEvent(event)
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSPopoverDelegate {
    let model: AppModel
    let chrome = ChromeModel()
    let composer = ComposerState()
    let loopDraft = LoopDraft()
    lazy var studioState = StudioState(root: URL(fileURLWithPath: projectPath))
    lazy var diagrams = DiagramMaker(c: self)
    lazy var docStudio: DocStudioState = { let d = DocStudioState(model: model); d.c = self; return d }()
    lazy var memoryHub: MemoryHub = { let h = MemoryHub(model: model); h.c = self; return h }()
    /// 새 버전 알림(위쪽 오른쪽 알약).
    private(set) lazy var updates = UpdateChecker(chrome: chrome)
    let scrollView = BoardScrollView(frame: .zero)
    let sidePanel = SidePanelController()
    private let panelContainer = NSView()
    private var homeHost: NSView!
    private var missionHost: NSView?
    private var missionObserver: Any?
    private var loopsObserver: Any?
    private var studioObserver: Any?
    private var memObserver: Any?
    private var canvases: [UUID: CanvasView] = [:]
    private var shownWorkspaceID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var gitTimer: Timer?
    private var usageTimer: Timer?
    /// 지금 창. 시작할 때 저장된 노드를 만드는 동안에는 AppDelegate.windowController 가 아직 비어 있어서 이걸 쓴다.
    private(set) static weak var current: MainWindowController?

    init(model: AppModel) {
        self.model = model
        let window = BoardWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Symboard"
        // 창을 닫아도 앱과 콘솔은 살아 있고, Dock 아이콘을 누르면 같은 창을 다시 연다.
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.canvas
        window.minSize = NSSize(width: 900, height: 560)
        super.init(window: window)
        Self.current = self
        window.delegate = self
        WindowFrames.track(window, key: "main")
        model.assignProjects(fallback: NewTerminalDialog.lastCwd)
        // 상태 틱(1초)은 콘솔이 없어도 돌아야 한다(사용량 알약·루프·미션 맵).
        _ = model.sessions
        _ = model.loops
        buildUI()
        observe()
        CursorWatch.start(window: window)
        TextCursor.install()
        DispatchQueue.main.async { [weak self] in self?.model.usage.refresh() }
        _ = updates
        // 알약이 CLI 와 같은 시각·% 를 보이도록 /usage 도 읽는다(질문 아님). 창이 먼저 뜨게 조금 늦춘다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.model.usage.refreshLimitsIfStale() }
        // 5시간 묶음이 끝나고 새로 시작한 것도 알약에 보이게 가끔 다시 훑는다.
        usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.usage.refresh()
                self?.model.usage.refreshLimitsIfStale()
            }
        }
        showWorkspace(model.selectedWorkspace.id)
        // 다른 작업공간 탭의 콘솔도 앱이 켜지면 바로 돈다(원본처럼 live 수가 전체). 이어하기를 기다리는 것은 답을 받은 뒤 띄운다.
        for ws in model.state.workspaces { for n in ws.nodes where n.kind == .terminal { _ = model.sessions.ensureSession(for: n) } }
        // 열 프로젝트가 없으면(새 상태 폴더) 홈 화면의 폴더 열기로 시작한다.
        if model.selectedWorkspace.projectPath == nil, model.state.workspaces.allSatisfy({ $0.nodes.isEmpty }) { setHome(true) }
        refreshGit()
        gitTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGit() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 지금 프로젝트 폴더. 새 노드의 기본 작업 폴더가 된다.
    var projectPath: String { model.selectedWorkspace.projectPath ?? NewTerminalDialog.lastCwd }

    // MARK: 화면 구성

    private func host<V: View>(_ v: V) -> NSHostingView<AnyView> {
        let h = NSHostingView(rootView: AnyView(v.localized()))
        h.translatesAutoresizingMaskIntoConstraints = false
        return h
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        let home = HiddenAwareHostingView(rootView: HomeView(model: model, c: self).localized())
        home.translatesAutoresizingMaskIntoConstraints = false
        home.sizingOptions = []
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
        Theme.paint { [weak panelContainer] in
            panelContainer?.layer?.borderColor = Theme.border.cgColor
            panelContainer?.layer?.backgroundColor = Theme.surface.cgColor
        }
        panelContainer.isHidden = true
        panelContainer.addSubview(sidePanel.view)
        content.addSubview(panelContainer)

        let topLeft = host(TopLeftBar(model: model, chrome: chrome, c: self))
        let topRight = host(TopRightBar(chrome: chrome, c: self))
        let left = host(LeftRail(chrome: chrome, c: self))
        let right = host(RightRail(chrome: chrome, c: self))
        let bottom = host(BottomBar(chrome: chrome, composer: composer, c: self))
        let branch = host(BranchChip(chrome: chrome))
        let zoom = host(ZoomControl(chrome: chrome, c: self))
        let hint = host(HintBanner(chrome: chrome))
        let selection = host(SelectionPanel(model: model, chrome: chrome, c: self))
        let pen = host(PenPanel(chrome: chrome))
        content.addSubview(pen)
        let drawingChip = host(DrawingChip(maker: diagrams))
        content.addSubview(drawingChip)
        let resume = host(ResumeToast(chrome: chrome, c: self))
        for v in [topLeft, topRight, left, right, bottom, branch, zoom, hint, selection, resume] as [NSView] { content.addSubview(v) }
        let mission = HiddenAwareHostingView(rootView: MissionHost(model: model, chrome: chrome, c: self).localized())
        mission.translatesAutoresizingMaskIntoConstraints = false
        mission.sizingOptions = []
        mission.isHidden = true
        missionHost = mission
        content.addSubview(mission)
        NSLayoutConstraint.activate([
            mission.topAnchor.constraint(equalTo: content.topAnchor),
            mission.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            mission.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mission.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        missionObserver = chrome.$missionOpen.sink { [weak self] open in self?.missionHost?.isHidden = !open }
        // 스튜디오 패널은 보드 위, 위쪽·아래 막대보다는 아래에 둔다.
        let studioHost = HiddenAwareHostingView(rootView: StudioOverlay(studio: studioState, c: self).localized())
        studioHostView = studioHost
        studioHost.translatesAutoresizingMaskIntoConstraints = false
        studioHost.sizingOptions = []
        studioHost.isHidden = true
        content.addSubview(studioHost, positioned: .above, relativeTo: homeHost)
        NSLayoutConstraint.activate([
            studioHost.topAnchor.constraint(equalTo: content.topAnchor),
            studioHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            studioHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            studioHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        studioObserver = studioState.$kind.sink { k in studioHost.isHidden = k == nil }
        let memHost = HiddenAwareHostingView(rootView: MemoryModalView(hub: memoryHub, model: model).localized())
        memHost.translatesAutoresizingMaskIntoConstraints = false
        memHost.sizingOptions = []
        memHost.isHidden = true
        content.addSubview(memHost)
        NSLayoutConstraint.activate([
            memHost.topAnchor.constraint(equalTo: content.topAnchor),
            memHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            memHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            memHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        memObserver = memoryHub.$page.sink { p in memHost.isHidden = p == nil }
        let loopsHost = HiddenAwareHostingView(rootView: LoopsHost(model: model, chrome: chrome, draft: loopDraft, c: self).localized())
        loopsHost.translatesAutoresizingMaskIntoConstraints = false
        loopsHost.sizingOptions = []
        loopsHost.isHidden = true
        content.addSubview(loopsHost)
        NSLayoutConstraint.activate([
            loopsHost.topAnchor.constraint(equalTo: content.topAnchor),
            loopsHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            loopsHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            loopsHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        loopsObserver = chrome.$loopsPage.sink { page in loopsHost.isHidden = page == nil }
        let promptHost = HiddenAwareHostingView(rootView: PromptEditorView(editor: promptEditor).localized())
        promptHost.translatesAutoresizingMaskIntoConstraints = false
        promptHost.sizingOptions = []
        promptHost.isHidden = true
        content.addSubview(promptHost)
        NSLayoutConstraint.activate([
            promptHost.topAnchor.constraint(equalTo: content.topAnchor),
            promptHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            promptHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            promptHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let keysHost = HiddenAwareHostingView(rootView: ShortcutsSheet(chrome: chrome).localized())
        keysHost.translatesAutoresizingMaskIntoConstraints = false
        keysHost.sizingOptions = []
        keysHost.isHidden = true
        content.addSubview(keysHost)
        NSLayoutConstraint.activate([
            keysHost.topAnchor.constraint(equalTo: content.topAnchor),
            keysHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            keysHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            keysHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        shortcutsObserver = chrome.$shortcutsOpen.sink { open in keysHost.isHidden = !open }
        promptObserver = promptEditor.$open.sink { [weak self] open in
            promptHost.isHidden = !open
            if !open { DispatchQueue.main.async { self?.promptEditorClosed() } }
        }
        // 안내 알약("Try @all …")은 모달·팝오버가 열려 있으면 숨긴다(팝오버 뒤로 비치지 않게).
        overlayObserver = Publishers.MergeMany(chrome.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                               composer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                               studioState.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                               memoryHub.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                               diagrams.objectWillChange.map { _ in () }.eraseToAnyPublisher())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateOverlayFlag() }
        composerObserver = composer.$open.removeDuplicates().sink { [weak self] open in
            DispatchQueue.main.async { self?.syncComposerPopover(open) }
        }

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
            resume.topAnchor.constraint(equalTo: topRight.bottomAnchor, constant: 10),
            resume.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            drawingChip.topAnchor.constraint(equalTo: content.topAnchor, constant: 96),
            drawingChip.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pen.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 10),
            pen.centerYAnchor.constraint(equalTo: left.centerYAnchor, constant: -80),
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
    let promptEditor = PromptEditorModel()
    private var promptObserver: AnyCancellable?
    private var shortcutsObserver: AnyCancellable?
    /// 전체 화면 편집을 연 입력칸(닫으면 거기로 초점을 돌린다).
    private weak var promptOrigin: MentionTextField?
    private var flagsMonitor: Any?

    private func observe() {
        // 노드 안 어디를 눌러도 그 노드를 선택한다. Option/Cmd 스크롤은 노드 안에서도 보드로 보낸다.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      let hit = self.window?.contentView?.hitTest(event.locationInWindow) else { return event }
                // 보드(캔버스·노드)를 누르면 THREAD 카드를 접어 그 밑을 쓸 수 있게 한다. 꺾쇠나 다음 보드 명령으로 다시 열린다.
                if event.type == .leftMouseDown, self.chrome.threadOpen, hit.isDescendant(of: self.scrollView) {
                    self.chrome.threadOpen = false
                }
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
                if let path = ProcessInfo.processInfo.environment["SYMBOARD_KEYLOG"] {
                    // 시험 도구가 보낸 키가 어떤 모양으로 오는지 확인용.
                    let line = "key code=\(event.keyCode) chars=\(Array((event.characters ?? "").unicodeScalars).map { $0.value }) raw=\(Array((event.charactersIgnoringModifiers ?? "").unicodeScalars).map { $0.value }) flags=\(event.modifierFlags.rawValue) win=\(event.window?.windowNumber ?? -1)\n"
                    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
                    else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
                }
                guard let self, event.window === self.window else { return event }
                if self.handleConsoleNavigation(event) { return nil }
                if let term = self.window?.firstResponder as? SymTerminalView, let byte = SymTerminalView.rawControlByte(event) {
                    term.send([byte])
                    return nil
                }
                // 콘솔 안 Option·Cmd + ←/→/Backspace 는 macOS 터미널 관례대로 단어·줄 이동과 지우기로, Shift+Enter 는 줄바꿈으로 보낸다.
                if let term = self.window?.firstResponder as? SymTerminalView {
                    let f = event.modifierFlags
                    if let bytes = KeyInput.editBytes(keyCode: event.keyCode, command: f.contains(.command), option: f.contains(.option),
                                                      control: f.contains(.control), shift: f.contains(.shift)) {
                        term.commitMarkedText()
                        term.send(bytes)
                        return nil
                    }
                }
                // Cmd+Shift+E: 초점이 있는 입력칸(없으면 명령 바)의 글을 전체 화면 편집으로 열고 닫는다.
                if event.keyCode == 14, event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift] {
                    self.togglePromptEditor()
                    return nil
                }
                // 입력칸의 @ 목록이 열려 있으면 Esc 는 그 목록만 닫는다(입력칸이 받는다).
                if event.keyCode == 53, MentionTextField.listOpen(for: self.window?.firstResponder) { return event }
                if event.keyCode == 53, self.promptEditor.open { self.promptEditor.close(); return nil }
                if event.keyCode == 53, self.chrome.shortcutsOpen { self.chrome.shortcutsOpen = false; return nil }
                // ? (입력칸·콘솔 밖에서) 는 단축키 표. 한글 입력 상태에서도 Shift+/ 는 ? 로 온다.
                if event.characters == "?", !(self.window?.firstResponder is NSTextView), !(self.window?.firstResponder is SymTerminalView) {
                    self.chrome.shortcutsOpen.toggle()
                    return nil
                }
                // Esc 는 열린 모달부터 닫는다. 닫지 않으면 다음 클릭이 어두운 배경을 눌러 모달을 닫는 데 쓰여 "첫 클릭 무시" 처럼 보였다.
                if event.keyCode == 53, self.closeTopOverlay() { return nil }
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
        startBoardTools()
        model.sessions.onMissingFolder = { [weak self] path in
            self?.chrome.flash(L("Folder not found: %@ · open a folder from Home", (path as NSString).lastPathComponent))
        }
        (window as? BoardWindow)?.boardUndo = { [weak self] redo in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.model.stepBoard(redo: redo) {
                    self.currentCanvas?.select(nil)
                    self.currentCanvas?.layoutLinks()
                    self.chrome.flash(L(redo ? "Redo" : "Undo"))
                }
            }
        }
        (window as? BoardWindow)?.boardCanUndo = { [weak self] redo in
            MainActor.assumeIsolated { redo ? (self?.model.canRedoBoard ?? false) : (self?.model.canUndoBoard ?? false) }
        }
        (window as? BoardWindow)?.keyIntercept = { [weak self] event in
            MainActor.assumeIsolated { self?.handleConsoleNavigation(event) ?? false }
        }
        // Cmd 를 누르고 있는 동안 콘솔 머리에 번호(Cmd+1~9)를 보인다.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return event }
                self.showConsoleNumbers(event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command)
                return event
            }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showConsoleNumbers(false) }
        })
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
        // 화면 모드가 바뀌면 캔버스(바탕·점)와 층에 그린 선·화살표를 다시 칠한다(10차).
        observers.append(nc.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window?.backgroundColor = Theme.canvas
                for cv in self.canvases.values {
                    cv.effectiveAppearance.performAsCurrentDrawingAppearance { cv.layoutLinks() }
                    cv.needsDisplay = true
                    cv.subviews.forEach { $0.needsDisplay = true }
                }
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
        StatusBeat.shared.tick &+= 1
        let pill = model.usage.pill
        if chrome.resetText != pill.text { chrome.resetText = pill.text }
        if chrome.sessionPercent != pill.percent { chrome.sessionPercent = pill.percent }
        let tint = model.usage.pillAgent == .codex ? "#6C7BFF" : "#E8704A"
        if chrome.sessionTint != tint { chrome.sessionTint = tint }
        let pending = model.sessions.pendingResume.count
        if chrome.resumeCount != pending { chrome.resumeCount = pending }
        let live = model.sessions.liveCount
        if chrome.liveCount != live { chrome.liveCount = live }
        let working = model.sessions.workingCount
        if chrome.workingCount != working { chrome.workingCount = working }
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
            let out = await GitRunner.run(["status", "--porcelain=v2", "--branch", "-uall"], cwd: path)
            gitBusy = false
            if out.code == 0 {
                let s = GitStatus.parse(out.out)
                chrome.branch = s.branch
                chrome.changeCount = s.changes.count
                if chrome.gitCard?.repo != path { chrome.gitCard = GitCardModel(repo: path) { _ in } }
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
        } else if let ws = model.state.workspaces.first(where: { $0.projectPath == nil && $0.nodes.isEmpty }) {
            // 처음 실행 때 생긴 빈 작업공간을 이 프로젝트에 쓴다.
            model.mutateWorkspace(ws.id) { $0.projectPath = path }
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

    /// 오른쪽 막대 스튜디오 입구. 지금 프로젝트 폴더에 붙는다.
    func openStudio(tab: String) {
        let root = URL(fileURLWithPath: projectPath)
        if studioState.root != root { studioState.root = root; studioState.selected = nil; studioState.text = ""; studioState.savedText = "" }
        let kind = tab == "Docs" ? "Documents" : tab
        if studioState.kind == kind { closeStudio(); return }
        if kind == "Markdown", studioState.selected?.pathExtension.lowercased() != "md" {
            studioState.selected = nil
            if let readme = studioState.markdownFiles().first(where: { $0.lastPathComponent.lowercased() == "readme.md" }) { studioState.open(readme) }
        } else if kind == "Code", studioState.selected == nil {
            // 원본처럼 코드 스튜디오도 처음에는 README 를 연다.
            if let readme = studioState.markdownFiles().first(where: { $0.lastPathComponent.lowercased() == "readme.md" }) { studioState.open(readme) }
        }
        // 탭은 코드 스튜디오 안에서만 쓴다. 다른 스튜디오에서 열었던 파일은 넘기지 않는다.
        if studioState.kind != kind { studioState.openFiles = studioState.selected.map { [$0] } ?? [] }
        studioState.kind = kind
    }

    /// 문서 스튜디오를 그 종류를 고른 채 연다. nil 이면 직접 요청(요청 칸이 첫 초점).
    func openDocuments(kind: String?) {
        if let kind { docStudio.selected = kind }
        if studioState.kind != "Documents" { openStudio(tab: "Docs") }
    }

    func openStudio(file: URL) {
        let kind = file.pathExtension.lowercased() == "md" ? "Markdown" : "Code"
        studioState.kind = nil
        studioState.root = URL(fileURLWithPath: projectPath)
        studioState.open(file)
        studioState.kind = kind
    }

    /// 닫으면 고친 내용을 저장하고, 열었던 파일은 보드에 작은 카드로 남긴다.
    func closeStudio() {
        studioState.save()
        if let f = studioState.selected, studioState.kind != "Documents",
           !model.selectedWorkspace.nodes.contains(where: { $0.kind == .file && $0.text == f.path }) {
            collapseStudio {
                addNode(kind: .file, size: CGSize(width: 380, height: 240), title: f.lastPathComponent) { $0.text = f.path }
            }
            return
        }
        studioState.kind = nil
    }

    func studioInsert() {
        guard let f = studioState.selected else { return }
        studioState.save()
        collapseStudio {
            addNode(kind: .file, size: CGSize(width: 560, height: 420), title: f.lastPathComponent) { $0.text = f.path }
        }
    }

    /// 스튜디오 패널(여백을 뺀 자리, StudioOverlay 의 padding 과 같다)을 창 내용 좌표로.
    private func studioPanelRect(_ host: NSView) -> NSRect {
        let b = host.bounds
        let r = NSRect(x: 84, y: 58, width: max(40, b.width - 160), height: max(40, b.height - 150))
        return host.convert(host.isFlipped ? r : NSRect(x: r.minX, y: b.height - r.maxY, width: r.width, height: r.height), to: host.superview)
    }

    /// 스튜디오가 새로 생긴 카드 자리로 줄어들며 닫히는 움직임(원본 studio-documents 19초, 약 0.25초).
    /// 패널을 찍어 둔 그림을 카드 자리로 옮기고, 다 옮기면 카드를 보인다. add 는 카드를 만든다.
    private func collapseStudio(_ add: () -> Void) {
        let before = Set(model.selectedWorkspace.nodes.map(\.id))
        var ghost: NSImageView?
        if let host = studioHostView, !host.isHidden {
            let panel = studioPanelRect(host)
            let local = host.convert(panel, from: host.superview)
            if let rep = host.bitmapImageRepForCachingDisplay(in: local) {
                host.cacheDisplay(in: local, to: rep)
                let img = NSImage(size: local.size)
                img.addRepresentation(rep)
                let g = NSImageView(frame: panel)
                g.image = img
                g.imageScaling = .scaleAxesIndependently
                g.wantsLayer = true
                g.layer?.cornerRadius = 14
                g.layer?.masksToBounds = true
                host.superview?.addSubview(g, positioned: .above, relativeTo: host)
                ghost = g
            }
        }
        add()
        studioState.kind = nil
        guard let g = ghost else { return }
        let newID = model.selectedWorkspace.nodes.map(\.id).first { !before.contains($0) }
        // 카드 뷰가 생기고 화면이 카드 쪽으로 옮겨진 다음 자리를 잰다.
        DispatchQueue.main.async { [weak self] in
            guard let self, let id = newID, let v = self.currentCanvas?.nodeViews[id] else {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.15; g.animator().alphaValue = 0 } completionHandler: { g.removeFromSuperview() }
                return
            }
            v.layer?.removeAnimation(forKey: "symAppear")
            v.alphaValue = 0
            let target = v.convert(v.bounds, to: g.superview)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1)
                g.animator().frame = target
                g.animator().alphaValue = 0.6
            } completionHandler: {
                MainActor.assumeIsolated {
                    v.alphaValue = 1
                    NSAnimationContext.runAnimationGroup { $0.duration = 0.08; g.animator().alphaValue = 0 } completionHandler: { g.removeFromSuperview() }
                }
            }
        }
    }

    func studioAddToBoard() { studioInsert() }

    /// 문서 스튜디오의 "보드로 보내기": DOCUMENT 카드.
    func placeDocumentCard(_ id: String) {
        let url = docStudio.url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let agent = docStudio.agent
        collapseStudio {
            addNode(kind: .document, size: CGSize(width: 520, height: 620), title: "Document") { $0.text = url.path; $0.role = agent }
        }
    }

    func studioExportDocPDF(_ id: String) {
        let md = docStudio.url(for: id)
        guard let w = window, FileManager.default.fileExists(atPath: md.path) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (Markdown.firstHeading((try? String(contentsOf: md, encoding: .utf8)) ?? "") ?? id) + ".pdf"
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let out = panel.url else { return }
            self?.exportPDF(markdown: md, to: out)
        }
    }

    func studioAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard let w = window else { return }
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let u = panel.url, let self, !self.studioState.extraRoots.contains(u) else { return }
            self.studioState.extraRoots.append(u)
        }
    }

    /// 마크다운을 PDF 로. 저장 위치는 macOS 저장 시트로 고른다.
    func studioExportPDF() {
        guard let md = studioState.selected, let w = window else { return }
        studioState.save()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = md.deletingPathExtension().lastPathComponent + ".pdf"
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let out = panel.url, let self else { return }
            self.exportPDF(markdown: md, to: out)
        }
    }

    /// 보드 위 마크다운 카드의 PDF 단추. 저장 위치는 저장 시트로.
    func exportCardPDF(_ md: URL) {
        guard let w = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = md.deletingPathExtension().lastPathComponent + ".pdf"
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let out = panel.url, let self else { return }
            self.exportPDF(markdown: md, to: out)
        }
    }

    private var pdfExporter: StudioModel?
    func exportPDF(markdown md: URL, to out: URL) {
        let m = StudioModel(root: md.deletingLastPathComponent())
        pdfExporter = m
        chrome.flash(L("Exporting PDF..."))
        m.exportPDF(from: md, to: out) { [weak self] ok in
            self?.chrome.flash(ok ? L("Saved %@", out.lastPathComponent) : L("PDF export failed"))
            self?.pdfExporter = nil
        }
    }


    func openDiagram() { diagrams.open.toggle() }

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

    func openUsage() { chrome.usageOpen.toggle() }
    func openProfiles() { chrome.accountsOpen.toggle() }

    /// 프로필(없으면 기본 로그인)로 콘솔을 하나 띄운다.
    func openProfileConsole(_ p: AccountProfile?, agent: AgentKind) {
        chrome.accountsOpen = false
        var spec = TerminalSpec(agent: agent, cwd: projectPath, profileID: p?.id)
        spec.profileID = p?.id
        addTerminal(spec: spec, at: nil, applyActiveProfile: false)
    }
    // MARK: 전체 화면 프롬프트 편집(Cmd+Shift+E)

    /// 명령 바를 편집 대상으로 하는 틀.
    var commandBarPromptTarget: PromptEditorModel.Target {
        PromptEditorModel.Target(
            title: { [weak self] in self?.commandBarTitle ?? "" },
            read: { [weak self] in self?.chrome.command ?? "" },
            write: { [weak self] in self?.chrome.command = $0 },
            send: { [weak self] in self?.runCommand() },
            options: { [weak self] in self?.mentionOptions() ?? [] })
    }

    /// 편집 창 위에 보이는 대상: 명령 바 자리표시와 같은 말.
    var commandBarTitle: String {
        if let id = currentCanvas?.selectedNodeID, let n = model.node(id), n.kind == .terminal { return L("Message %@ · @ to direct", n.title) }
        return L("Command the board · @ to direct")
    }

    func togglePromptEditor() {
        if promptEditor.open { promptEditor.close(); return }
        let field = MentionTextField.focused(window?.firstResponder)
        promptOrigin = field
        if let f = field, let expand = f.onExpand { expand() }
        else { promptOrigin = nil; promptEditor.show(commandBarPromptTarget) }
    }

    /// 닫히면 원래 입력칸(없으면 명령 바)에 초점을 돌려 이어서 쓸 수 있게 한다.
    private func promptEditorClosed() {
        if let f = promptOrigin, f.window != nil { f.focusAtEnd() } else { chrome.focusCommand += 1 }
        promptOrigin = nil
    }

    /// 맨 위에 열린 모달 하나를 닫는다. 닫은 게 있으면 true.
    @discardableResult
    func closeTopOverlay() -> Bool {
        if chrome.gitOpen { chrome.gitOpen = false }
        else if chrome.loopsPage != nil { chrome.loopsPage = nil }
        else if memoryHub.page != nil, memoryHub.page != "scan" { memoryHub.page = nil }
        else if studioState.kind != nil { closeStudio() }
        else if chrome.missionOpen { chrome.missionOpen = false }
        else { return false }
        // 사라진 모달 안 입력란에 초점이 남지 않게 보드로 돌린다.
        window?.makeFirstResponder(currentCanvas)
        return true
    }

    func openLoops() { chrome.loopsPage = chrome.loopsPage == nil ? "list" : nil }
    func openMemory() { memoryHub.page = memoryHub.page == nil ? "list" : nil }

    /// 메모리 카드를 보드에 놓는다(지금 레포 메모).
    func placeMemoryCard() {
        memoryHub.page = nil
        addNode(kind: .memory, size: CGSize(width: 360, height: 300), title: "Memory") { $0.text = self.memoryHub.repo }
    }
    func openMission() { chrome.missionOpen.toggle() }

    /// 그룹 프레임 전체가 보이게 맞춘다.
    func zoomToTeam(_ id: UUID) {
        let ms = model.selectedWorkspace.nodes.filter { $0.teamID == id }
        guard !ms.isEmpty else { return }
        let minX = ms.map(\.frame.x).min()!, minY = ms.map(\.frame.y).min()!
        let maxX = ms.map { $0.frame.x + $0.frame.w }.max()!, maxY = ms.map { $0.frame.y + $0.frame.h }.max()!
        let size = scrollView.frame.size
        let zoom = min((size.width - 200) / (maxX - minX + 80), (size.height - 240) / (maxY - minY + 80), 1.2)
        scrollView.center(on: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2), zoom: zoom)
    }
    func openSettings() { SettingsWindowController.shared.show(over: window) }

    /// 놓기 도구로 캔버스를 눌렀을 때.
    /// 막대들에 가리지 않는 보드 영역(캔버스 좌표). 위 70, 왼쪽·오른쪽 80, 아래 110 포인트를 뺀다.
    var safeCanvasRect: Rect {
        let b = scrollView.contentView.bounds, mag = max(scrollView.magnification, 0.01)
        let top = 70 / mag, side = 80 / mag, bottom = 110 / mag
        let r = NSRect(x: b.minX + side, y: b.minY + top, width: max(1, b.width - side * 2), height: max(1, b.height - top - bottom))
        return CanvasGeometry.modelRect(r)
    }

    /// 놓는 자리가 가장자리면 막대 밑으로 들어가지 않게 보이는 영역 안으로 옮긴다. 너무 크면 들어오게 축소한다.
    private func visiblePlacement(_ frame: Rect) -> Rect {
        let safe = safeCanvasRect
        let fitted = CanvasLayout.fit(frame, in: safe)
        if frame.w > safe.w || frame.h > safe.h {
            let mag = scrollView.magnification
            let z = mag * min(safe.w / (frame.w + 40), safe.h / (frame.h + 40))
            scrollView.center(on: Point(x: fitted.x + frame.w / 2, y: fitted.y + frame.h / 2), zoom: z)
            return CanvasLayout.fit(frame, in: safeCanvasRect)
        }
        return fitted
    }

    /// 앱이 만든 노드가 막대 밑이나 화면 밖에 있으면 보이게 화면을 옮긴다(노드 자리는 그대로).
    /// 보이는 영역은 막대를 뺀 safeCanvasRect 이고, 그 영역의 가운데가 화면 가운데보다 (아래 110 − 위 70)/2 만큼 위에 있다.
    func reveal(_ frames: [Rect]) {
        let mag = Double(scrollView.magnification)
        guard let r = CanvasLayout.reveal(frames, in: safeCanvasRect, magnification: mag) else { return }
        let z = max(r.zoom, Double(scrollView.minMagnification))
        scrollView.center(on: Point(x: r.center.x, y: r.center.y + 20 / z), zoom: z)
    }

    /// 오케스트레이터를 고른 노드 바로 아래(없으면 화면 가운데)에 놓는다.
    func addOrchestratorNearSelection() {
        var at = scrollView.visibleCenter
        var console: UUID?
        if let id = currentCanvas?.selectedNodeID, let n = model.node(id) {
            at = Point(x: n.frame.x + n.frame.w / 2, y: n.frame.y + n.frame.h + 60)
            if n.kind == .terminal { console = id }
        }
        place(.orchestrator, at: at)
        // 원본처럼 고른 콘솔은 처음부터 연결해 둔다("1 agent").
        if let console, let orch = currentCanvas?.selectedNodeID, model.node(orch)?.kind == .orchestrator {
            toggleWire(orch, to: console)
        }
    }

    func place(_ p: Placement, at point: Point) {
        let s = p.size
        let isShape: Bool = { if case .shape = p { return true }; return false }()
        let raw = Rect(x: point.x - s.width / 2, y: isShape ? point.y - s.height / 2 : point.y - 20, w: s.width, h: s.height)
        var placed = visiblePlacement(raw)
        // 글·도형은 다른 것 위에 덧붙이는 용도라 그대로 둔다. 나머지는 그룹 프레임·노드와 겹치면 가장 가까운 빈 자리로 민다.
        if !isShape, !{ if case .text = p { return true }; return false }() {
            let ws = model.selectedWorkspace
            let free = CanvasLayout.nearestFree(placed, avoiding: CanvasLayout.obstacles(nodes: ws.nodes, teams: ws.teams))
            if free != placed { placed = free; reveal([free]) }
        }
        let origin = Point(x: placed.x, y: placed.y)
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
            addNode(kind: .sticky, size: s, title: "Note", at: origin) { $0.text = ""; $0.colorHex = "#C9A227" }
            // 원본처럼 놓자마자 글을 쓸 수 있게 편집 상태로.
            if let id = currentCanvas?.selectedNodeID {
                DispatchQueue.main.async { [weak self] in self?.currentCanvas?.nodeViews[id]?.setEditing(true) }
            }
        case .checklist:
            addNode(kind: .checklist, size: s, title: "Checklist", at: origin) { $0.checklist = [] }
        case .kanban:
            addNode(kind: .kanban, size: s, title: "Board", at: origin) {
                $0.kanban = ["Backlog", "To Do", "In Progress", "Done"].map { KanbanColumn(title: $0) }
            }
        case .web:
            addNode(kind: .web, size: s, title: "Web", at: origin) { $0.text = ""; $0.tabs = [""] }
        case .orchestrator:
            addNode(kind: .orchestrator, size: s, title: "Orchestrator", at: origin)
        case .calendar:
            addNode(kind: .calendar, size: s, title: "Calendar", at: origin) { $0.events = [] }
        case .shape(let k):
            addNode(kind: .shape, size: s, title: k.capitalized, at: origin) {
                $0.shape = ShapeSpec(kind: k)
                $0.style = NodeStyle(fontSize: 20, font: "hand", align: "center")
                $0.text = ""
            }
        }
        setTool(.select)
    }

    /// 웹 도구로 끌어 그린 사각형 자리에 그 크기로 웹 타일을 놓는다(원본 node-webtiles). 직접 그린 자리라 밀지 않는다.
    func placeWeb(in r: Rect) {
        addNode(kind: .web, size: CGSize(width: r.w, height: r.h), title: "Web", at: Point(x: r.x, y: r.y)) { $0.text = ""; $0.tabs = [""] }
        setTool(.select)
    }

    /// 선택한 노드를 옆에 하나 더 만든다. 터미널은 같은 CLI 로 새 세션.
    func duplicateSelection() {
        guard let id = currentCanvas?.selectedNodeID, let n = model.node(id) else {
            chrome.flash(L("Select something to duplicate")); return
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
        reveal([copy.frame])
    }

    /// 토스트의 Yes/No: 기다리는 콘솔을 모두 차례로 띄운다. Yes 면 끝난 뒤 전체가 보이게 줄인다.
    func answerResumeAll(_ yes: Bool) {
        let ids = Array(model.sessions.pendingResume)
        // 지금 작업공간 것부터 화면 순서(위→아래, 왼→오른)로.
        let order = model.selectedWorkspace.nodes.map(\.id)
        let sorted = ids.sorted { (order.firstIndex(of: $0) ?? Int.max) < (order.firstIndex(of: $1) ?? Int.max) }
        chrome.resumeCount = 0
        model.sessions.answerResume(sorted, resume: yes) { [weak self] in
            guard yes else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.zoomToFit(nil) }
        }
    }

    /// 오케스트레이터에 연결된 콘솔(그룹 멤버 포함).
    func orchestratorTargets(_ orch: UUID) -> [BoardNode] {
        guard let wsID = model.workspaceID(containing: orch), let ws = model.workspace(wsID) else { return [] }
        let to = Set((ws.links ?? []).filter { $0.from == orch }.map(\.to))
        return ws.nodes.filter { $0.kind == .terminal && (to.contains($0.id) || ($0.teamID.map(to.contains) ?? false)) }
    }

    /// 입력칸 @ 목록: 살아 있는 콘솔 → all → 그룹(소문자 이름, 보드 명령과 같은 꼴).
    /// 오케스트레이터 입력칸이면 그 오케스트레이터에 연결된 콘솔만(보낼 수 있는 대상만) 보인다.
    func mentionOptions(orchestrator: UUID? = nil) -> [MentionOption] {
        let ws = orchestrator.flatMap { model.workspaceID(containing: $0) }.flatMap { model.workspace($0) } ?? model.selectedWorkspace
        let pool = orchestrator.map { orchestratorTargets($0) } ?? ws.nodes.filter { $0.kind == .terminal }
        let live = pool.filter { model.sessions.status(of: $0.id) != .exited }
        var out: [MentionOption] = []
        var seen = Set<String>()
        func add(_ o: MentionOption) { if seen.insert(o.id).inserted { out.append(o) } }
        for n in live {
            add(MentionOption(name: n.title, kind: .console(AgentCatalog.choice(for: n.terminal), model.sessions.status(of: n.id) ?? .starting)))
        }
        guard !live.isEmpty else { return [] }
        add(MentionOption(name: "all", kind: .all(live.count)))
        for t in ws.teams {
            let k = live.filter { $0.teamID == t.id }.count
            if k > 0 { add(MentionOption(name: t.name.lowercased(), kind: .group(count: k, colorHex: t.colorHex))) }
        }
        return out
    }

    /// 연결된 콘솔 전부에, 또는 앞에 쓴 @이름 대상에만 보낸다. 보낸 수를 돌려준다.
    @discardableResult
    func orchestratorSend(_ orch: UUID, text: String) -> Int {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = orchestratorTargets(orch)
        let ws = model.selectedWorkspace
        let cands = targets.map { n in CommandTargets.Candidate(id: n.id, name: n.title, team: n.teamID.flatMap { id in ws.teams.first { $0.id == id }?.name }) }
        if let split = CommandTargets.split(text, candidates: cands) {
            let n = deliver(split, said: text)
            if n > 0 { chrome.flash(Ln(n, "Sent to %d agent", "Sent to %d agents")) }
            return n
        }
        let parsed = CommandTargets.parse(text, candidates: cands)
        let ids = parsed.implicit ? targets.map(\.id) : parsed.nodeIDs
        guard !parsed.body.isEmpty, !ids.isEmpty else { return 0 }
        for id in ids { model.sessions.session(for: id)?.sendText(parsed.body, submit: true) }
        chrome.flash(Ln(ids.count, "Sent to %d agent", "Sent to %d agents"))
        return ids.count
    }

    /// @대상별로 나눈 글을 보낸다. 보내기 직전 THREAD 에 대상마다 무엇이 갔는지, 글 없는 대상은 보내지 않았다고 남긴다.
    /// 여러 대상이거나 빠진 대상이 있으면 THREAD 를 연다. 보낸 콘솔 수(겹치면 한 번)를 돌려준다.
    func deliver(_ split: CommandTargets.Split, said: String) -> Int {
        let multi = split.deliveries.count > 1 || !split.missingBody.isEmpty
        chrome.thread.add(.user, said)
        for name in split.missingBody { chrome.thread.add(.result, "Nothing to send to \(name) · not sent") }
        var sent = Set<UUID>()
        for d in split.deliveries {
            let titles = d.nodeIDs.compactMap { model.node($0)?.title }
            let preview = d.body.count > 80 ? String(d.body.prefix(80)) + "…" : d.body
            chrome.thread.add(.result, "→ \(titles.isEmpty ? d.names.joined(separator: ", ") : titles.joined(separator: ", ")): \(preview.replacingOccurrences(of: "\n", with: " ⏎ "))")
            for id in d.nodeIDs {
                model.sessions.session(for: id)?.sendText(d.body, submit: true)
                sent.insert(id)
            }
        }
        if multi { chrome.threadOpen = true }
        return sent.count
    }

    /// 오케스트레이터 Connect/Done.
    func toggleConnect(_ orch: UUID) {
        chrome.connectingOrchestrator = chrome.connectingOrchestrator == orch ? nil : orch
        if chrome.connectingOrchestrator != nil { chrome.flash(L("Click consoles or a group's pill to wire them · Done when finished")) }
        currentCanvas?.layoutGroups()
    }

    /// 오케스트레이터와 그룹·콘솔 사이 연결을 켜거나 끈다.
    func toggleWire(_ orch: UUID, to target: UUID) {
        guard let wsID = model.workspaceID(containing: orch) else { return }
        model.mutateWorkspace(wsID) { ws in
            var links = ws.links ?? []
            if let i = links.firstIndex(where: { $0.from == orch && $0.to == target }) { links.remove(at: i) }
            else { links.append(NodeLink(from: orch, to: target)) }
            ws.links = links
        }
        currentCanvas?.layoutGroups()
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
    func closeNodes(_ ids: [UUID], inThread: Bool = false) {
        let nodes = ids.compactMap { model.node($0) }
        guard !nodes.isEmpty else { return }
        if nodes.count > 1 {
            let names = nodes.map(\.title)
            let shown = names.prefix(5).joined(separator: ", ") + (names.count > 5 ? " +\(names.count - 5)" : "")
            let message = "\(shown): about to close \(nodes.count) consoles"
            if inThread { chrome.thread.add(.result, message + ", confirm below") }
            chrome.confirm = PendingConfirm(message: message, button: inThread ? "Confirm · \(nodes.count)" : "Close \(nodes.count)", action: { [weak self] in
                self?.removeNodes(nodes.map(\.id))
                if inThread { self?.chrome.thread.add(.result, "Closed \(nodes.count) consoles") }
            }, inThread: inThread, onCancel: inThread ? { [weak self] in self?.chrome.thread.add(.result, "Cancelled, nothing was closed") } : nil)
            return
        }
        removeNodes(nodes.map(\.id))
        if inThread { chrome.thread.add(.result, "Closed \(nodes[0].title)") }
    }

    func removeNodes(_ ids: [UUID]) {
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
        let closing = text.hasPrefix("/close") && !text.lowercased().contains("group")
        // 보드 명령(원본 음성 명령을 글로): @대상으로 시작하지 않고 보드 명령 꼴이면 고른 콘솔이 있어도 보드에 적용한다.
        // 그런 글을 콘솔에 그대로 보내려면 "@이름 spawn …" 처럼 대상을 적는다(DECISIONS).
        if !closing, !text.hasPrefix("@"), let cmd = BoardCommand.parse(text) {
            chrome.command = ""
            runBoardCommand(cmd, said: text)
            return
        }
        if closing { text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) + " _" }
        let ws = model.selectedWorkspace
        let cands = ws.nodes.filter { $0.kind == .terminal }.map { n in
            CommandTargets.Candidate(id: n.id, name: n.title, team: n.teamID.flatMap { t in ws.teams.first { $0.id == t }?.name })
        }
        // @대상마다 다른 글(8차 5번).
        if !closing, let split = CommandTargets.split(text, candidates: cands) {
            let n = deliver(split, said: text)
            if n > 0 || !split.missingBody.isEmpty { chrome.command = "" }
            if n > 0 { chrome.flash(Ln(n, "Sent to %d console", "Sent to %d consoles")) }
            else if split.missingBody.isEmpty { chrome.flash(L("Type something to send")) }
            return
        }
        let parsed = CommandTargets.parse(text, candidates: cands)
        var targets = parsed.nodeIDs
        if parsed.implicit, let sel = currentCanvas?.selectedNodeID, model.node(sel)?.kind == .terminal { targets = [sel] }
        if !parsed.unknown.isEmpty { chrome.flash(L("No console named @%@", parsed.unknown[0])); return }
        if closing {
            chrome.command = ""
            closeNodes(targets)
            return
        }
        guard !targets.isEmpty, !parsed.body.isEmpty else {
            chrome.flash(L(parsed.body.isEmpty ? "Type something to send" : "Select a console or start with @name"))
            return
        }
        for id in targets { model.sessions.session(for: id)?.sendText(parsed.body, submit: true) }
        chrome.command = ""
        chrome.flash(Ln(targets.count, "Sent to %d console", "Sent to %d consoles"))
    }

    /// 명령 바의 보드 명령을 실행하고, 친 글·계획·결과를 THREAD 패널에 쌓는다.
    func runBoardCommand(_ cmd: BoardCommand, said: String? = nil) {
        let ws = model.selectedWorkspace
        let groups = ws.teams.filter { t in ws.nodes.contains { $0.teamID == t.id } }
        chrome.thread.add(.user, said ?? cmd.plan)
        chrome.thread.add(.plan, cmd.plan)
        chrome.threadOpen = true
        func say(_ s: String) { chrome.thread.add(.result, s) }
        switch cmd {
        case .spawn(let count, let agent):
            guard let choice = AgentCatalog.choice(id: agent), AgentCatalog.shared.installed.contains(choice.id) else {
                say("\(agent) is not installed on this Mac"); return
            }
            let name = "Group \(groups.count + 1)"
            _ = launchTeam(spec: choice.spec(cwd: projectPath), count: count, teamName: name, roles: [])
            say("Spawned \(count) \(choice.name) console\(count == 1 ? "" : "s") · \(name)")
        case .orchestrator(let g):
            guard let i = BoardCommand.matchGroup(g, in: groups.map(\.name)) else { say("No group named \(g)"); return }
            let n = addOrchestrator(for: groups[i])
            say("Orchestrator added for \(groups[i].name), wired to \(n) consoles")
        case .preset(let key):
            let all = ComposerPreset.all
            let pick = Int(key).flatMap { $0 >= 1 && $0 <= all.count ? all[$0 - 1] : nil }
                ?? all.first { $0.name.lowercased().contains(key.lowercased()) }
            guard let p = pick else { say("No preset \(key)"); return }
            spawnPreset(p)
            say("Deployed the \(p.name) preset")
        case .closeGroup(let g):
            guard let i = BoardCommand.matchGroup(g, in: groups.map(\.name)) else { say("No group named \(g)"); return }
            closeNodes(ws.nodes.filter { $0.teamID == groups[i].id }.map(\.id), inThread: true)
        }
    }

    /// 앱이 정한 자리가 그룹·노드와 겹치면 가장 가까운 빈 자리로(1번 규칙).
    func freePoint(_ r: Rect) -> Point {
        let ws = model.selectedWorkspace
        let f = CanvasLayout.nearestFree(r, avoiding: CanvasLayout.obstacles(nodes: ws.nodes, teams: ws.teams))
        return Point(x: f.x, y: f.y)
    }

    /// 그룹 왼쪽에 오케스트레이터를 놓고 그 그룹에 잇는다. 이은 콘솔 수를 돌려준다.
    @discardableResult
    func addOrchestrator(for team: Team) -> Int {
        let members = model.selectedWorkspace.nodes.filter { $0.teamID == team.id }
        let minX = members.map(\.frame.x).min() ?? 0, minY = members.map(\.frame.y).min() ?? 0
        let size = Placement.orchestrator.size
        let at = freePoint(Rect(x: minX - size.width - 120, y: minY, w: size.width, h: size.height))
        addNode(kind: .orchestrator, size: size, title: "Orchestrator", at: at)
        if let orch = currentCanvas?.selectedNodeID { toggleWire(orch, to: team.id) }
        reveal(([model.selectedWorkspace.nodes.last?.frame].compactMap { $0 }) + members.map(\.frame))
        return members.count
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
        let team = launchTeam(specs: specs, teamName: p.name, roles: [])
        // 원본 프리셋처럼 콘솔 말고 다른 노드도 함께 놓는다.
        for extra in p.extras {
            switch extra {
            case .orchestrator:
                addOrchestrator(for: team)
            case .checklist(let items):
                let members = model.selectedWorkspace.nodes.filter { $0.teamID == team.id }
                let maxX = members.map { $0.frame.x + $0.frame.w }.max() ?? 0, minY = members.map(\.frame.y).min() ?? 0
                let size = Placement.checklist.size
                addNode(kind: .checklist, size: size, title: "Checklist", at: freePoint(Rect(x: maxX + 80, y: minY, w: size.width, h: size.height))) {
                    $0.checklist = items.map { ChecklistItem(text: $0) }
                }
            }
        }
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
                     title: String? = nil, teamID: UUID? = nil, role: String? = nil, applyActiveProfile: Bool = true,
                     near: UUID? = nil) -> BoardNode {
        var spec = spec
        // 새 콘솔은 그 CLI 에 고른 계정 프로필을 따른다.
        if applyActiveProfile, spec.profileID == nil, spec.agent == .claude || spec.agent == .codex {
            spec.profileID = model.profiles.active(for: spec.agent)
        }
        let frame: Rect
        if let point { frame = Rect(x: point.x, y: point.y, w: size.width, h: size.height) }
        else { frame = besideFrame(w: size.width, h: size.height, near: near) }
        let name = title ?? nextName()
        let node = BoardNode(kind: .terminal, frame: frame, title: name, terminal: spec, teamID: teamID, role: role)
        model.addNode(node)
        currentCanvas?.select(node.id)
        if point == nil { glideReveal([frame], zoomIn: true) }
        return node
    }

    /// 자리를 정하지 않은 새 콘솔(묶음)의 자리: 기준 노드(near → 고른 노드 → 마지막 노드) 옆 빈 칸. 보드가 비었으면 화면 가운데.
    func besideFrame(w: Double, h: Double, near: UUID? = nil) -> Rect {
        let ws = model.selectedWorkspace
        let refID = near ?? currentCanvas?.selectedNodeID
        var ref = refID.flatMap { id in ws.nodes.first { $0.id == id } }
        if ref.map({ NodeView.isHeaderless($0.kind) }) ?? false { ref = nil }
        var refRect = ref?.frame ?? ws.nodes.last(where: { !NodeView.isHeaderless($0.kind) })?.frame
        // 기준이 그룹에 들었으면 그룹 프레임 전체를 기준으로(그룹 안에 끼어들지 않게).
        let obstacles = CanvasLayout.obstacles(nodes: ws.nodes, teams: ws.teams)
        if let r = refRect, let box = obstacles.first(where: { $0.x <= r.x && $0.y <= r.y && $0.x + $0.w >= r.x + r.w && $0.y + $0.h >= r.y + r.h }) {
            refRect = box
        }
        if let slot = CanvasLayout.besideSlot(w: w, h: h, reference: refRect, obstacles: obstacles) { return slot }
        return model.suggestedFrame(size: CGSize(width: w, height: h), near: scrollView.visibleCenter)
    }

    /// 새로 놓은 노드로 화면을 부드럽게 옮긴다. 배율은 그대로 두되, 화면보다 크면 들어오게 줄인다.
    /// zoomIn: 새 콘솔처럼 바로 쓸 노드면 실제 크기(1배)까지 확대하며 간다. 이미 그보다 크면 그대로, 화면을 넘지는 않는다.
    func glideReveal(_ frames: [Rect], zoomIn: Bool = false, duration: TimeInterval = 0.35) {
        guard let first = frames.first else { return }
        var minX = first.x, minY = first.y, maxX = first.x + first.w, maxY = first.y + first.h
        for f in frames.dropFirst() { minX = min(minX, f.x); minY = min(minY, f.y); maxX = max(maxX, f.x + f.w); maxY = max(maxY, f.y + f.h) }
        let safe = safeCanvasRect, mag = Double(scrollView.magnification)
        let fit = min(safe.w / (maxX - minX + 80), safe.h / (maxY - minY + 80))
        let z = max(Double(scrollView.minMagnification), zoomIn ? min(mag * fit, max(mag, 1)) : mag * min(1, fit))
        // 보이는 영역(막대를 뺀 곳)의 가운데는 화면 가운데보다 20pt 위다(reveal 과 같은 보정).
        scrollView.glide(to: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2 + 20 / z), zoom: z, duration: duration)
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
        else {
            // 자리를 정해 주지 않은 카드(스튜디오 Add to Board·문서·메모리)도 1번 규칙으로 겹치지 않게.
            let ws = model.selectedWorkspace
            frame = CanvasLayout.nearestFree(frame, avoiding: CanvasLayout.obstacles(nodes: ws.nodes, teams: ws.teams))
        }
        var node = BoardNode(kind: kind, frame: frame, title: title)
        configure(&node)
        model.addNode(node)
        currentCanvas?.select(node.id)
        // 자리를 정해 주지 않은 노드(문서·메모리·파일 카드)는 놓인 자리가 보이게 한다.
        // 자리를 정한 쪽(놓기·다이어그램·인스펙터)은 부른 곳에서 알아서 보이게 한다.
        if point == nil { reveal([node.frame]) }
    }

    /// 위쪽 막대 언어 단추(10차): 한국어 ↔ English.
    @objc func toggleLanguage() {
        let next: LanguageMode = L10n.current == .ko ? .en : .ko
        UIPrefs.setLanguage(next, Prefs.shared)
        L10n.apply(next)
    }

    /// 새 루프 양식을 연다. nodeID 가 있으면 그 콘솔만 고른 상태로.
    func newLoop(for nodeID: UUID?) {
        loopDraft.reset()
        if let nodeID { loopDraft.targetAll = false; loopDraft.picked = [nodeID] }
        chrome.loopsPage = "gallery"
    }

    /// 루프 양식의 Create/Save.
    func saveLoop() {
        guard loopDraft.isValid else { return }
        let consoles = model.selectedWorkspace.nodes.filter { $0.kind == .terminal }
        let rule = loopDraft.rule(fallbackNode: consoles.first?.id ?? UUID())
        if loopDraft.editing != nil { model.loops.replace(rule) } else { model.loops.add(rule, to: model.selectedWorkspace.id) }
        loopDraft.reset()
        chrome.loopsPage = "list"
    }

    /// 스튜디오 패널 호스트(닫히는 움직임에서 찍어 둔다).
    private weak var studioHostView: NSView?

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
        if !composer.open { composer.reset(default: AgentCatalog.shared.lastChoiceID) }
        composer.open.toggle()
    }

    /// 아래 막대 Group 단추 자리. 컴포저 팝오버가 여기에 붙는다.
    weak var composerAnchor: NSView?
    private var composerPopover: NSPopover?
    private var composerObserver: Any?
    private var overlayObserver: Any?

    private func updateOverlayFlag() {
        let c = chrome
        let open = c.spawnMenuOpen || c.insertOpen || c.shapeOpen || c.gitOpen || c.usageOpen || c.accountsOpen
            || c.missionOpen || c.loopsPage != nil || composer.open || studioState.kind != nil || memoryHub.page != nil
            || diagrams.open || c.panelOpen
        if c.overlayOpen != open { c.overlayOpen = open }
    }

    /// 컴포저 카드는 AppKit 팝오버로 띄운다. SwiftUI 팝오버는 타일 줄이 늘 때 위쪽을 고정한 채 아래로 자라
    /// 아래 단추 줄과 명령 입력을 가렸다. AppKit 팝오버는 단추 쪽(아래)을 고정하고 위로 자란다.
    private func syncComposerPopover(_ open: Bool) {
        if !open {
            composerPopover?.close()
            return
        }
        guard composerPopover?.isShown != true, let anchor = composerAnchor, anchor.window != nil else { return }
        let host = NSHostingController(rootView: ComposerCard(state: composer) { [weak self] in self?.spawnComposer() }
            .localized())
        host.sizingOptions = [.preferredContentSize]
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = false
        pop.contentViewController = host
        pop.delegate = self
        composerPopover = pop
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === composerPopover else { return }
        composerPopover = nil
        if composer.open { composer.open = false }
    }

    /// 컴포저 카드의 Spawn N: 역할 색 그룹 프레임을 만들고 노드를 차례로 띄운다.
    func spawnComposer() {
        let specs = composer.tiles.map { (AgentCatalog.choice(id: $0) ?? AgentCatalog.shared.lastChoice).spec(cwd: projectPath) }
        let name = composer.teamName.trimmingCharacters(in: .whitespaces).isEmpty ? composer.role.name : composer.teamName
        composer.open = false
        launchTeam(specs: specs, teamName: name, roles: [], colorHex: composer.role.colorHex, stagger: true)
    }

    /// 노드 여러 개를 격자로 띄우고 새 팀으로 묶는다.
    @discardableResult
    func launchTeam(spec: TerminalSpec, count: Int, teamName: String, roles: [String?]) -> Team {
        launchTeam(specs: Array(repeating: spec, count: count), teamName: teamName, roles: roles)
    }

    @discardableResult
    func launchTeam(specs: [TerminalSpec], teamName: String, roles: [String?], colorHex: String? = nil, stagger: Bool = false) -> Team {
        let wsID = model.selectedWorkspace.id
        let color = colorHex ?? Composer.teamColors[model.selectedWorkspace.teams.count % Composer.teamColors.count]
        let team = Team(name: teamName, colorHex: color)
        model.mutateWorkspace(wsID) { $0.teams.append(team) }
        let frames = Composer.frames(count: specs.count, center: stagger ? freeSpotCenter(count: specs.count) : teamSlotCenter(count: specs.count),
                                     size: (w: 520, h: 330))
        for (i, f) in frames.enumerated() {
            let role = i < roles.count ? roles[i] : nil
            let add = { [weak self] in
                guard let self else { return }
                self.addTerminal(spec: specs[i], at: Point(x: f.x, y: f.y), size: CGSize(width: f.w, height: f.h),
                                 teamID: team.id, role: role)
                if i == frames.count - 1, !stagger { self.glideReveal(frames) }
            }
            if stagger && i > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i), execute: add) } else { add() }
        }
        if stagger { zoomToFitFrames(frames) }
        return team
    }

    /// Spawn N·spawn 명령의 묶음 자리: 기존 노드 옆 빈 칸(그룹 프레임 여백·머리 포함 크기로). 보드가 비었으면 화면 가운데.
    private func teamSlotCenter(count: Int) -> Point {
        let cols = Double(Int(ceil(Double(count).squareRoot())))
        let rows = ceil(Double(count) / cols)
        let innerW = cols * 544 - 24, innerH = rows * 354 - 24
        let pad = 14.0, head = 30.0
        let slot = besideFrame(w: innerW + pad * 2, h: innerH + pad * 2 + head)
        return Point(x: slot.x + pad + innerW / 2, y: slot.y + pad + head + innerH / 2)
    }

    /// 새 묶음을 놓을 자리: 화면 가운데가 비어 있으면 거기, 아니면 기존 노드 오른쪽.
    private func freeSpotCenter(count: Int) -> Point {
        let c = scrollView.visibleCenter
        let nodes = model.selectedWorkspace.nodes
        let cols = Double(Int(ceil(Double(count).squareRoot())))
        let w = cols * 544, h = ceil(Double(count) / cols) * 354
        let probe = NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        if !nodes.contains(where: { CanvasGeometry.viewRect($0.frame).offsetBy(dx: -CanvasGeometry.origin, dy: -CanvasGeometry.origin).intersects(probe) }) { return c }
        let maxX = nodes.map { $0.frame.x + $0.frame.w }.max() ?? 0
        let minY = nodes.map(\.frame.y).min() ?? 0
        return Point(x: maxX + 120 + w / 2, y: minY + h / 2)
    }

    private func zoomToFitFrames(_ frames: [Rect]) {
        let existing = model.selectedWorkspace.nodes.map(\.frame)
        let all = existing + frames
        guard !all.isEmpty else { return }
        let minX = all.map(\.x).min()!, minY = all.map(\.y).min()!
        let maxX = all.map { $0.x + $0.w }.max()!, maxY = all.map { $0.y + $0.h }.max()!
        let size = scrollView.frame.size
        let zoom = min((size.width - 160) / (maxX - minX + 40), (size.height - 220) / (maxY - minY + 40), 1)
        scrollView.center(on: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2), zoom: zoom)
    }

    func addImageFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addImage(url: url, at: nil)
    }

    /// 주소 하나로 웹 타일을 보드에 놓는다(스튜디오의 바깥 링크).
    func openWebTile(_ address: String) {
        closeStudio()
        addNode(kind: .web, size: CGSize(width: 900, height: 620), title: "Web") { $0.text = address; $0.tabs = [address] }
    }

    /// 클립보드의 그림을 보드에 놓는다. 그림 파일이면 그 파일을, 그림 자체(스크린샷 복사 등)면 상태 폴더 images/ 에 PNG 로 저장해 쓴다.
    @discardableResult
    func pasteImage() -> Bool {
        let pb = NSPasteboard.general
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: ["public.image"]]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], let u = urls.first {
            addImage(url: u, at: nil)
            return true
        }
        guard let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            chrome.flash(L("No image on the clipboard"))
            return false
        }
        let dir = model.store.directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pasted-\(UUID().uuidString.prefix(8)).png")
        guard (try? png.write(to: url)) != nil else { chrome.flash(L("Could not save the pasted image")); return false }
        addImage(url: url, at: nil)
        return true
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
        reveal([frame])
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
    // MARK: 키보드로 콘솔 사이 옮겨 다니기(Ctrl+Tab · Cmd+1~9)

    /// 지금 작업공간 콘솔의 화면 위치 순서(위 → 아래, 왼 → 오른쪽).
    func consoleOrder() -> [UUID] {
        ConsoleOrder.order(model.selectedWorkspace.nodes.filter { $0.kind == .terminal }.map { (id: $0.id, frame: $0.frame) })
    }

    /// 콘솔을 고르고 키보드 입력을 바로 받게 한 뒤 화면을 그쪽으로 옮긴다.
    func focusConsole(_ id: UUID) {
        guard let n = model.node(id) else { return }
        currentCanvas?.select(id)
        if let t = model.sessions.session(for: id)?.view { window?.makeFirstResponder(t) }
        glideReveal([n.frame])
    }

    @objc func nextConsole(_ sender: Any?) { cycleConsole(forward: true) }
    @objc func previousConsole(_ sender: Any?) { cycleConsole(forward: false) }

    func cycleConsole(forward: Bool) {
        if let id = ConsoleOrder.step(from: currentCanvas?.selectedNodeID, in: consoleOrder(), forward: forward) { focusConsole(id) }
    }

    @objc func goToConsoleMenu(_ sender: NSMenuItem) { goToConsole(number: sender.tag) }

    func goToConsole(number: Int) {
        let ids = consoleOrder()
        guard number >= 1, number <= ids.count else { return }
        focusConsole(ids[number - 1])
    }

    /// Ctrl+Tab / Ctrl+Shift+Tab, Cmd+1~9, Cmd+Shift+1(Zoom to Fit). 키 코드로 봐서 한글 입력 상태에서도 같다.
    /// 그냥 Tab 은 건드리지 않는다(콘솔 안 프로그램의 자동완성).
    func handleConsoleNavigation(_ event: NSEvent) -> Bool {
        let f = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, f == .control || f == [.control, .shift] {
            cycleConsole(forward: !f.contains(.shift))
            return true
        }
        if let d = ConsoleOrder.digit(keyCode: event.keyCode) {
            if f == .command { goToConsole(number: d); return true }
            if f == [.command, .shift], d == 1 { zoomToFit(nil); return true }
        }
        return false
    }

    func showConsoleNumbers(_ show: Bool) {
        guard let canvas = currentCanvas else { return }
        let ids = consoleOrder()
        for (id, v) in canvas.nodeViews where v.header.isTerminal {
            let i = ids.firstIndex(of: id)
            v.header.setNumber(show && i != nil && i! < 9 ? i! + 1 : nil)
        }
    }

    @objc func zoomToFit(_ sender: Any?) {
        let nodes = model.selectedWorkspace.nodes
        guard !nodes.isEmpty else { scrollView.center(on: Point(x: 0, y: 0), zoom: 1); return }
        zoomToFit(frames: nodes.map(\.frame))
    }

    /// 주어진 사각형들만 담게 화면을 부드럽게 맞춘다.
    func zoomToFit(frames: [Rect]) {
        guard !frames.isEmpty else { return }
        let minX = frames.map(\.x).min()!, minY = frames.map(\.y).min()!
        let maxX = frames.map { $0.x + $0.w }.max()!, maxY = frames.map { $0.y + $0.h }.max()!
        let size = scrollView.frame.size
        let zoom = min((size.width - 160) / (maxX - minX + 40), (size.height - 220) / (maxY - minY + 40), 1)
        scrollView.glide(to: Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2 + 20 / max(zoom, 0.1)), zoom: zoom)
    }
}

/// 미션 맵 모달을 열렸을 때만 그린다.
struct MissionHost: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    var body: some View {
        if chrome.missionOpen { MissionMapView(model: model, beat: .shared, chrome: chrome, c: c) }
    }
}

struct LoopsHost: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var draft: LoopDraft
    let c: MainWindowController
    var body: some View {
        if chrome.loopsPage != nil { LoopsModal(model: model, runner: model.loops, chrome: chrome, draft: draft, c: c) }
    }
}

/// 숨겨져 있을 때 클릭을 가로채지 않는 호스팅 뷰.
final class HiddenAwareHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : super.hitTest(point) }
}

/// 아래 Presets 메뉴의 미리 정한 조합.
struct ComposerPreset: Identifiable {
    struct Part { var agentID: String; var count: Int }
    /// 콘솔 말고 함께 놓는 노드.
    enum Extra { case orchestrator, checklist([String]) }
    var id: String { name }
    var name: String
    var parts: [Part]
    var extras: [Extra] = []

    static let all: [ComposerPreset] = [
        ComposerPreset(name: "Pair: 2 Claude", parts: [Part(agentID: "claude", count: 2)]),
        ComposerPreset(name: "Mixed: 2 Claude + 2 Codex", parts: [Part(agentID: "claude", count: 2), Part(agentID: "codex", count: 2)]),
        ComposerPreset(name: "Shells: 3", parts: [Part(agentID: "shell", count: 3)]),
        ComposerPreset(name: "Command post: orchestrator + 3 shells + checklist", parts: [Part(agentID: "shell", count: 3)],
                       extras: [.orchestrator, .checklist(["Run the build", "Run the tests", "Write up the result"])]),
    ]
}
