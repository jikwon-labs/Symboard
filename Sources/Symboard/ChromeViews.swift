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
            .tip("Back to projects")

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
                        .buttonStyle(.plainHit)
                        .foregroundStyle(Color.symDim)
                        .tip("New workspace")
                }
                .padding(4)
                .floatingCapsule(radius: 12)

                Button { c.closeProject() } label: {
                    HStack(spacing: 6) { Image(systemName: "xmark"); Text("Close") }
                }
                .buttonStyle(PillButtonStyle())
                .tip("Close this project and return home")
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
                    .buttonStyle(.plainHit)
                    .foregroundStyle(Color.symDim)
                    .tip("Close workspace")
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
                // 일하는 콘솔이 있으면 점을 강조색으로 바꾸고 개수를 붙인다.
                Circle().fill(chrome.workingCount > 0 ? Color.symAccent : (chrome.liveCount > 0 ? Color.green : Color.symDim)).frame(width: 7, height: 7)
                Text("\(chrome.liveCount)").font(.system(size: 12, weight: .semibold))
                Text("live").font(.system(size: 12)).foregroundStyle(Color.symDim)
                if chrome.workingCount > 0 {
                    Text("· \(chrome.workingCount) working").font(.system(size: 12)).foregroundStyle(Color.symAccent)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .floatingCapsule(radius: 10)
            .hint("Running consoles")

            Button { chrome.usageOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Color.symDim)
                    if let p = chrome.sessionPercent {
                        SessionRing(percent: p, tintHex: chrome.sessionTint).hint("Session \(p)% used")
                    }
                    Text(chrome.resetText)
                }
            }
            .buttonStyle(PillButtonStyle(active: chrome.usageOpen))
            .tip("Usage")
            .popover(isPresented: $chrome.usageOpen, arrowEdge: .bottom) {
                UsagePopover(store: c.model.usage) { chrome.usageOpen = false }
            }

            HStack(spacing: 2) {
                iconButton("person.crop.circle", "Accounts") { chrome.accountsOpen.toggle() }
                    .popover(isPresented: $chrome.accountsOpen, arrowEdge: .bottom) { AccountsPopover(profiles: c.model.profiles, c: c) }
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
                .hint("Tools")
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .floatingCapsule(radius: 10)
        }
        .foregroundStyle(Color.symText)
        .fixedSize()
    }

    func iconButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 30, height: 28) }
            .buttonStyle(.plainHit)
            .tip(tip)
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
            .tip("Spawn agent")
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
                .tip("Text")
            toolButton("pencil.tip", "Pen", active: chrome.tool == .pen) { c.setTool(chrome.tool == .pen ? .select : .pen) }
            toolButton("eraser", "Eraser", active: chrome.tool == .eraser) { c.setTool(chrome.tool == .eraser ? .select : .eraser) }
            Divider().frame(width: 24).overlay(Color.symBorder)
            Button { chrome.shapeOpen.toggle() } label: { Image(systemName: "square.on.circle") }
                .buttonStyle(RailToolStyle(active: { if case .place(.shape) = chrome.tool { return true } else { return false } }()))
                .tip("Shapes")
                .popover(isPresented: $chrome.shapeOpen, arrowEdge: .trailing) {
                    ShapePicker { k in chrome.shapeOpen = false; c.setTool(.place(k == "sticky" ? .sticky : .shape(k))) }
                }
            DiagramRailButton(maker: c.diagrams)
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
            .tip(tip)
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
                .buttonStyle(HoverRowStyle()).axName("Spawn \(choice.name)")
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
            .buttonStyle(HoverRowStyle()).axName(showAll ? "Fewer agents" : "All agents")
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
    @State private var layersOpen = false

    var body: some View {
        VStack(spacing: 4) {
            Button { layersOpen.toggle() } label: { Image(systemName: "square.3.layers.3d") }
                .buttonStyle(RailButtonStyle()).tip("Layers")
                .popover(isPresented: $layersOpen, arrowEdge: .leading) { LayersList(model: c.model, c: c) }
            Button { chrome.insertOpen.toggle() } label: { Image(systemName: "checklist") }
                .buttonStyle(RailButtonStyle()).tip("Insert checklist, board, note")
                .popover(isPresented: $chrome.insertOpen, arrowEdge: .leading) {
                    InsertMenu { p in chrome.insertOpen = false; c.setTool(.place(p)) }
                }
            // 원본 오른쪽 막대 셋째: 오케스트레이터를 바로 놓는다(설정은 위쪽 톱니).
            Button { c.addOrchestratorNearSelection() } label: { Image(systemName: "circle.hexagongrid") }
                .buttonStyle(RailButtonStyle()).tip("Orchestrator")
            Divider().frame(width: 22).overlay(Color.symBorder)
            Button { c.openStudio(tab: "Code") } label: { Image(systemName: "folder") }
                .buttonStyle(RailButtonStyle()).tip("Code studio")
            Button { c.openStudio(tab: "Markdown") } label: { Image(systemName: "doc.text") }
                .buttonStyle(RailButtonStyle()).tip("Markdown studio")
            Button { c.openStudio(tab: "Docs") } label: { Image(systemName: "doc.richtext") }
                .buttonStyle(RailButtonStyle()).tip("Document studio")
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
            .buttonStyle(RailButtonStyle()).tip("Loops")
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
            row("calendar", "Calendar", "A month with events") { pick(.calendar) }
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
        .buttonStyle(HoverRowStyle()).axName(title)
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
        case .inspector: return "ladybug"
        case .memory: return "brain"
        case .document: return "doc.richtext"
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
                        .buttonStyle(PillButtonStyle(prominent: true)).axName(cf.button)
                    Button("Cancel") { chrome.confirm = nil }.axName("Cancel")
                        .buttonStyle(PillButtonStyle())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .floatingCapsule(radius: 14)
            } else if let s = chrome.suggestion, !chrome.overlayOpen {
                HStack(spacing: 6) {
                    Button(s) { chrome.command = "@all git status"; focused = true }
                        .buttonStyle(.plainHit).axName(s)
                    Button { chrome.suggestion = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.tip("Dismiss hint")
                        .buttonStyle(.plainHit)
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.symDim)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .floatingCapsule(radius: 10)
            }
            HStack(spacing: 6) {
                Button("New console") { c.spawnQuick(count: 1) }.axName("New console")
                Button("Spawn 4") { c.spawnQuick(count: 4) }.axName("Spawn 4")
                Button("Group") { c.openComposer(nil) }.axName("Group")
                    .background(PopoverAnchor { c.composerAnchor = $0 })
                Menu("Presets") {
                    ForEach(ComposerPreset.all) { p in Button(p.name) { c.spawnPreset(p) } }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .modifier(PillLook())
                Button("Pause all") { c.pauseAll(true) }.axName("Pause all")
                Button("Resume all") { c.pauseAll(false) }.axName("Resume all")
                Button("Memory") { c.openMemory() }.axName("Memory")
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
                .buttonStyle(.plainHit)
                .tip("Send")
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
            Button { chrome.gitOpen.toggle() } label: { chip(b) }
                .buttonStyle(.plainHit)
                .tip("Branch and changes: click to commit")
                .popover(isPresented: $chrome.gitOpen, arrowEdge: .top) {
                    if let card = chrome.gitCard {
                        GitCardView(card: card) { chrome.gitOpen = false }
                            .frame(width: 360, height: 470)
                            .onAppear {
                                // 커밋 뒤에도 원본처럼 팝오버를 연 채 결과(Working tree clean·결과 줄)를 보인다.
                                // 입력칸이 사라진 뒤에는 결과 줄이 초점을 받는다(GitCardView.resultFocused).
                                Task { await card.refresh() }
                            }
                    }
                }
                .hiddenOnHome(chrome)
        }
    }

    func chip(_ b: String) -> some View {
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
            .fixedSize()
    }
}

struct ZoomControl: View {
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    var body: some View {
        HStack(spacing: 2) {
            Button { c.zoomOut(nil) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }.tip("Zoom out")
            Button { c.zoomReset(nil) } label: {
                Text("\(chrome.zoomPercent)%").font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 44)
            }
            .tip("Reset to 100%")
            Button { c.zoomIn(nil) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }.tip("Zoom in")
        }
        .buttonStyle(.plainHit)
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
                Button("Yes") { c.answerResumeAll(true) }.buttonStyle(PillButtonStyle(prominent: true)).axName("Yes")
                Button("No") { c.answerResumeAll(false) }.buttonStyle(PillButtonStyle()).axName("No")
                Button { chrome.resumeDismissed = true } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symDim)
                    .tip("Decide per console")
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
                    .buttonStyle(.plainHit)
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
                .buttonStyle(.plainHit)
            }
            Spacer()
        }
        .padding(.horizontal, 90).padding(.top, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.symCanvas)
    }
}

struct DiagramRailButton: View {
    @ObservedObject var maker: DiagramMaker
    var body: some View {
        Button { maker.open.toggle() } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
            .buttonStyle(RailToolStyle(active: maker.open || maker.drawing != nil))
            .tip("Diagram")
            .popover(isPresented: $maker.open, arrowEdge: .trailing) { DiagramPopover(maker: maker) }
    }
}


/// SwiftUI 단추 자리에 AppKit 팝오버를 붙이기 위한 빈 뷰.
struct PopoverAnchor: NSViewRepresentable {
    var onMake: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onMake(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 글을 쓰는 창이 열리자마자 첫 칸에 초점을 준다. 바로 친 글자가 사라지지 않게 한다.
/// 창이 키 창이 되고 SwiftUI 가 필드를 붙인 뒤에 잡아야 해서 조금 미뤄 두 번 시도한다.
struct AutoFocus: ViewModifier {
    var enabled: Bool
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onAppear {
                guard enabled else { return }
                for delay in [0.05, 0.25] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { focused = true }
                }
            }
    }
}

extension View {
    func autoFocus(_ enabled: Bool = true) -> some View { modifier(AutoFocus(enabled: enabled)) }
}

/// 사용량 알약 안의 작은 세션 % 링(가운데 claude 글자).
struct SessionRing: View {
    var percent: Int
    var tintHex = "#E8704A"
    var body: some View {
        ZStack {
            Circle().stroke(Color.symBorder, lineWidth: 2)
            Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(Color(hex: tintHex), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)").font(.system(size: 7, weight: .bold, design: .rounded)).foregroundStyle(Color.symText)
        }
        .frame(width: 16, height: 16)
    }
}
