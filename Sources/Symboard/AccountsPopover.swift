import AppKit
import SwiftUI
import SymboardCore

/// 위쪽 계정 버튼 팝오버: CLI 별 로그인 프로필을 고르고, 새 계정을 연결한다.
struct AccountsPopover: View {
    @ObservedObject var profiles: ProfilesModel
    let c: MainWindowController
    @State private var agent: AgentKind = .claude
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""

    var list: [AccountProfile] { profiles.profiles.filter { $0.agent == agent } }
    var activeID: UUID? { profiles.active(for: agent) }
    var cli: String { agent == .codex ? "Codex" : "Claude" }

    var body: some View {
        let _ = profiles.model.state.activeProfiles
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("accounts").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symText)
                ForEach([AgentKind.claude, .codex], id: \.self) { a in
                    Button { agent = a } label: { AgentBadge(choice: AgentCatalog.choice(for: TerminalSpec(agent: a, cwd: "/")), size: 22) }.tip("Show \(a.rawValue) accounts")
                        .buttonStyle(.plainHit).opacity(agent == a ? 1 : 0.4)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: "#E9C46A"))
                Text("\(cli) can keep its sign-in in the macOS Keychain, which a separate settings folder does not fully isolate. After switching, check the account inside the console (for example with /status).")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: "#E9C46A").opacity(0.9))
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#E9C46A").opacity(0.08)))
            row(initials: nil, name: "Your sign-in", sub: "Used by new \(cli) consoles", active: activeID == nil,
                use: { profiles.setActive(nil, for: agent) }, open: { c.openProfileConsole(nil, agent: agent) }, edit: nil, delete: nil)
            ForEach(list) { p in
                if renaming == p.id {
                    HStack {
                        TextField("", text: $renameText).modifier(FieldLook()).onSubmit { profiles.rename(p.id, to: renameText); renaming = nil }
                        Button("Save") { profiles.rename(p.id, to: renameText); renaming = nil }.buttonStyle(PillButtonStyle(prominent: true)).axName("Save")
                    }
                } else {
                    row(initials: Self.initials(p.name), name: p.name, sub: activeID == p.id ? "Used by new \(cli) consoles" : "Ready when you need it", active: activeID == p.id,
                        use: { profiles.setActive(p.id, for: agent) }, open: { c.openProfileConsole(p, agent: agent) },
                        edit: { renaming = p.id; renameText = p.name }, delete: { profiles.remove(p.id) })
                }
            }
            Button { profiles.saveCurrent(agent: agent) } label: {
                HStack { Text("Save your current sign-in as a profile").font(.system(size: 12)); Spacer(); Image(systemName: "plus") }
                    .foregroundStyle(Color.symDim).padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            Divider().overlay(Color.symBorder)
            Text("CONNECT ANOTHER ACCOUNT").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            HStack(spacing: 6) {
                TextField("", text: $newName, prompt: Text("e.g. Work account").foregroundColor(Color.symDim)).modifier(FieldLook())
                    .onSubmit(connect)
                Button(action: connect) { Label("Connect", systemImage: "plus") }.buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Opens a \(cli) console on the board with its own settings folder so you can sign in there.")
                .font(.system(size: 10)).foregroundStyle(Color.symDim)
        }
        .padding(14)
        .frame(width: 400)
        .background(Color.symSurface)
    }

    func connect() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let p = profiles.connect(name: n, agent: agent)
        newName = ""
        c.openProfileConsole(p, agent: agent)
    }

    static func initials(_ s: String) -> String {
        let words = s.split(separator: " ")
        return String((words.first?.prefix(1) ?? "") + (words.dropFirst().first?.prefix(1) ?? "")).uppercased()
    }

    func row(initials: String?, name: String, sub: String, active: Bool, use: @escaping () -> Void, open: @escaping () -> Void,
             edit: (() -> Void)?, delete: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Group {
                if let initials { Text(initials).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.symAccent) }
                else { Image(systemName: "person.crop.circle").foregroundStyle(Color.symText) }
            }
            .frame(width: 30, height: 30).background(Circle().fill(Color.symAccent.opacity(initials == nil ? 0 : 0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.symDim)
            }
            Spacer()
            if active {
                HStack(spacing: 4) { Circle().fill(Color.symAccent).frame(width: 5, height: 5); Text("ACTIVE") }
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color.symAccent)
            } else {
                Button("Use", action: use).buttonStyle(PillButtonStyle(prominent: true))
            }
            Button(action: open) { Image(systemName: "terminal") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Open a console with this account")
            if let edit { Button(action: edit) { Image(systemName: "pencil") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Rename") }
            if let delete { Button(action: delete) { Image(systemName: "xmark") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Remove profile") }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.symAccent.opacity(0.06) : Color.symRaised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.symAccent.opacity(0.5) : .clear))
    }
}
