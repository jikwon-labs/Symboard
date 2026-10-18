import AppKit
import SwiftUI
import SymboardCore

/// 1초마다 바뀌는 신호. 상태를 보여 주는 SwiftUI 본문이 구독한다.
@MainActor
final class StatusBeat: ObservableObject {
    static let shared = StatusBeat()
    @Published var tick = 0
}

/// 오케스트레이터 노드: 연결한 그룹·콘솔의 상태를 한눈에 보고 한꺼번에 명령한다.
/// 연결은 작업공간 links(오케스트레이터 → 팀 또는 콘솔)에 저장한다.
final class OrchestratorContent: NodeContent {
    let host: NSView
    var view: NSView { host }

    init(node: BoardNode, model: AppModel) {
        let c = MainWindowController.current
        host = CanvasHostingView(rootView: OrchestratorView(nodeID: node.id, model: model, beat: .shared, chrome: c?.chrome ?? ChromeModel(), c: c)
            .environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}
}

struct OrchestratorView: View {
    let nodeID: UUID
    @ObservedObject var model: AppModel
    @ObservedObject var beat: StatusBeat
    @ObservedObject var chrome: ChromeModel
    weak var c: MainWindowController?
    @State private var command = ""
    @State private var hoverRow: UUID?

    var ws: Workspace? { model.workspaceID(containing: nodeID).flatMap { model.workspace($0) } }
    var links: [NodeLink] { (ws?.links ?? []).filter { $0.from == nodeID } }
    var wiredTeams: [Team] { (ws?.teams ?? []).filter { t in links.contains { $0.to == t.id } } }
    var wiredNodes: [BoardNode] { (ws?.nodes ?? []).filter { n in n.kind == .terminal && links.contains { $0.to == n.id } } }
    /// 연결된 모든 콘솔(그룹 멤버 포함, 중복 없음).
    var targets: [BoardNode] {
        var out = wiredNodes
        for t in wiredTeams {
            for n in (ws?.nodes ?? []) where n.teamID == t.id && !out.contains(where: { $0.id == n.id }) { out.append(n) }
        }
        return out
    }
    var connecting: Bool { chrome.connectingOrchestrator == nodeID }

    var body: some View {
        let _ = beat.tick
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(targets.count) agent\(targets.count == 1 ? "" : "s") · \(wiredTeams.count) group\(wiredTeams.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(Color.symDim)
                Spacer()
                Text("\(targets.filter { status($0) == .idle }.count)/\(targets.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Color.symDim)
                    .hint("Ready / wired")
                Button { spawnWired() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Spawn an agent and wire it")
                Button { c?.toggleConnect(nodeID) } label: {
                    Label(connecting ? "Done" : "Connect", systemImage: connecting ? "checkmark" : "link")
                }
                .buttonStyle(PillButtonStyle(prominent: true)).axName(connecting ? "Done" : "Connect")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            if connecting {
                connectPicker
            } else if targets.isEmpty {
                emptyState
            } else {
                rows
            }

            commandField
        }
        .background(Color.symSurface)
    }

    func status(_ n: BoardNode) -> NodeStatus { model.sessions.status(of: n.id) ?? .starting }

    var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 26)).foregroundStyle(Color.symAccent)
            Text("No agents wired").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText)
            Text("Spawn a new one here, or tap Connect and pick\nconsoles or groups on the board.")
                .multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(Color.symDim)
            Button { spawnWired() } label: { Label("Spawn agent", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(active: true)).axName("Spawn agent")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var connectPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Click consoles on the board, or wire groups here. Tap Done when finished.")
                    .font(.system(size: 11)).foregroundStyle(Color.symDim).padding(.bottom, 4)
                if !(ws?.teams.isEmpty ?? true) {
                    Text("GROUPS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.symDim)
                }
                ForEach(ws?.teams ?? []) { t in
                    let on = links.contains { $0.to == t.id }
                    chip(t.name, count: (ws?.nodes ?? []).filter { $0.teamID == t.id }.count, color: t.colorHex, on: on) { c?.toggleWire(nodeID, to: t.id) }
                }
                let loose = (ws?.nodes ?? []).filter { $0.kind == .terminal && $0.teamID == nil }
                if !loose.isEmpty {
                    Text("CONSOLES").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.symDim).padding(.top, 4)
                }
                ForEach(loose) { n in
                    let on = links.contains { $0.to == n.id }
                    chip(n.title, count: nil, color: AgentCatalog.choice(for: n.terminal).colorHex, on: on) { c?.toggleWire(nodeID, to: n.id) }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    func chip(_ title: String, count: Int?, color: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10))
                Text(title).font(.system(size: 12, weight: .semibold))
                if let count { Text("\(count)").font(.system(size: 11, design: .monospaced)).opacity(0.7) }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
            }
            .foregroundStyle(on ? Color.white : Color.symText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.symAccent : Color.symRaised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Color(hex: color).opacity(0.4)))
        }
        .buttonStyle(.plainHit)
    }

    var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(wiredNodes.filter { n in n.teamID == nil || !wiredTeams.contains(where: { $0.id == n.teamID }) }) { row($0) }
                ForEach(wiredTeams) { t in
                    let members = (ws?.nodes ?? []).filter { $0.teamID == t.id }
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: t.colorHex)).frame(width: 6, height: 6)
                        Text(t.name.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Color.symText)
                        Spacer()
                        Text("\(members.filter { status($0) == .idle }.count)/\(members.count)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                    ForEach(members) { row($0) }
                }
            }
            .padding(.bottom, 6)
        }
        .clipped()
    }

    func row(_ n: BoardNode) -> some View {
        let choice = AgentCatalog.choice(for: n.terminal)
        let st = status(n)
        let paused = model.sessions.session(for: n.id)?.paused ?? false
        return HStack(spacing: 10) {
            AgentBadge(choice: choice, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(n.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText)
                Text(choice.name).font(.system(size: 10)).foregroundStyle(Color.symDim)
            }
            Spacer()
            if hoverRow == n.id {
                Button { c?.focus(nodeID: n.id) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plainHit).tip("Show on board")
                Button { _ = model.sessions.session(for: n.id)?.signal(paused ? SIGCONT : SIGSTOP) } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plainHit).tip(paused ? "Resume" : "Pause")
            }
            StatusPill(text: paused ? "paused" : st.pillText.lowercased(), color: paused ? Theme.textDim : st.color)
        }
        .foregroundStyle(Color.symDim)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(hoverRow == n.id ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hoverRow = $0 ? n.id : (hoverRow == n.id ? nil : hoverRow) }
    }

    var commandField: some View {
        HStack(spacing: 8) {
            TextField("", text: $command, prompt: Text("Command \(targets.count) agent\(targets.count == 1 ? "" : "s") · @ to direct").foregroundColor(Color.symDim))
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(command.isEmpty ? Color.symRaised : Color.symAccent))
            }
            .buttonStyle(.plainHit).tip("Send to wired agents")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised))
        .padding(10)
    }

    func send() {
        guard let c, c.orchestratorSend(nodeID, text: command) > 0 else { return }
        command = ""
    }

    func spawnWired() {
        guard let c, let me = model.node(nodeID) else { return }
        let choice = AgentCatalog.shared.lastChoice
        let n = c.addTerminal(spec: choice.spec(cwd: c.projectPath), at: Point(x: me.frame.x + me.frame.w + 120, y: me.frame.y))
        c.toggleWire(nodeID, to: n.id)
        c.currentCanvas?.select(nodeID)
    }
}

/// 소문자 상태 알약(오케스트레이터 행).
struct StatusPill: View {
    var text: String
    var color: NSColor
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(nsColor: color)).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(Color(nsColor: color))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color(nsColor: color).opacity(0.12)))
    }
}
