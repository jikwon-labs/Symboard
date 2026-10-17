import AppKit
import SymboardCore

/// 컴포저: 같은 폴더에 노드를 최대 12개까지 한 번에 띄우고 팀으로 묶는다.
@MainActor
enum ComposerDialog {
    struct Result {
        var spec: TerminalSpec
        var count: Int
        var teamName: String
        var roles: [String?]
    }

    static func run() -> Result? {
        let alert = NSAlert()
        alert.messageText = "Composer"
        alert.informativeText = "Launch up to \(Composer.maxNodes) terminals at once as one team."

        let agents: [AgentKind] = [.claude, .codex, .shell]
        let agentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        agentPopup.addItems(withTitles: agents.map(\.displayName))
        let countField = NSTextField(string: "4")
        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = Double(Composer.maxNodes)
        stepper.integerValue = 4
        let stepHandler = StepperBridge(stepper: stepper, field: countField)
        let cwdField = NSTextField(string: NewTerminalDialog.lastCwd)
        let teamField = NSTextField(string: "Team")
        let rolesField = NSTextField(string: "Lead, Coder, Tester, Reviewer")
        rolesField.placeholderString = "comma separated, optional"

        let countRow = NSStackView(views: [countField, stepper])
        countRow.spacing = 4
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Program"), agentPopup],
            [NSTextField(labelWithString: "Count"), countRow],
            [NSTextField(labelWithString: "Folder"), cwdField],
            [NSTextField(labelWithString: "Team name"), teamField],
            [NSTextField(labelWithString: "Roles"), rolesField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 420, height: 160)
        countField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        cwdField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        rolesField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        alert.accessoryView = grid
        alert.addButton(withTitle: "Launch")
        alert.addButton(withTitle: "Cancel")
        let ok = alert.runModal() == .alertFirstButtonReturn
        _ = stepHandler
        guard ok else { return nil }

        let count = max(1, min(Composer.maxNodes, countField.integerValue))
        let cwd = (cwdField.stringValue as NSString).expandingTildeInPath
        NewTerminalDialog.lastCwd = cwd
        let spec = TerminalSpec(agent: agents[agentPopup.indexOfSelectedItem], cwd: cwd)
        let team = teamField.stringValue.trimmingCharacters(in: .whitespaces)
        return Result(spec: spec, count: count, teamName: team.isEmpty ? "Team" : team,
                      roles: Composer.roles(from: rolesField.stringValue, count: count))
    }
}

/// 스테퍼와 숫자 칸을 맞춘다.
final class StepperBridge: NSObject {
    let stepper: NSStepper
    let field: NSTextField

    init(stepper: NSStepper, field: NSTextField) {
        self.stepper = stepper
        self.field = field
        super.init()
        stepper.target = self
        stepper.action = #selector(changed)
    }

    @objc private func changed() { field.integerValue = stepper.integerValue }
}
