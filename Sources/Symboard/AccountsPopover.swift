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
    @State private var note: String?

    var list: [AccountProfile] { profiles.profiles.filter { $0.agent == agent } }
    var activeID: UUID? { profiles.active(for: agent) }
    var cli: String { agent == .codex ? "Codex" : "Claude" }

    var body: some View {
        let _ = profiles.model.state.activeProfiles
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("accounts")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symText)
                // 원본처럼 CLI 다섯을 늘어놓는다. 계정 프로필은 claude·codex 만 다룬다.
                CLIIconStrip(ids: ["claude", "codex", "gemini", "cursor", "qwen"], supported: ["claude", "codex"],
                             selected: agent == .codex ? "codex" : "claude", feature: "account profiles",
                             onPick: { ch in agent = ch.agent; note = nil }, onNote: { note = $0 })
                Spacer()
                Button { c.chrome.accountsOpen = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("Close"))
            }
            if let note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color.symDim)
                    Text(note).font(.system(size: 11)).foregroundStyle(Color.symText.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { self.note = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Dismiss note")
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: "#E9C46A"))
                Text(L("%@ can keep its sign-in in the macOS Keychain, which a separate settings folder does not fully isolate. After switching, check the account inside the console (for example with /status).", cli))
                    .font(.system(size: 11)).foregroundStyle(Color(hex: "#E9C46A").opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#E9C46A").opacity(0.08)))
            row(initials: nil, name: L("Your sign-in"), sub: L("Used by new %@ consoles", cli), active: activeID == nil,
                use: { profiles.setActive(nil, for: agent) }, open: { c.openProfileConsole(nil, agent: agent) }, edit: nil, delete: nil)
            ForEach(list) { p in
                if renaming == p.id {
                    HStack {
                        TextField("", text: $renameText).modifier(FieldLook()).onSubmit { profiles.rename(p.id, to: renameText); renaming = nil }
                        Button(L("Save")) { profiles.rename(p.id, to: renameText); renaming = nil }.buttonStyle(PillButtonStyle(prominent: true)).axName("Save")
                    }
                } else {
                    row(initials: Self.initials(p.name), name: p.name, sub: activeID == p.id ? L("Used by new %@ consoles", cli) : L("Ready when you need it"), active: activeID == p.id,
                        use: { profiles.setActive(p.id, for: agent) }, open: { c.openProfileConsole(p, agent: agent) },
                        edit: { renaming = p.id; renameText = p.name }, delete: { profiles.remove(p.id) })
                }
            }
            Button { profiles.saveCurrent(agent: agent) } label: {
                HStack { Text(L("Save your current sign-in as a profile")).font(.system(size: 12)); Spacer(); Image(systemName: "plus") }
                    .foregroundStyle(Color.symDim).padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(HoverRowStyle())
            Divider().overlay(Color.symBorder)
            Text(L("CONNECT ANOTHER ACCOUNT")).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            HStack(spacing: 6) {
                TextField("", text: $newName, prompt: Text(L("e.g. Work account")).foregroundColor(Color.symDim)).modifier(FieldLook())
                    .autoFocus(profiles.profiles.isEmpty)
                    .onSubmit(connect)
                Button(action: connect) { Label(L("Connect"), systemImage: "plus") }.buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(L("Opens a %@ console on the board with its own settings folder so you can sign in there.", cli))
                .font(.system(size: 10)).foregroundStyle(Color.symDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 4) { Circle().fill(Color.symAccent).frame(width: 5, height: 5); Text(L("ACTIVE")) }
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color.symAccent)
            } else {
                Button(L("Use"), action: use).buttonStyle(PillButtonStyle(prominent: true))
            }
            Button(action: open) { Image(systemName: "terminal") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("Open a console with this account"))
            if let edit { Button(action: edit) { Image(systemName: "pencil") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("Rename")) }
            if let delete { Button(action: delete) { Image(systemName: "xmark") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip(L("Remove profile")) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.symAccent.opacity(0.06) : Color.symRaised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.symAccent.opacity(0.5) : .clear))
    }
}
