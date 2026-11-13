import AppKit
import SwiftUI
import SymboardCore

/// 새 터미널 노드에서 실행할 CLI 를 고르는 창.
/// 고른 프로그램에 필요한 칸만 보인다: 실행 파일은 다른 프로그램일 때만, 추가 옵션은 셸이 아닐 때만(셸은 인자를 쓰지 않는다).
/// 계정은 묻지 않는다. 새 콘솔은 그 CLI 에 지금 고른 프로필로 열린다(`addTerminal` 의 applyActiveProfile).
/// 키보드: ← → 로 프로그램을 고르고(글 칸에 커서가 없을 때), Enter 로 바로 만든다, Esc 는 취소.
@MainActor
enum NewTerminalDialog {
    static var lastCwd: String {
        get { Prefs.shared.string("lastCwd") ?? NSHomeDirectory() }
        set { Prefs.shared.set(newValue, for: "lastCwd") }
    }

    static func run() -> TerminalSpec? {
        let state = NewTerminalState(cwd: lastCwd)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("New Terminal")
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Theme.surface
        let closer = ModalCloser()
        panel.delegate = closer
        let view = NewTerminalView(state: state,
                                   cancel: { NSApp.stopModal(withCode: .cancel) },
                                   create: { NSApp.stopModal(withCode: .OK) })
        panel.contentView = NSHostingView(rootView: view.localized())
        panel.center()

        // SwiftUI 단추 단축키는 글 칸에 커서가 있으면 Enter 를 글 칸이 먼저 먹는다. 창 단위로 키를 먼저 받는다.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            MainActor.assumeIsolated { handleKey(event, panel: panel, state: state) ? nil : event }
        }
        // 처음엔 글 칸에 커서를 두지 않는다(그래야 ← → 가 바로 프로그램을 고른다).
        panel.initialFirstResponder = nil
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        let response = NSApp.runModal(for: panel)
        if let monitor { NSEvent.removeMonitor(monitor) }
        panel.delegate = nil
        panel.orderOut(nil)
        guard response == .OK, state.canCreate else { return nil }

        let agent = state.agent
        let cwd = (state.cwd.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        lastCwd = cwd
        let exe = (state.executable.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        let args = agent == .shell ? [] : ArgumentSplitter.split(state.arguments)
        var spec = TerminalSpec(agent: agent, executable: agent == .custom ? exe : nil, extraArgs: args, cwd: cwd)
        if agent == .claude, state.ceo { spec.crew = Crew.ceo.rawValue }
        return spec
    }

    /// 처리했으면 true(키를 삼킨다).
    private static func handleKey(_ event: NSEvent, panel: NSPanel?, state: NewTerminalState) -> Bool {
        guard let panel, event.window === panel else { return false }   // 폴더 고르기 창 등은 건드리지 않는다
        let editor = panel.firstResponder as? NSTextView
        if editor?.hasMarkedText() == true { return false }            // 한글 조합 중 Enter 는 조합 끝내기
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36, 76:   // Return, 숫자판 Enter
            guard mods.isEmpty else { return false }
            if state.canCreate { NSApp.stopModal(withCode: .OK) } else { state.focusRequest += 1 }
            return true
        case 53:       // Esc
            NSApp.stopModal(withCode: .cancel)
            return true
        case 123, 124:   // ← →. 글 칸에 커서가 있으면 글자 사이를 움직이게 둔다
            guard editor == nil, mods.isEmpty else { return false }
            state.move(by: event.keyCode == 123 ? -1 : 1)
            return true
        default:
            return false
        }
    }
}

/// 창 닫기 단추도 취소로 친다.
@MainActor
private final class ModalCloser: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApp.stopModal(withCode: .cancel) }
}

@MainActor
final class NewTerminalState: ObservableObject {
    static let agents: [AgentKind] = [.claude, .codex, .shell, .custom]

    @Published var agent: AgentKind = .claude
    @Published var executable = ""
    @Published var arguments = ""
    /// claude 를 CEO 콘솔로 연다(18차).
    @Published var ceo = false
    @Published var cwd: String
    /// 다른 프로그램인데 실행 파일이 비어 Enter 를 누르면 올려서 그 칸에 커서를 보낸다.
    @Published var focusRequest = 0

    init(cwd: String) { self.cwd = (cwd as NSString).abbreviatingWithTildeInPath }

    func move(by step: Int) {
        guard let i = Self.agents.firstIndex(of: agent) else { return }
        agent = Self.agents[min(max(i + step, 0), Self.agents.count - 1)]
    }

    var canCreate: Bool {
        guard !cwd.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return agent != .custom || !executable.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private struct NewTerminalView: View {
    @ObservedObject var state: NewTerminalState
    var cancel: () -> Void
    var create: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case executable, folder, arguments }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("New Terminal")).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.symText)
                Text(L("Opens a new console on the board.")).font(.system(size: 12)).foregroundStyle(Color.symDim)
            }

            section(L("What to run"), note: description(state.agent)) {
                HStack(spacing: 8) {
                    ForEach(NewTerminalState.agents, id: \.self) { a in
                        Button { state.agent = a; focus = nil } label: { AgentCard(agent: a, on: state.agent == a) }
                            .buttonStyle(.plain)
                            .axName(name(a))
                    }
                }
            }

            if state.agent == .claude {
                section(L("Mode"), note: L(state.ceo
                    ? "Takes your work and calls only the roles it needs: planner, designer, frontend, backend, CTO."
                    : "A regular console. It splits work into new consoles by goal.")) {
                    Toggle(L("Open as CEO"), isOn: $state.ceo)
                        .toggleStyle(.switch).controlSize(.small)
                        .font(.system(size: 12)).foregroundStyle(Color.symText)
                        .axName("Open as CEO")
                }
            }

            if state.agent == .custom {
                section(L("Program"), note: L("A command name on your PATH, or the full path to a program.")) {
                    HStack(spacing: 8) {
                        field(L("e.g. %@", "gemini"), text: $state.executable, focused: .executable)
                        Button(L("Find...")) { pickProgram() }.buttonStyle(PillButtonStyle())
                    }
                }
            }

            section(L("Working folder"), note: L("The console starts in this folder.")) {
                HStack(spacing: 8) {
                    field("~/", text: $state.cwd, focused: .folder)
                    Button(L("Change...")) { pickFolder() }.buttonStyle(PillButtonStyle())
                }
            }

            if state.agent != .shell {
                section(L("Extra options") + "  ·  " + L("Optional"),
                        note: L("Added to the end of the command as-is. Usually leave this empty.")) {
                    field(L("e.g. %@", state.agent == .codex ? "--model gpt-5" : "--model opus"), text: $state.arguments, focused: .arguments)
                }
            }

            HStack(spacing: 8) {
                Text(L("← → to choose, Enter to create")).font(.system(size: 11)).foregroundStyle(Color.symDim)
                Spacer()
                Button(L("Cancel"), action: cancel)
                    .buttonStyle(PillButtonStyle())
                Button(L("Create"), action: create)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(!state.canCreate)
                    .opacity(state.canCreate ? 1 : 0.45)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
        .frame(width: 480, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.symSurface)
        .onChange(of: state.focusRequest) { _, _ in focus = .executable }
    }

    private func section<Content: View>(_ title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.symDim)
            content()
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(Color.symDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, focused: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.symText)
            .focused($focus, equals: focused)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.symRaised))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focus == focused ? Color.symAccent.opacity(0.7) : Color.symBorder, lineWidth: 1))
    }

    private func name(_ a: AgentKind) -> String {
        switch a {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .shell: return L("Shell")
        case .custom: return L("Other program")
        }
    }

    private func description(_ a: AgentKind) -> String {
        switch a {
        case .claude: return L("Starts Claude Code. The board shows when it is working or waiting for you.")
        case .codex: return L("Starts the Codex CLI.")
        case .shell: return L("Opens your usual shell (zsh, bash...).")
        case .custom: return L("Runs a program you choose, such as another AI CLI.")
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: (state.cwd as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { state.cwd = (url.path as NSString).abbreviatingWithTildeInPath }
    }

    private func pickProgram() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url { state.executable = url.path }
    }

    fileprivate struct AgentCard: View {
        var agent: AgentKind
        var on: Bool

        var body: some View {
            VStack(spacing: 7) {
                Text(glyph)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: colorHex)))
                Text(title)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.symText : Color.symText.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.symAccent.opacity(0.10) : Color.symRaised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(on ? Color.symAccent : Color.symBorder, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }

        private var title: String {
            switch agent {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .shell: return L("Shell")
            case .custom: return L("Other program")
            }
        }

        private var glyph: String {
            switch agent {
            case .claude: return "C"
            case .codex: return "X"
            case .shell: return ">_"
            case .custom: return "..."
            }
        }

        private var colorHex: String {
            switch agent {
            case .claude: return "#E8704A"
            case .codex: return "#6C7BFF"
            case .shell: return "#9A938C"
            case .custom: return "#5E5852"
            }
        }
    }
}

final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
        self.handler = handler
        target = self
        action = #selector(fire)
    }

    @objc private func fire() { handler?() }
}
