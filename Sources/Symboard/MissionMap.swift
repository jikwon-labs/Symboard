import AppKit
import SwiftUI
import SymboardCore

/// 미션 맵: 오케스트레이터 → 그룹 → 콘솔 구조와 상태를 한 화면에서 본다. 보드 위에 뜨는 큰 모달.
struct MissionMapView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var beat: StatusBeat
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController
    @State private var filter = "All"
    @State private var query = ""
    var selected: UUID? {
        get { chrome.missionSelected }
        nonmutating set { chrome.missionSelected = newValue }
    }

    static let rowH: CGFloat = 52
    static let filters = ["All", "Working", "Needs you", "Idle", "Done"]

    var ws: Workspace { model.selectedWorkspace }
    var consoles: [BoardNode] { ws.nodes.filter { $0.kind == .terminal } }
    var orchestrators: [BoardNode] { ws.nodes.filter { $0.kind == .orchestrator } }
    var teams: [Team] { ws.teams.filter { t in consoles.contains { $0.teamID == t.id } } }
    var links: [NodeLink] { ws.links ?? [] }

    /// 이어하기 답을 기다리는(아직 띄우지 않은) 콘솔은 끝난 것이 아니라 대기다. Idle 칸에 세고 "On hold" 로 보인다.
    func onHold(_ id: UUID) -> Bool { model.sessions.pendingResume.contains(id) }
    func status(_ id: UUID) -> NodeStatus { onHold(id) ? .idle : (model.sessions.status(of: id) ?? .starting) }

    static func bucket(_ s: NodeStatus) -> String {
        switch s {
        case .working: return "Working"
        case .waiting: return "Needs you"
        case .idle, .starting: return "Idle"
        case .done, .exited: return "Done"
        }
    }

    func teamName(_ n: BoardNode) -> String? { n.teamID.flatMap { id in ws.teams.first { $0.id == id }?.name } }

    var visible: [BoardNode] {
        consoles.filter { n in
            (filter == "All" || Self.bucket(status(n.id)) == filter)
            && (query.isEmpty || n.title.localizedCaseInsensitiveContains(query) || (teamName(n)?.localizedCaseInsensitiveContains(query) ?? false))
        }
        .sorted { (teamName($0) ?? "~", $0.title) < (teamName($1) ?? "~", $1.title) }
    }

    /// 콘솔에 닿는 오케스트레이터들(직접 또는 그룹을 거쳐).
    func orchestrators(of n: BoardNode) -> [BoardNode] {
        orchestrators.filter { o in links.contains { $0.from == o.id && ($0.to == n.id || $0.to == n.teamID) } }
    }

    var subtitle: String {
        let working = consoles.filter { status($0.id) == .working }.count
        return [Ln(orchestrators.count, "%d orchestrator", "%d orchestrators"), Ln(teams.count, "%d team", "%d teams"), Ln(consoles.count, "%d console", "%d consoles"), L("%d working", consoles.filter { status($0.id) == .working }.count)].joined(separator: " · ")
    }

    var body: some View {
        let _ = beat.tick
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { chrome.missionOpen = false }
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.symBorder)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        filterBar
                        graph
                        legend
                    }
                    Divider().overlay(Color.symBorder)
                    detail.frame(width: 300)
                }
            }
            .frame(maxWidth: 1120, maxHeight: 700)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .padding(.horizontal, 60).padding(.vertical, 50)
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Color.symAccent)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Color.symAccent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Mission Map")).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.symText)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.symDim)
            }
            Spacer()
            Button { chrome.missionOpen = false } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }.tip(L("Close mission map"))
                .buttonStyle(.plainHit).foregroundStyle(Color.symDim)
        }
        .padding(18)
    }

    var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(Self.filters, id: \.self) { f in
                let n = f == "All" ? consoles.count : consoles.filter { Self.bucket(status($0.id)) == f }.count
                Button { filter = f } label: {
                    HStack(spacing: 5) {
                        if f != "All" { Circle().fill(Self.color(f)).frame(width: 6, height: 6) }
                        Text(L(f)).font(.system(size: 12, weight: .medium))
                        Text("\(n)").font(.system(size: 11, design: .monospaced)).opacity(0.7)
                    }
                    .foregroundStyle(filter == f ? Color.white : Color.symText.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(filter == f ? Color.symAccent : Color.clear))
                }
                .buttonStyle(.plainHit)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.symDim)
                TextField("", text: $query, prompt: Text(L("Find a console or team")).foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).foregroundStyle(Color.symText)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    static func color(_ bucket: String) -> Color {
        switch bucket {
        case "Working": return Color(nsColor: NodeStatus.working.color)
        case "Needs you": return Color(nsColor: NodeStatus.waiting.color)
        case "Idle": return Color(nsColor: NodeStatus.idle.color)
        default: return Color(nsColor: NodeStatus.done.color)
        }
    }

    // MARK: 그래프

    struct Placed { var id: UUID; var y: CGFloat }

    var graph: some View {
        let rows = visible
        let colX: [CGFloat] = [20, 300, 560]
        let consoleY = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, CGFloat($0.offset) * Self.rowH + 30) })
        let shownTeams = teams.filter { t in rows.contains { $0.teamID == t.id } }
        let teamY: [UUID: CGFloat] = Dictionary(uniqueKeysWithValues: shownTeams.map { t in
            let ys = rows.filter { $0.teamID == t.id }.compactMap { consoleY[$0.id] }
            return (t.id, ys.reduce(0, +) / CGFloat(max(ys.count, 1)))
        })
        let loose = rows.filter { orchestrators(of: $0).isEmpty }
        let ccY = loose.isEmpty ? 30 : loose.compactMap { consoleY[$0.id] }.reduce(0, +) / CGFloat(loose.count)
        let orchY: [UUID: CGFloat] = Dictionary(uniqueKeysWithValues: orchestrators.enumerated().map { i, o in
            let ys = rows.filter { orchestrators(of: $0).contains { $0.id == o.id } }.compactMap { consoleY[$0.id] }
            return (o.id, ys.isEmpty ? CGFloat(i) * 70 + 100 : ys.reduce(0, +) / CGFloat(ys.count))
        })
        let height = max(CGFloat(rows.count) * Self.rowH + 40, 420)
        return ScrollView {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    func curve(_ a: CGPoint, _ b: CGPoint, dashed: Bool, color: Color) {
                        var p = Path()
                        p.move(to: a)
                        let k = (b.x - a.x) * 0.5
                        p.addCurve(to: b, control1: CGPoint(x: a.x + k, y: a.y), control2: CGPoint(x: b.x - k, y: b.y))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.2, dash: dashed ? [4, 4] : []))
                    }
                    let accent = Color.symAccent.opacity(0.6)
                    for n in loose { if let y = consoleY[n.id] { curve(CGPoint(x: colX[0] + 180, y: ccY + 18), CGPoint(x: colX[2], y: y + 18), dashed: true, color: Color.symDim.opacity(0.6)) } }
                    for o in orchestrators {
                        guard let oy = orchY[o.id] else { continue }
                        for l in links where l.from == o.id {
                            if let ty = teamY[l.to] { curve(CGPoint(x: colX[0] + 180, y: oy + 18), CGPoint(x: colX[1], y: ty + 18), dashed: false, color: accent) }
                            if let cy = consoleY[l.to] { curve(CGPoint(x: colX[0] + 180, y: oy + 18), CGPoint(x: colX[2], y: cy + 18), dashed: false, color: accent) }
                        }
                    }
                    for n in rows {
                        guard let t = n.teamID, let ty = teamY[t], let cy = consoleY[n.id] else { continue }
                        curve(CGPoint(x: colX[1] + 170, y: ty + 18), CGPoint(x: colX[2], y: cy + 18), dashed: false, color: Color(hex: ws.teams.first { $0.id == t }?.colorHex ?? "#888").opacity(0.5))
                    }
                }
                .frame(height: height)

                card(icon: "command", title: "Command center", sub: L("%d only reachable from the bar", loose.count), color: Color.symDim, selected: false)
                    .offset(x: colX[0], y: ccY)
                ForEach(orchestrators) { o in
                    card(icon: "point.3.connected.trianglepath.dotted", title: o.title, sub: L("%d wired", c.orchestratorTargets(o.id).count), color: Color.symAccent, selected: selected == o.id)
                        .offset(x: colX[0], y: orchY[o.id] ?? 0)
                        .onTapGesture { selected = o.id }
                }
                ForEach(shownTeams) { t in
                    let members = consoles.filter { $0.teamID == t.id }
                    card(icon: "circle.fill", title: t.name, sub: Ln(members.count, "%d console", "%d consoles") + " · " + L("%d working", members.filter { status($0.id) == .working }.count),
                         color: Color(hex: t.colorHex), selected: selected == t.id, width: 170)
                        .offset(x: colX[1], y: teamY[t.id] ?? 0)
                        .onTapGesture { selected = t.id }
                }
                ForEach(rows) { n in
                    let st = status(n.id)
                    HStack(spacing: 8) {
                        AgentBadge(choice: AgentCatalog.choice(for: n.terminal), size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText)
                            Text(L(onHold(n.id) ? "On hold" : (Self.bucket(st) == "Idle" ? "At the prompt" : st.label))).font(.system(size: 10)).foregroundStyle(Color.symDim)
                        }
                        Spacer()
                        Circle().fill(Color(nsColor: st.color)).frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 190, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected == n.id ? Color.symAccent : Color.symBorder))
                    .offset(x: colX[2], y: consoleY[n.id] ?? 0)
                    .onTapGesture(count: 2) { goTo(n.id) }
                    .onTapGesture { selected = n.id }
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .padding(.horizontal, 16)
        }
    }

    func card(icon: String, title: String, sub: String, color: Color, selected: Bool, width: CGFloat = 180) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: icon == "circle.fill" ? 7 : 12)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText).lineLimit(1)
                Text(L(sub)).font(.system(size: 10)).foregroundStyle(Color.symDim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 38)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.symAccent : Color.symBorder))
    }

    var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.filters.dropFirst()), id: \.self) { f in
                HStack(spacing: 4) { Circle().fill(Self.color(f)).frame(width: 6, height: 6); Text(L(f)) }
            }
            Text(L("- - - Command bar only"))
            Spacer()
            Text(L("Click to inspect · Double-click to jump there"))
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.symDim)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: 오른쪽 상세

    @ViewBuilder var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let id = selected, let n = model.node(id), n.kind == .terminal {
                consoleDetail(n)
            } else if let id = selected, let t = ws.teams.first(where: { $0.id == id }) {
                teamDetail(t)
            } else {
                overview
            }
            Spacer()
        }
        .padding(18)
    }

    /// 아무것도 고르지 않았을 때: 원본처럼 Fleet(상태별 수)·Structure(오케스트레이터·팀·콘솔·켜진 루프) 두 카드.
    var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            overviewCard(L("Fleet"), Self.filters.dropFirst().map { f in
                (f, Self.color(f), consoles.filter { Self.bucket(status($0.id)) == f }.count)
            })
            overviewCard(L("Structure"), [
                ("Orchestrators", nil, orchestrators.count),
                ("Teams", nil, teams.count),
                ("Consoles", nil, consoles.count),
                ("Active loops", nil, ws.loops.filter(\.enabled).count),
            ])
            Text(L("Select a console, a team or an orchestrator to see what it is doing and act on it."))
                .font(.system(size: 12)).foregroundStyle(Color.symDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    func overviewCard(_ title: String, _ rows: [(String, Color?, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symDim)
            VStack(spacing: 10) {
                ForEach(rows, id: \.0) { r in
                    HStack(spacing: 8) {
                        if let c = r.1 { Circle().fill(c).frame(width: 7, height: 7) }
                        Text(L(r.0)).foregroundStyle(Color.symText)
                        Spacer()
                        Text("\(r.2)").font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(r.2 == 0 ? Color.symDim : Color.symText)
                    }
                    .font(.system(size: 13))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.symBorder))
        }
    }

    func teamDetail(_ t: Team) -> some View {
        let members = consoles.filter { $0.teamID == t.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: t.colorHex)).frame(width: 10, height: 10)
                Text(t.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.symText)
            }
            Text(Ln(members.count, "%d console", "%d consoles") + " · " + L("%d working", members.filter { status($0.id) == .working }.count)).font(.system(size: 12)).foregroundStyle(Color.symDim)
            Button { showTeam(t.id) } label: { Label(L("Show this team on the board"), systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: true))
        }
    }

    func consoleDetail(_ n: BoardNode) -> some View {
        let choice = AgentCatalog.choice(for: n.terminal)
        let st = status(n.id)
        let since = model.sessions.statusSince[n.id] ?? Date()
        let paused = model.sessions.session(for: n.id)?.paused ?? false
        let orchs = orchestrators(of: n)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentBadge(choice: choice, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.symText)
                    Text(choice.name).font(.system(size: 12)).foregroundStyle(Color.symDim)
                }
            }
            Button { goTo(n.id) } label: { Label(L("Go to the console"), systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(prominent: true))
            HStack(spacing: 8) {
                Button { _ = model.sessions.session(for: n.id)?.signal(paused ? SIGCONT : SIGSTOP) } label: {
                    Label(L(paused ? "Resume" : "Pause"), systemImage: paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                Button { model.sessions.session(for: n.id)?.terminate() } label: {
                    Label(L("Kill"), systemImage: "xmark.circle").frame(maxWidth: .infinity).foregroundStyle(Color.symAccent)
                }
                .buttonStyle(PillButtonStyle())
            }
            Text(L("Now")).font(.system(size: 11)).foregroundStyle(Color.symDim)
            VStack(spacing: 8) {
                HStack {
                    Circle().fill(Color(nsColor: st.color)).frame(width: 6, height: 6)
                    Text(L("Status")).foregroundStyle(Color.symDim)
                    Spacer()
                    Text(L(paused ? "Paused" : (onHold(n.id) ? "On hold" : st.label))).foregroundStyle(Color(nsColor: st.color))
                }
                HStack {
                    Text(L("For")).foregroundStyle(Color.symDim)
                    Spacer()
                    Text(Self.duration(Date().timeIntervalSince(since))).font(.system(.body, design: .monospaced)).foregroundStyle(Color.symText)
                }
            }
            .font(.system(size: 13))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
            Text(L("Belongs to")).font(.system(size: 11)).foregroundStyle(Color.symDim)
            if let tn = teamName(n) { belongs(icon: "circle.fill", title: tn, sub: "Group") }
            if orchs.isEmpty { belongs(icon: "command", title: "Command center", sub: "Not wired to any orchestrator") }
            ForEach(orchs) { o in belongs(icon: "point.3.connected.trianglepath.dotted", title: o.title, sub: "Orchestrator") }
        }
    }

    func belongs(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: icon == "circle.fill" ? 7 : 12)).foregroundStyle(Color.symDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                Text(L(sub)).font(.system(size: 11)).foregroundStyle(Color.symDim)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    func goTo(_ id: UUID) {
        chrome.missionOpen = false
        c.focus(nodeID: id)
    }

    func showTeam(_ id: UUID) {
        chrome.missionOpen = false
        c.zoomToTeam(id)
    }
}
