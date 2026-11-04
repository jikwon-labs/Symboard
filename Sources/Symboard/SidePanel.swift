import AppKit
import SwiftUI
import SymboardCore

/// 세션 목록 한 줄.
struct MissionRow: Identifiable, Equatable {
    var id: UUID
    var title: String
    var workspaceID: UUID
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
}

/// 오른쪽 세션 목록. 모든 작업공간의 도는 콘솔(보관한 것은 뺌)과 그 상태를 보이고, 누르면 그 콘솔로 간다.
/// 오른쪽 도구 막대의 첫 단추와 위쪽 "N live" 알약으로 연다.
@MainActor
final class SidePanelController {
    weak var model: AppModel?
    let state = SidePanelState()
    var onFocusNode: ((UUID) -> Void)?
    var onClose: (() -> Void)?
    lazy var view: NSView = {
        let host = NSHostingView(rootView: SidePanelView(state: state,
                                                         focus: { [weak self] id in self?.onFocusNode?(id) },
                                                         close: { [weak self] in self?.onClose?() }).localized())
        host.translatesAutoresizingMaskIntoConstraints = false
        return host
    }()

    var selectedNodeID: UUID? {
        get { state.selectedNodeID }
        set { state.selectedNodeID = newValue }
    }

    func reload() { refreshStatuses() }

    func refreshStatuses() {
        guard let model else { return }
        let now = Date()
        var rows: [MissionRow] = []
        for ws in model.state.workspaces {
            // 보관한 콘솔(17차)은 도는 콘솔 목록에서 뺀다. 보드의 카드로 남아 있다.
            for n in ws.nodes where n.kind == .terminal && n.terminal?.archived == nil {
                let status = model.sessions.status(of: n.id) ?? .starting
                let idle = model.sessions.session(for: n.id)?.idleSeconds(now: now) ?? 0
                let team = n.teamID.flatMap { tid in ws.teams.first { $0.id == tid } }
                rows.append(MissionRow(id: n.id, title: n.role.map { "\($0) - \(n.displayTitle)" } ?? n.displayTitle,
                                       workspaceID: ws.id, workspace: ws.name, agent: n.terminal?.agent ?? .shell,
                                       status: status, idleText: Self.format(idle: idle, status: status),
                                       team: team?.name, teamColor: team?.colorHex))
            }
        }
        rows = SessionList.order(rows, current: model.selectedWorkspace.id, workspace: \.workspaceID, status: \.status)
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
    var close: () -> Void

    private var counts: [(NodeStatus, Int)] {
        [NodeStatus.waiting, .working, .done, .idle, .exited].compactMap { s in
            let n = state.rows.filter { $0.status == s || (s == .idle && $0.status == .starting) }.count
            return n > 0 ? (s, n) : nil
        }
    }

    /// 작업공간별 묶음. 줄은 이미 작업공간 순으로 서 있다.
    private var sections: [(id: UUID, name: String, rows: [MissionRow])] {
        var out: [(id: UUID, name: String, rows: [MissionRow])] = []
        for r in state.rows {
            if out.last?.id == r.workspaceID { out[out.count - 1].rows.append(r) }
            else { out.append((r.workspaceID, r.workspace, [r])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L("SESSIONS"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.symDim)
                Text("\(state.rows.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.symText)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("Close"))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            if !counts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(counts, id: \.0) { item in
                        HStack(spacing: 4) {
                            Circle().fill(Color(nsColor: item.0.color)).frame(width: 7, height: 7)
                            Text("\(item.1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.symText)
                        }
                        // 상태 이름까지 쓰면 한국어에서 폭이 모자라 잘린다. 점 색과 마우스를 올렸을 때의 설명으로 알린다.
                        .hint(L(item.0.label))
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider().overlay(Color.symBorder)
            if state.rows.isEmpty {
                Text(L("No terminal nodes yet.\nDouble-click the board or press Cmd+T."))
                    .font(.system(size: 12)).foregroundStyle(Color.symDim)
                    .padding(14)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections, id: \.id) { sec in
                            // 작업공간이 하나뿐이면 묶음 제목은 뺀다.
                            if sections.count > 1 {
                                Text(sec.name.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(Color.symDim)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8).padding(.top, sec.id == sections.first?.id ? 2 : 10).padding(.bottom, 2)
                            }
                            ForEach(sec.rows) { row in
                                Button { focus(row.id) } label: { MissionRowView(row: row, selected: row.id == state.selectedNodeID) }
                                    .buttonStyle(HoverRowStyle())
                                    .axName("Session \(row.title)")
                            }
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.symText)
    }
}

struct MissionRowView: View {
    var row: MissionRow
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(nsColor: row.status.color)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText).lineLimit(1)
                HStack(spacing: 4) {
                    Text(L(row.status.label)).foregroundStyle(row.status == .waiting || row.status == .working ? Color(nsColor: row.status.color) : Color.symDim)
                    if !row.idleText.isEmpty { Text(L("for %@", row.idleText)) }
                    Text("· " + row.agent.displayName)
                }
                .font(.system(size: 10)).foregroundStyle(Color.symDim).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let team = row.team {
                Text(team).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: row.teamColor ?? "#5E5CE6")))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.symAccent.opacity(0.14) : Color.clear))
    }
}
