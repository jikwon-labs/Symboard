import AppKit
import SwiftUI
import SymboardCore

// MARK: 위쪽 왼쪽: 홈·프로젝트·작업공간 탭

struct TopLeftBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController

    var project: String? { model.selectedWorkspace.projectPath }

    var body: some View {
        HStack(spacing: 8) {
            Button { c.goHome() } label: {
                HStack(spacing: 6) { Image(systemName: "arrow.left"); Text("Home") }
            }
            .buttonStyle(PillButtonStyle(active: chrome.showingHome))
            .help("Back to projects")

            if !chrome.showingHome {
                HStack(spacing: 4) {
                    Menu {
                        ForEach(Projects.paths(in: model.state.workspaces), id: \.self) { p in
                            Button((p as NSString).lastPathComponent) { c.openProject(p) }
                        }
                        Divider()
                        Button("Open Folder...") { c.chooseProjectFolder() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(Color.symDim)
                            Text(project.map { ($0 as NSString).lastPathComponent } ?? "No project")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.visible)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .help(project ?? "")

                    Rectangle().fill(Color.symBorder).frame(width: 1, height: 18)

                    ForEach(model.state.workspaces.filter { $0.projectPath == project }) { ws in
                        WorkspaceTab(ws: ws, active: ws.id == model.selectedWorkspace.id, c: c)
                    }
                    Button { c.newWorkspace(nil) } label: { Image(systemName: "plus").frame(width: 22, height: 22) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.symDim)
                        .help("New workspace")
                }
                .padding(4)
                .floatingCapsule(radius: 12)

                Button { c.closeProject() } label: {
                    HStack(spacing: 6) { Image(systemName: "xmark"); Text("Close") }
                }
                .buttonStyle(PillButtonStyle())
                .help("Close this project and return home")
            }
        }
        .foregroundStyle(Color.symText)
        .fixedSize()
    }
}

struct WorkspaceTab: View {
    var ws: Workspace
    var active: Bool
    let c: MainWindowController
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(ws.name).font(.system(size: 12, weight: active ? .semibold : .regular))
            if active {
                Text("\(ws.nodes.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.symAccent)
            }
            if active || hover {
                Button { c.closeWorkspace(ws.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.symDim)
                    .help("Close workspace")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.symAccent.opacity(0.10) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Color.symAccent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { c.renameWorkspace(ws.id) }
        .onTapGesture { c.model.selectWorkspace(ws.id) }
    }
}

// MARK: 위쪽 오른쪽: live·사용량·계정·설정·도구

struct TopRightBar: View {
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(chrome.liveCount > 0 ? Color.green : Color.symDim).frame(width: 7, height: 7)
                Text("\(chrome.liveCount)").font(.system(size: 12, weight: .semibold))
                Text("live").font(.system(size: 12)).foregroundStyle(Color.symDim)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .floatingCapsule(radius: 10)
            .help("Running consoles")

            Button { c.openUsage() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Color.symDim)
                    Text(chrome.resetText)
                }
            }
            .buttonStyle(PillButtonStyle())
            .help("Usage")

            HStack(spacing: 2) {
                iconButton("person.crop.circle", "Accounts") { c.openProfiles() }
                iconButton("gearshape", "Settings") { c.openSettings() }
                Menu {
                    Button("Mission Map") { c.openMission() }
                    Button("Loops") { c.openLoops() }
                    Button("Memory") { c.openMemory() }
                    Button("Usage") { c.openUsage() }
                    Button("Accounts") { c.openProfiles() }
                    Divider()
                    Button("Studio") { c.openStudio(nil) }
                    Button("Zoom to Fit") { c.zoomToFit(nil) }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30, height: 28)
                .help("Tools")
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .floatingCapsule(radius: 10)
        }
        .foregroundStyle(Color.symText)
        .fixedSize()
    }

    func iconButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 30, height: 28) }
            .buttonStyle(.plain)
            .help(tip)
    }
}

// MARK: 왼쪽 도구 막대

struct LeftRail: View {
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var catalog = AgentCatalog.shared
    let c: MainWindowController

    var isPlacingAgent: Bool { if case .place(.agent) = chrome.tool { return true } else { return false } }

    var body: some View {
        VStack(spacing: 4) {
            toolButton("cursorarrow", "Select (V)", active: chrome.tool == .select) { c.setTool(.select) }
            Button { chrome.spawnMenuOpen.toggle() } label: {
                Image(systemName: "sparkle").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(RailToolStyle(active: isPlacingAgent, tint: .symAccent))
            .help("Spawn agent")
            .popover(isPresented: $chrome.spawnMenuOpen, arrowEdge: .trailing) {
                SpawnAgentMenu(catalog: catalog) { choice in
                    chrome.spawnMenuOpen = false
                    catalog.lastChoiceID = choice.id
                    c.setTool(.place(.agent(choice.id)))
                }
            }
            toolButton("plus.square.on.square", "Duplicate selection", active: false) { c.duplicateSelection() }
            Button { c.setTool(.place(.text)) } label: { Text("Aa").font(.system(size: 14, weight: .medium)) }
                .buttonStyle(RailToolStyle(active: chrome.tool == .place(.text)))
                .help("Text")
            toolButton("pencil.tip", "Pen", active: chrome.tool == .pen) { c.setTool(chrome.tool == .pen ? .select : .pen) }
            toolButton("eraser", "Eraser", active: chrome.tool == .eraser) { c.setTool(chrome.tool == .eraser ? .select : .eraser) }
            Divider().frame(width: 24).overlay(Color.symBorder)
            toolButton("square.on.circle", "Shapes", active: false) { c.openShapes() }
            toolButton("point.3.connected.trianglepath.dotted", "Diagram", active: false) { c.openDiagram() }
            toolButton("globe", "Web tile", active: chrome.tool == .place(.web)) { c.setTool(.place(.web)) }
            toolButton("photo", "Image", active: false) { c.addImageFromPanel() }
            Divider().frame(width: 24).overlay(Color.symBorder)
            toolButton("arrow.up.left.and.arrow.down.right", "Zoom to fit", active: false) { c.zoomToFit(nil) }
        }
        .padding(.vertical, 8).padding(.horizontal, 5)
        .floatingCapsule(radius: 22)
        .fixedSize()
        .hiddenOnHome(chrome)
    }

    func toolButton(_ symbol: String, _ tip: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(RailToolStyle(active: active))
            .help(tip)
    }
}

/// 왼쪽 막대 버튼. 켠 도구는 강조색 원.
struct RailToolStyle: ButtonStyle {
    var active: Bool
    var tint: Color = .symText
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(active ? Color.white : tint.opacity(configuration.isPressed ? 0.6 : 0.88))
            .frame(width: 38, height: 38)
            .background(Circle().fill(active ? Color.symAccent : Color.clear))
            .contentShape(Circle())
    }
}

struct SpawnAgentMenu: View {
    @ObservedObject var catalog: AgentCatalog
    var pick: (AgentChoice) -> Void
    @State private var showAll = false

    var rows: [AgentChoice] { showAll ? AgentCatalog.known : catalog.available }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SPAWN AGENT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.symDim)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(rows) { choice in
                Button { pick(choice) } label: {
                    HStack(spacing: 12) {
                        AgentBadge(choice: choice, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                            Text(choice.subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                        }
                        Spacer()
                        if choice.id == catalog.lastChoiceID {
                            Image(systemName: "checkmark").foregroundStyle(Color.symAccent)
                        } else if !catalog.installed.contains(choice.id) {
                            Text("not found").font(.system(size: 10)).foregroundStyle(Color.symDim)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
            }
            Button { showAll.toggle() } label: {
                HStack {
                    Image(systemName: "square.grid.2x2").foregroundStyle(Color.symDim)
                    Text(showAll ? "Installed only" : "All agents").foregroundStyle(Color.symText)
                    Spacer()
                    Text("\(AgentCatalog.known.count)").foregroundStyle(Color.symDim).font(.system(size: 11, design: .monospaced))
                    Image(systemName: "chevron.right").foregroundStyle(Color.symDim)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            Text("then click the canvas to drop it")
                .font(.system(size: 11)).foregroundStyle(Color.symDim)
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .frame(width: 280)
        .background(Color.symSurface)
    }
}

struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }
    struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover || configuration.isPressed ? 0.06 : 0)))
                .onHover { hover = $0 }
        }
    }
}

// MARK: 오른쪽 세로 막대

struct RightRail: View {
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    @State private var insertOpen = false
    @State private var layersOpen = false

    var body: some View {
        VStack(spacing: 4) {
            Button { layersOpen.toggle() } label: { Image(systemName: "square.3.layers.3d") }
                .buttonStyle(RailButtonStyle()).help("Layers")
                .popover(isPresented: $layersOpen, arrowEdge: .leading) { LayersList(model: c.model, c: c) }
            Button { insertOpen.toggle() } label: { Image(systemName: "checklist") }
                .buttonStyle(RailButtonStyle()).help("Insert checklist, board, note")
                .popover(isPresented: $insertOpen, arrowEdge: .leading) {
                    InsertMenu { p in insertOpen = false; c.setTool(.place(p)) }
                }
            Button { c.openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(RailButtonStyle()).help("Settings")
            Divider().frame(width: 22).overlay(Color.symBorder)
            Button { c.openStudio(tab: "Code") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(RailButtonStyle()).help("Code studio")
            Button { c.openStudio(tab: "Markdown") } label: { Image(systemName: "doc.text") }
                .buttonStyle(RailButtonStyle()).help("Markdown studio")
            Button { c.openStudio(tab: "Docs") } label: { Image(systemName: "doc.richtext") }
                .buttonStyle(RailButtonStyle()).help("Document studio")
            Divider().frame(width: 22).overlay(Color.symBorder)
            Button { c.openLoops() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .overlay(alignment: .topTrailing) {
                        if chrome.loopBadge > 0 {
                            Text("\(chrome.loopBadge)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.symAccent))
                                .offset(x: 9, y: -8)
                        }
                    }
            }
            .buttonStyle(RailButtonStyle()).help("Loops")
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .floatingCapsule(radius: 20)
        .fixedSize()
        .hiddenOnHome(chrome)
    }
}

struct InsertMenu: View {
    var pick: (Placement) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("checklist", "Checklist", "Objectives with a progress counter") { pick(.checklist) }
            row("rectangle.split.3x1", "Board", "Kanban columns with cards") { pick(.kanban) }
            row("note.text", "Sticky note", "A paper note") { pick(.sticky) }
            row("point.3.connected.trianglepath.dotted", "Orchestrator", "Watch and command many consoles") { pick(.orchestrator) }
        }
        .padding(6)
        .frame(width: 250)
        .background(Color.symSurface)
    }

    func row(_ symbol: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.symRaised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.symText)
                    Text(sub).font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
                Spacer()
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

struct LayersList: View {
    @ObservedObject var model: AppModel
    let c: MainWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LAYERS").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.symDim).padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.selectedWorkspace.nodes.reversed()) { n in
                        Button { c.focus(nodeID: n.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: Self.symbol(n.kind)).frame(width: 18).foregroundStyle(Color.symDim)
                                Text(n.title.isEmpty ? n.kind.rawValue : n.title).lineLimit(1).foregroundStyle(Color.symText)
                                Spacer()
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRowStyle())
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 240)
        .background(Color.symSurface)
    }

    static func symbol(_ k: NodeKind) -> String {
        switch k {
        case .terminal: return "terminal"
        case .sticky: return "note.text"
        case .text: return "textformat"
        case .checklist: return "checklist"
        case .kanban: return "rectangle.split.3x1"
        case .image: return "photo"
        case .web: return "globe"
        case .git: return "arrow.triangle.branch"
        case .file: return "doc"
        case .orchestrator: return "point.3.connected.trianglepath.dotted"
        case .calendar: return "calendar"
        case .shape: return "square.on.circle"
        }
    }
}

// MARK: 아래 명령 바

struct BottomBar: View {
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var composer: ComposerState
    let c: MainWindowController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let cf = chrome.confirm {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.symAccent)
                    Text(cf.message).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.symText)
                    Button(cf.button) { chrome.confirm = nil; cf.action() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                    Button("Cancel") { chrome.confirm = nil }
                        .buttonStyle(PillButtonStyle())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .floatingCapsule(radius: 14)
            } else if let s = chrome.suggestion {
                HStack(spacing: 6) {
                    Button(s) { chrome.command = "@all git status"; focused = true }
                        .buttonStyle(.plain)
                    Button { chrome.suggestion = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.symDim)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .floatingCapsule(radius: 10)
            }
            HStack(spacing: 6) {
                Button("New console") { c.spawnQuick(count: 1) }
                Button("Spawn 4") { c.spawnQuick(count: 4) }
                Button("Group") { c.openComposer(nil) }
                    .popover(isPresented: $composer.open, arrowEdge: .top) {
                        ComposerCard(state: composer) { c.spawnComposer() }
                    }
                Menu("Presets") {
                    ForEach(ComposerPreset.all) { p in Button(p.name) { c.spawnPreset(p) } }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .modifier(PillLook())
                Button("Pause all") { c.pauseAll(true) }
                Button("Resume all") { c.pauseAll(false) }
                Button("Memory") { c.openMemory() }
            }
            .buttonStyle(PillButtonStyle())
            HStack(spacing: 10) {
                Image(systemName: "chevron.right.2").foregroundStyle(Color.symAccent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.symAccent.opacity(0.15)))
                TextField("", text: $chrome.command, prompt: Text(placeholder).foregroundColor(Color.symDim))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.symText)
                    .focused($focused)
                    .onSubmit { c.runCommand() }
                Button { c.runCommand() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(chrome.command.isEmpty ? Color.symDim : .white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(chrome.command.isEmpty ? Color.symRaised : Color.symAccent))
                }
                .buttonStyle(.plain)
                .help("Send")
            }
            .padding(.leading, 8).padding(.trailing, 8).padding(.vertical, 7)
            .frame(width: 520)
            .floatingCapsule(radius: 18)
        }
        .foregroundStyle(Color.symText)
        .fixedSize()
        .hiddenOnHome(chrome)
    }

    var placeholder: String {
        if let id = chrome.selectedNodeID, let n = c.model.node(id), n.kind == .terminal {
            return "Message \(n.title) · @ to direct"
        }
        return "Type a command · @ to direct"
    }
}

struct PillLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.symBorder, lineWidth: 1))
    }
}

// MARK: 아래 왼쪽·오른쪽

struct BranchChip: View {
    @ObservedObject var chrome: ChromeModel
    var body: some View {
        if let b = chrome.branch {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(b).font(.system(size: 12, weight: .medium, design: .monospaced))
                if chrome.changeCount > 0 {
                    Text("\(chrome.changeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.symAccent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.symAccent.opacity(0.15)))
                }
            }
            .foregroundStyle(Color.symText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .floatingCapsule(radius: 10)
            .help("Branch and uncommitted changes in this project")
            .fixedSize()
        }
    }
}

struct ZoomControl: View {
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    var body: some View {
        HStack(spacing: 2) {
            Button { c.zoomOut(nil) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
            Button { c.zoomReset(nil) } label: {
                Text("\(chrome.zoomPercent)%").font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 44)
            }
            .help("Reset to 100%")
            Button { c.zoomIn(nil) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.symText)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .floatingCapsule(radius: 10)
        .fixedSize()
        .hiddenOnHome(chrome)
    }
}

extension View {
    /// 홈(프로젝트 목록)에서는 보드 전용 막대를 숨긴다.
    func hiddenOnHome(_ chrome: ChromeModel) -> some View {
        opacity(chrome.showingHome ? 0 : 1).allowsHitTesting(!chrome.showingHome)
    }
}

/// 다시 열었을 때 오른쪽 위 토스트.
struct ResumeToast: View {
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    var body: some View {
        if chrome.resumeCount > 0 && !chrome.resumeDismissed && !chrome.showingHome {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).foregroundStyle(Color.symAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume all conversations?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                    Text("\(chrome.resumeCount) console\(chrome.resumeCount == 1 ? "" : "s") can pick up their last chat")
                        .font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
                Button("Yes") { c.answerResumeAll(true) }.buttonStyle(PillButtonStyle(prominent: true))
                Button("No") { c.answerResumeAll(false) }.buttonStyle(PillButtonStyle())
                Button { chrome.resumeDismissed = true } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Color.symDim)
                    .help("Decide per console")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .floatingCapsule(radius: 14)
            .fixedSize()
        }
    }
}

/// 도구 안내와 짧은 알림.
struct HintBanner: View {
    @ObservedObject var chrome: ChromeModel
    var body: some View {
        let text: String? = {
            if let t = chrome.toast { return t }
            if case .place(let p) = chrome.tool { return p.hint }
            if chrome.tool == .eraser { return "Click a pen stroke to erase it · Esc to stop" }
            return nil
        }()
        if let text {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.symText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .floatingCapsule(radius: 10)
                .fixedSize()
        }
    }
}

// MARK: 홈(프로젝트 목록)

struct HomeView: View {
    @ObservedObject var model: AppModel
    let c: MainWindowController

    var body: some View {
        let paths = Projects.paths(in: model.state.workspaces)
        VStack(alignment: .leading, spacing: 18) {
            Text("Projects").font(Font(Theme.handwriting(size: 40))).foregroundStyle(Color.symText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(paths, id: \.self) { p in
                    let wss = model.state.workspaces.filter { $0.projectPath == p }
                    Button { c.openProject(p) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(Color.symAccent)
                                Text((p as NSString).lastPathComponent).font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }
                            Text((p as NSString).abbreviatingWithTildeInPath).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.symDim).lineLimit(1).truncationMode(.middle)
                            Text("\(wss.count) workspace\(wss.count == 1 ? "" : "s") · \(wss.reduce(0) { $0 + $1.nodes.count }) items")
                                .font(.system(size: 11)).foregroundStyle(Color.symDim)
                        }
                        .foregroundStyle(Color.symText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.symSurface))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.symBorder))
                    }
                    .buttonStyle(.plain)
                }
                Button { c.chooseProjectFolder() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 20))
                        Text("Open folder").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.symDim)
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.symBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 90).padding(.top, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.symCanvas)
    }
}
