import AppKit
import SymboardCore

/// 새 터미널 노드에서 실행할 CLI 를 고르는 창.
@MainActor
enum NewTerminalDialog {
    static var lastCwd: String {
        get { Prefs.shared.string("lastCwd") ?? NSHomeDirectory() }
        set { Prefs.shared.set(newValue, for: "lastCwd") }
    }

    static func run(profiles: [AccountProfile]) -> TerminalSpec? {
        let alert = NSAlert()
        alert.messageText = "New Terminal"
        alert.informativeText = "Choose what to run in the new node."

        let agentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let agents: [AgentKind] = [.claude, .codex, .shell, .custom]
        agentPopup.addItems(withTitles: agents.map(\.displayName))
        let exeField = NSTextField(string: "")
        exeField.placeholderString = "/path/to/executable (Custom only)"
        let argsField = NSTextField(string: "")
        argsField.placeholderString = "extra arguments (optional)"
        let cwdField = NSTextField(string: lastCwd)
        let chooseButton = ClosureButton(title: "Choose...") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = URL(fileURLWithPath: cwdField.stringValue)
            if panel.runModal() == .OK, let url = panel.url { cwdField.stringValue = url.path }
        }
        let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        profilePopup.addItem(withTitle: "Default account")
        for p in profiles { profilePopup.addItem(withTitle: "\(p.name) (\(p.agent.displayName))") }

        let grid = NSGridView(views: [
            [label("Program"), agentPopup],
            [label("Executable"), exeField],
            [label("Arguments"), argsField],
            [label("Folder"), row(cwdField, chooseButton)],
            [label("Profile"), profilePopup],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 440, height: 170)
        exeField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        cwdField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        alert.accessoryView = grid
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let agent = agents[agentPopup.indexOfSelectedItem]
        let cwd = (cwdField.stringValue as NSString).expandingTildeInPath
        lastCwd = cwd
        let exe = (exeField.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if agent == .custom && exe.isEmpty { return nil }
        let profileIndex = profilePopup.indexOfSelectedItem - 1
        let profile = profileIndex >= 0 ? profiles[profileIndex] : nil
        let args = ArgumentSplitter.split(argsField.stringValue)
        return TerminalSpec(agent: agent, executable: agent == .custom ? exe : nil, extraArgs: args, cwd: cwd,
                            profileID: profile?.agent == agent ? profile?.id : nil)
    }

    private static func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private static func row(_ views: NSView...) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 6
        return s
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
