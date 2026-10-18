import AppKit
import SwiftUI
import SymboardCore

/// 컴포저 카드의 상태. 디버그 통로에서도 바꿀 수 있게 따로 둔다.
@MainActor
final class ComposerState: ObservableObject {
    struct Role: Hashable {
        var name: String
        var colorHex: String
    }

    static let roles: [Role] = [
        Role(name: "Frontend", colorHex: "#E8A15A"), Role(name: "Backend", colorHex: "#B48CF2"),
        Role(name: "Testers", colorHex: "#6FCF97"), Role(name: "Reviewers", colorHex: "#E9C46A"),
        Role(name: "Design", colorHex: "#F28AB2"), Role(name: "Docs", colorHex: "#56C2C9"),
        Role(name: "Security", colorHex: "#E86A5A"), Role(name: "General", colorHex: "#9A938C"),
    ]

    @Published var open = false
    @Published var teamName = "Team"
    @Published var role = roles.last!
    /// 타일마다 CLI id.
    @Published var tiles: [String] = Array(repeating: "claude", count: 4)
    /// 마지막으로 누른 Fill all 값. 개수를 늘릴 때 새 타일이 이 값을 따른다.
    private(set) var fillChoice: String?

    var count: Int { tiles.count }

    func reset(default id: String) {
        teamName = "Team"
        role = Self.roles.last!
        tiles = Array(repeating: id, count: 4)
        fillChoice = nil
    }

    func setCount(_ n: Int) {
        tiles = Composer.resize(tiles: tiles, to: n, fill: fillChoice, fallback: AgentCatalog.shared.lastChoiceID)
    }

    func fillAll(_ id: String) {
        fillChoice = id
        tiles = Array(repeating: id, count: count)
    }

    func pick(role r: Role) {
        // 이름을 손대지 않았으면 역할 이름을 팀 이름으로.
        if teamName == role.name || teamName == "Team" { teamName = r.name }
        role = r
    }

    /// 타일 하나를 다음 CLI 로 돌린다.
    func cycle(_ i: Int, among ids: [String]) {
        guard i < tiles.count, !ids.isEmpty else { return }
        let cur = ids.firstIndex(of: tiles[i]) ?? -1
        tiles[i] = ids[(cur + 1) % ids.count]
    }
}

struct ComposerCard: View {
    @ObservedObject var state: ComposerState
    @ObservedObject var catalog = AgentCatalog.shared
    var spawn: () -> Void

    var roleColor: Color { Color(hex: state.role.colorHex) }
    var choices: [AgentChoice] { catalog.available }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(roleColor).frame(width: 9, height: 9)
                TextField("Team name", text: $state.teamName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.symText)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))

            FlowRows(items: ComposerState.roles, perRow: 4) { r in
                Button { state.pick(role: r) } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: r.colorHex)).frame(width: 6, height: 6)
                        Text(r.name).font(.system(size: 12))
                    }
                    .foregroundStyle(state.role == r ? Color.symText : Color.symDim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(state.role == r ? Color.white.opacity(0.08) : .clear))
                    .overlay(Capsule().stroke(state.role == r ? Color.symBorder : .clear))
                }
                .buttonStyle(.plainHit).axName("Role \(r.name)")
            }

            Divider().overlay(Color.symBorder)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(state.tiles.enumerated()), id: \.offset) { i, id in
                    let choice = AgentCatalog.choice(id: id) ?? AgentCatalog.known.last!
                    Button { state.cycle(i, among: choices.map(\.id)) } label: {
                        VStack(spacing: 5) {
                            AgentBadge(choice: choice, size: 28)
                            Text(choice.name.components(separatedBy: " ").first ?? choice.name)
                                .font(.system(size: 11)).foregroundStyle(Color.symDim).lineLimit(1)
                        }
                        .frame(width: 78, height: 70)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: choice.colorHex).opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: choice.colorHex).opacity(0.35)))
                    }
                    .buttonStyle(.plainHit)
                    .tip("Agent \(i + 1): \(choice.name). Click to switch this one to another CLI")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: state.tiles.count)

            HStack(spacing: 6) {
                Text("Fill all").font(.system(size: 12)).foregroundStyle(Color.symDim)
                ForEach(choices) { c in
                    Button { state.fillAll(c.id) } label: { AgentBadge(choice: c, size: 24) }
                        .buttonStyle(.plainHit)
                        .overlay(Circle().stroke(state.tiles.allSatisfy { $0 == c.id } ? Color.symAccent : .clear, lineWidth: 1.5).padding(-3))
                        .tip("Fill all with \(c.name)")
                }
            }

            Divider().overlay(Color.symBorder)

            HStack {
                HStack(spacing: 10) {
                    Button { state.setCount(state.count - 1) } label: { Image(systemName: "minus").frame(width: 22, height: 22) }.tip("Fewer agents")
                    Text("\(state.count)").font(.system(size: 14, weight: .semibold, design: .monospaced)).frame(minWidth: 22)
                    Button { state.setCount(state.count + 1) } label: { Image(systemName: "plus").frame(width: 22, height: 22) }.tip("More agents")
                }
                .buttonStyle(.plainHit)
                .foregroundStyle(Color.symText)
                Spacer()
                Button("Spawn \(state.count)", action: spawn)
                    .buttonStyle(SpawnButtonStyle(color: roleColor)).axName("Spawn \(state.count)")
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 368)
        .background(Color.symSurface)
    }
}

struct SpawnButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.75 : 0.95)))
    }
}

/// 고정 개수씩 줄을 나눠 늘어놓는다.
struct FlowRows<Item: Hashable, Content: View>: View {
    var items: [Item]
    var perRow: Int
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<((items.count + perRow - 1) / perRow), id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(items[(r * perRow)..<min(items.count, (r + 1) * perRow)], id: \.self) { content($0) }
                }
            }
        }
    }
}
