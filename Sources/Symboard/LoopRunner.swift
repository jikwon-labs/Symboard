import AppKit
import SwiftUI
import SymboardCore

/// 루프 규칙을 1초마다 확인해서 정해진 문장을 노드에 보낸다.
@MainActor
final class LoopRunner: ObservableObject {
    unowned let model: AppModel
    private var runtimes: [UUID: LoopRuntime] = [:]
    private var observer: NSObjectProtocol?
    /// 패널에 보여 줄 줄. 1초마다 갱신.
    @Published private(set) var rows: [LoopRow] = []

    struct LoopRow: Identifiable, Equatable {
        var id: UUID
        var nodeTitle: String
        var message: String
        var trigger: String
        var goal: String
        var enabled: Bool
        var runs: String
        var note: String
    }

    private var notes: [UUID: String] = [:]

    init(model: AppModel) {
        self.model = model
        observer = NotificationCenter.default.addObserver(forName: .statusTick, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: 규칙 편집

    func add(_ rule: LoopRule) {
        guard let wsID = model.workspaceID(containing: rule.nodeID) else { return }
        model.mutateWorkspace(wsID) { $0.loops.append(rule) }
        runtimes[rule.id] = LoopRuntime()
        refreshRows()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        mutate(id) { r in
            r.enabled = on
            if on { r.runCount = 0 }
        }
        if on { runtimes[id] = LoopRuntime(); notes[id] = nil }
        refreshRows()
    }

    func remove(_ id: UUID) {
        for ws in model.state.workspaces where ws.loops.contains(where: { $0.id == id }) {
            model.mutateWorkspace(ws.id) { $0.loops.removeAll { $0.id == id } }
        }
        runtimes[id] = nil
        refreshRows()
    }

    private func mutate(_ id: UUID, _ body: (inout LoopRule) -> Void) {
        for ws in model.state.workspaces {
            if let i = ws.loops.firstIndex(where: { $0.id == id }) {
                model.mutateWorkspace(ws.id) { body(&$0.loops[i]) }
                return
            }
        }
    }

    // MARK: 실행

    private func tick() {
        let now = Date()
        for ws in model.state.workspaces {
            for rule in ws.loops {
                guard let session = model.sessions.session(for: rule.nodeID) else { continue }
                if session.outputListeners[rule.id] == nil {
                    session.outputListeners[rule.id] = { [weak self] text in
                        guard let self, var rt = self.runtimes[rule.id] else { return }
                        rt.pending += text
                        if rt.pending.count > 8000 { rt.pending = String(rt.pending.suffix(4000)) }
                        self.runtimes[rule.id] = rt
                    }
                }
                guard rule.enabled else { continue }
                var rt = runtimes[rule.id] ?? LoopRuntime(startedAt: now)
                let decision = LoopEngine.evaluate(rule: rule, runtime: &rt, now: now,
                                                   idleSeconds: session.idleSeconds(now: now),
                                                   lastOutputAt: session.tracker.lastOutput)
                runtimes[rule.id] = rt
                switch decision {
                case .none:
                    break
                case .fire:
                    guard session.running else { continue }
                    session.sendText(rule.message, submit: true)
                    mutate(rule.id) { $0.runCount += 1 }
                    notes[rule.id] = "sent at \(Self.time(now))"
                case .stop(let reason):
                    mutate(rule.id) { $0.enabled = false }
                    notes[rule.id] = reason == "goal" ? "goal reached at \(Self.time(now))" : "stopped: \(reason)"
                }
            }
        }
        refreshRows()
    }

    func refreshRows() {
        var out: [LoopRow] = []
        for ws in model.state.workspaces {
            for r in ws.loops {
                let title = ws.nodes.first { $0.id == r.nodeID }?.title ?? "?"
                out.append(LoopRow(id: r.id, nodeTitle: title, message: r.message, trigger: Self.describe(r.trigger),
                                   goal: r.goal, enabled: r.enabled, runs: "\(r.runCount)/\(r.maxRuns)", note: notes[r.id] ?? ""))
            }
        }
        if out != rows { rows = out }
    }

    static func describe(_ t: LoopTrigger) -> String {
        switch t {
        case .interval(let s): return "every \(Int(s))s"
        case .idle(let s): return "when idle \(Int(s))s"
        case .output(let p): return "when output has \"\(p)\""
        }
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: 새 루프 창

@MainActor
enum LoopDialog {
    static func run(nodes: [BoardNode], preselect: UUID?) -> LoopRule? {
        let terminals = nodes.filter { $0.kind == .terminal }
        guard !terminals.isEmpty else {
            let a = NSAlert()
            a.messageText = "No terminal nodes in this workspace."
            a.runModal()
            return nil
        }
        let alert = NSAlert()
        alert.messageText = "New Loop"
        alert.informativeText = "Automatically type a message into a node. The loop turns itself off when the goal text appears in the output."
        let nodePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        nodePopup.addItems(withTitles: terminals.map { $0.role.map { r in "\(r) - " } ?? "" }.enumerated().map { "\($0.element)\(terminals[$0.offset].title)" })
        if let pre = preselect, let i = terminals.firstIndex(where: { $0.id == pre }) { nodePopup.selectItem(at: i) }
        let message = NSTextField(string: "continue")
        let triggerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        triggerPopup.addItems(withTitles: ["Every N seconds", "When idle for N seconds", "When output contains text"])
        triggerPopup.selectItem(at: 1)
        let value = NSTextField(string: "30")
        value.placeholderString = "seconds, or text to watch for"
        let goal = NSTextField(string: "")
        goal.placeholderString = "e.g. ALL TESTS PASSED (optional)"
        let maxRuns = NSTextField(string: "20")
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Node"), nodePopup],
            [NSTextField(labelWithString: "Message"), message],
            [NSTextField(labelWithString: "Start when"), triggerPopup],
            [NSTextField(labelWithString: "Value"), value],
            [NSTextField(labelWithString: "Goal text"), goal],
            [NSTextField(labelWithString: "Max runs"), maxRuns],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 420, height: 200)
        for f in [message, value, goal] { f.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        maxRuns.widthAnchor.constraint(equalToConstant: 60).isActive = true
        alert.accessoryView = grid
        alert.addButton(withTitle: "Start Loop")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let msg = message.stringValue
        guard !msg.isEmpty else { return nil }
        let trigger: LoopTrigger
        switch triggerPopup.indexOfSelectedItem {
        case 0: trigger = .interval(seconds: max(5, value.doubleValue))
        case 1: trigger = .idle(seconds: max(3, value.doubleValue))
        default:
            guard !value.stringValue.isEmpty else { return nil }
            trigger = .output(pattern: value.stringValue)
        }
        return LoopRule(nodeID: terminals[nodePopup.indexOfSelectedItem].id, message: msg, trigger: trigger,
                        goal: goal.stringValue.trimmingCharacters(in: .whitespaces), maxRuns: max(1, maxRuns.integerValue))
    }
}

// MARK: 패널

struct LoopPanelView: View {
    @ObservedObject var runner: LoopRunner
    var newLoop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Loops").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("New Loop", action: newLoop).controlSize(.small)
            }
            .padding(10)
            if runner.rows.isEmpty {
                Text("No loops. A loop types a message into a node on a schedule, when it goes idle, or when some text appears.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10)
                Spacer()
            } else {
                List(runner.rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Toggle("", isOn: Binding(get: { row.enabled }, set: { runner.setEnabled(row.id, $0) }))
                                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            Text(row.nodeTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Button { runner.remove(row.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }
                        Text("\"\(row.message)\" \(row.trigger)").font(.system(size: 11)).lineLimit(2)
                        HStack(spacing: 6) {
                            if !row.goal.isEmpty { Text("goal: \(row.goal)") }
                            Text("runs \(row.runs)")
                            if !row.note.isEmpty { Text(row.note) }
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
