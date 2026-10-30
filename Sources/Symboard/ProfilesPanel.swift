import AppKit
import SwiftUI
import SymboardCore

/// 계정 프로필: 같은 CLI 를 다른 설정 폴더(다른 계정)로 띄운다.
/// claude 는 CLAUDE_CONFIG_DIR, codex 는 CODEX_HOME 으로 설정 폴더를 바꾼다(LaunchPlanner).
@MainActor
final class ProfilesModel: ObservableObject {
    unowned let model: AppModel
    @Published var profiles: [AccountProfile] = []

    init(model: AppModel) {
        self.model = model
        profiles = model.state.profiles
    }

    func add(name: String, agent: AgentKind, folder: String) {
        let dir = (folder as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        model.mutateState { $0.profiles.append(AccountProfile(name: name, agent: agent, configDir: dir)) }
        profiles = model.state.profiles
    }

    func active(for agent: AgentKind) -> UUID? { model.state.activeProfiles?[agent.rawValue] }

    func setActive(_ id: UUID?, for agent: AgentKind) {
        model.mutateState { s in
            var m = s.activeProfiles ?? [:]
            m[agent.rawValue] = id
            s.activeProfiles = m
        }
        objectWillChange.send()
    }

    func rename(_ id: UUID, to name: String) {
        model.mutateState { s in if let i = s.profiles.firstIndex(where: { $0.id == id }) { s.profiles[i].name = name } }
        profiles = model.state.profiles
    }

    /// 새 계정: 앱 데이터 폴더 아래 빈 설정 폴더를 만든다. 첫 실행에서 CLI 가 로그인을 묻는다.
    @discardableResult
    func connect(name: String, agent: AgentKind) -> AccountProfile {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce("") { $0 + String($1) }
        let dir = model.store.directory.appendingPathComponent("profiles/\(agent.rawValue)-\(slug)-\(UUID().uuidString.prefix(4))").path
        add(name: name, agent: agent, folder: dir)
        return model.state.profiles.last!
    }

    /// 지금 기본 로그인(기본 설정 폴더)을 이름 붙은 프로필로.
    func saveCurrent(agent: AgentKind) {
        let dir = agent == .codex ? NSHomeDirectory() + "/.codex" : NSHomeDirectory() + "/.claude"
        model.mutateState { $0.profiles.append(AccountProfile(name: "Saved sign-in", agent: agent, configDir: dir)) }
        profiles = model.state.profiles
    }

    func remove(_ id: UUID) {
        model.mutateState { s in
            for (k, v) in s.activeProfiles ?? [:] where v == id { s.activeProfiles?[k] = nil }
        }
        model.mutateState { $0.profiles.removeAll { $0.id == id } }
        profiles = model.state.profiles
    }

    func addWithDialog() {
        let alert = NSAlert()
        alert.messageText = "New Account Profile"
        alert.informativeText = "A profile runs a CLI with its own settings folder, so you can be logged in to a second account at the same time. The first launch asks you to log in."
        let name = NSTextField(string: "Work")
        let agentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        agentPopup.addItems(withTitles: ["Claude Code", "Codex"])
        let folder = NSTextField(string: "~/.symboard-profiles/claude-work")
        agentPopup.target = nil
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L("Name")), name],
            [NSTextField(labelWithString: L("CLI")), agentPopup],
            [NSTextField(labelWithString: L("Settings folder")), folder],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 420, height: 90)
        folder.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = grid
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard Prompt.run(alert, focus: name) == .alertFirstButtonReturn, !name.stringValue.isEmpty, !folder.stringValue.isEmpty else { return }
        add(name: name.stringValue, agent: agentPopup.indexOfSelectedItem == 0 ? .claude : .codex, folder: folder.stringValue)
    }
}

struct ProfilesPanelView: View {
    @ObservedObject var profiles: ProfilesModel
    var launch: (AccountProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Account Profiles")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(L("Add")) { profiles.addWithDialog() }.controlSize(.small).axName("Add")
            }
            Text(L("Each profile gives a CLI its own settings folder (Claude Code: CLAUDE_CONFIG_DIR, Codex: CODEX_HOME). Pick a profile in the New Terminal dialog."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            List(profiles.profiles) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(p.name) - \(p.agent.displayName)").font(.system(size: 12, weight: .medium))
                        Text(p.configDir).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(L("Launch")) { launch(p) }.controlSize(.small).axName("Launch")
                    Button { profiles.remove(p.id) } label: { Image(systemName: "trash") }.buttonStyle(.plainHit).tip(L("Delete profile"))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(8)
    }
}
