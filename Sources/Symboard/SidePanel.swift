import AppKit
import SwiftUI
import SymboardCore

/// 미션 맵 한 줄.
struct MissionRow: Identifiable, Equatable {
    var id: UUID
    var title: String
    var workspace: String
    var agent: AgentKind
    var status: NodeStatus
    var idleText: String
    var team: String?
    var teamColor: String?
}

@MainActor
final class SidePanelState: ObservableObject {
    @Published var rows: [MissionRow] = []
    @Published var tab: String = "Mission"
    @Published var selectedNodeID: UUID?
    /// 다른 기능이 패널 탭을 추가한다. 이름과 뷰.
    @Published var extraTabs: [(String, AnyView)] = []
}

/// 오른쪽 패널. 기본 탭은 전체 터미널 노드의 상태 목록(미션 맵).
@MainActor
final class SidePanelController {
    weak var model: AppModel?
    let state = SidePanelState()
    var onFocusNode: ((UUID) -> Void)?
    lazy var view: NSView = {
        let host = NSHostingView(rootView: SidePanelView(state: state, focus: { [weak self] id in self?.onFocusNode?(id) }).localized())
        host.translatesAutoresizingMaskIntoConstraints = false
        return host
    }()

    var selectedNodeID: UUID? {
        get { state.selectedNodeID }
        set { state.selectedNodeID = newValue }
    }

    func addTab(_ name: String, view: AnyView) {
        state.extraTabs.append((name, view))
    }

    func reload() { refreshStatuses() }

    func refreshStatuses() {
        guard let model else { return }
        let now = Date()
        var rows: [MissionRow] = []
        for ws in model.state.workspaces {
            for n in ws.nodes where n.kind == .terminal {
                let status = model.sessions.status(of: n.id) ?? .starting
                let idle = model.sessions.session(for: n.id)?.idleSeconds(now: now) ?? 0
                let team = n.teamID.flatMap { tid in ws.teams.first { $0.id == tid } }
                rows.append(MissionRow(id: n.id, title: n.role.map { "\($0) - \(n.displayTitle)" } ?? n.displayTitle,
                                       workspace: ws.name, agent: n.terminal?.agent ?? .shell,
                                       status: status, idleText: Self.format(idle: idle, status: status),
                                       team: team?.name, teamColor: team?.colorHex))
            }
        }
        if rows != state.rows { state.rows = rows }
    }

    static func format(idle: TimeInterval, status: NodeStatus) -> String {
        guard status == .idle || status == .waiting else { return "" }
        let s = Int(idle)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

struct SidePanelView: View {
    @ObservedObject var state: SidePanelState
    var focus: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.tab) {
                Text(L("Mission")).tag("Mission")
                ForEach(state.extraTabs.map(\.0), id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(8)
            Divider()
            if state.tab == "Mission" {
                MissionListView(state: state, focus: focus)
            } else if let v = state.extraTabs.first(where: { $0.0 == state.tab })?.1 {
                v
            }
        }
        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1)))
    }
}

struct MissionListView: View {
    @ObservedObject var state: SidePanelState
    var focus: (UUID) -> Void

    private var counts: [(NodeStatus, Int)] {
        [NodeStatus.working, .waiting, .idle, .done, .exited].map { s in (s, state.rows.filter { $0.status == s }.count) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ForEach(counts, id: \.0) { item in
                    HStack(spacing: 4) {
                        Circle().fill(Color(nsColor: item.0.color)).frame(width: 8, height: 8)
                        Text("\(item.1)").font(.system(size: 11, weight: .semibold))
                    }
                    .hint(L(item.0.label))
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            if state.rows.isEmpty {
                Text(L("No terminal nodes yet.\nDouble-click the board or press Cmd+T."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                Spacer()
            } else {
                List(state.rows) { row in
                    Button { focus(row.id) } label: { MissionRowView(row: row, selected: row.id == state.selectedNodeID) }
                        .buttonStyle(.plainHit)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

struct MissionRowView: View {
    var row: MissionRow
    var selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(nsColor: row.status.color)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(L(row.status.label))
                    if !row.idleText.isEmpty { Text(L("for %@", row.idleText)) }
                    Text("- \(row.workspace)")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if let team = row.team {
                Text(team).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(nsColor: NSColor(hex: row.teamColor ?? "#5E5CE6"))).cornerRadius(3)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
    }
}
