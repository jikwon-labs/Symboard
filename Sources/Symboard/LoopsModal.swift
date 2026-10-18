import AppKit
import SwiftUI
import SymboardCore

/// 루프 틀. 이름·설명·지시문은 Symboard 가 직접 쓴 것이다.
struct LoopTemplate: Identifiable {
    var id: String { name }
    var icon: String
    var name: String
    var blurb: String
    var message: String
    var trigger: LoopTrigger

    static let all: [LoopTemplate] = [
        LoopTemplate(icon: "text.bubble", name: "Pulse check", blurb: "A quick pulse from every agent each quarter hour: finished, up next, stuck on.",
                     message: "Give a short status: what you finished, what you will do next, and anything blocking you.", trigger: .interval(seconds: 900)),
        LoopTemplate(icon: "figure.walk", name: "Nudge when quiet", blurb: "A console that has gone silent gets a nudge to pick up the next useful task.",
                     message: "If your current task is done, pick the next most useful task from the plan and continue.", trigger: .idle(seconds: 30)),
        LoopTemplate(icon: "wrench.and.screwdriver", name: "Red-line fixer", blurb: "The moment FAILED shows up in a console, that agent drops everything and repairs it.",
                     message: "The last command failed. Stop, read the error, fix the cause, then run it again.", trigger: .output(pattern: "FAILED")),
        LoopTemplate(icon: "checkmark.shield", name: "Suite watchdog", blurb: "Twice an hour the tests run, and a red result is traced to its real cause.",
                     message: "Run the test suite. If anything fails, fix the underlying cause rather than the test, then re-run.", trigger: .interval(seconds: 1800)),
        LoopTemplate(icon: "arrow.triangle.branch", name: "Save point", blurb: "Every 20 minutes work in progress becomes a local commit. Nothing is pushed.",
                     message: "If you have working changes, commit them with a clear message. Do not push.", trigger: .interval(seconds: 1200)),
        LoopTemplate(icon: "magnifyingglass", name: "Second look", blurb: "Every half hour an agent rereads what changed, hunting bugs and leftovers to tidy.",
                     message: "Review the changes made since the last review for bugs and dead code, and fix what you find.", trigger: .interval(seconds: 1800)),
        LoopTemplate(icon: "clock", name: "Three-line hour", blurb: "On the hour each agent writes exactly three lines: done, doing, blocked.",
                     message: "Write a three-line stand-up: done, doing, blocked.", trigger: .interval(seconds: 3600)),
    ]
}

/// 새 루프·고치기 양식의 상태.
@MainActor
final class LoopDraft: ObservableObject {
    @Published var editing: UUID?
    @Published var name = ""
    @Published var message = ""
    /// "interval", "idle", "output"
    @Published var when = "interval"
    @Published var intervalMinutes = 15.0
    @Published var idleSeconds = 30.0
    @Published var pattern = ""
    @Published var targetAll = true
    @Published var picked: Set<UUID> = []
    @Published var useRuns = false
    @Published var runs = 10
    @Published var useTime = false
    @Published var timeMinutes = 120.0
    @Published var useGoal = false
    /// "text", "command", "agent"
    @Published var goalMode = "agent"
    @Published var goal = ""
    @Published var goalCommand = ""
    @Published var goalAgent = "claude"
    @Published var background = true

    func apply(_ t: LoopTemplate) {
        name = t.name
        message = t.message
        switch t.trigger {
        case .interval(let s): when = "interval"; intervalMinutes = s / 60
        case .idle(let s): when = "idle"; idleSeconds = s
        case .output(let p): when = "output"; pattern = p
        }
    }

    func load(_ r: LoopRule) {
        editing = r.id
        name = r.name ?? ""
        message = r.message
        switch r.trigger {
        case .interval(let s): when = "interval"; intervalMinutes = s / 60
        case .idle(let s): when = "idle"; idleSeconds = s
        case .output(let p): when = "output"; pattern = p
        }
        targetAll = r.targetAll ?? false
        picked = Set(r.targetIDs ?? [r.nodeID])
        useRuns = r.useMaxRuns != false
        runs = r.maxRuns
        useTime = r.timeLimit != nil
        timeMinutes = (r.timeLimit ?? 7200) / 60
        let mode = r.goalMode ?? "text"
        useGoal = mode == "command" ? !(r.goalCommand ?? "").isEmpty : !r.goal.isEmpty
        goalMode = mode
        goal = r.goal
        goalCommand = r.goalCommand ?? ""
        goalAgent = r.goalAgent ?? "claude"
        background = r.background ?? true
    }

    func reset() {
        let fresh = LoopDraft()
        editing = nil; name = fresh.name; message = fresh.message; when = fresh.when; intervalMinutes = fresh.intervalMinutes
        idleSeconds = fresh.idleSeconds; pattern = ""; targetAll = true; picked = []; useRuns = false; runs = 10
        useTime = false; timeMinutes = 120; useGoal = false; goalMode = "agent"; goal = ""; goalCommand = ""; goalAgent = "claude"; background = true
    }

    var trigger: LoopTrigger {
        switch when {
        case "idle": return .idle(seconds: max(3, idleSeconds))
        case "output": return .output(pattern: pattern)
        default: return .interval(seconds: max(60, intervalMinutes * 60))
        }
    }

    func rule(fallbackNode: UUID) -> LoopRule {
        var r = LoopRule(id: editing ?? UUID(), nodeID: picked.first ?? fallbackNode, message: message, trigger: trigger,
                         goal: useGoal && goalMode != "command" ? goal : "", maxRuns: max(1, runs))
        r.name = name.isEmpty ? "Loop" : name
        r.targetAll = targetAll
        r.targetIDs = targetAll ? nil : Array(picked)
        r.useMaxRuns = useRuns
        r.timeLimit = useTime ? timeMinutes * 60 : nil
        r.goalMode = useGoal ? goalMode : "text"
        r.goalCommand = useGoal && goalMode == "command" ? goalCommand : nil
        r.goalAgent = goalAgent
        r.background = background
        return r
    }

    var isValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (targetAll || !picked.isEmpty)
            && (when != "output" || !pattern.isEmpty)
    }
}

struct LoopsModal: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runner: LoopRunner
    @ObservedObject var chrome: ChromeModel
    @ObservedObject var draft: LoopDraft
    let c: MainWindowController

    var consoles: [BoardNode] { model.selectedWorkspace.nodes.filter { $0.kind == .terminal } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { chrome.loopsPage = nil }
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(Color.symBorder)
                switch chrome.loopsPage ?? "list" {
                case "gallery": gallery
                case "form": form
                default: if runner.rows.isEmpty { gallery } else { list }
                }
            }
            .frame(maxWidth: 1000)
            // 배경을 높이 상한보다 먼저 달아, 내용이 짧으면 카드도 내용 높이로 줄어든다.
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .frame(maxHeight: 720)
            .padding(.horizontal, 80).padding(.vertical, 60)
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.symAccent)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Color.symAccent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Loops").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.symText)
                Text("Instructions that repeat for your agents: on a timer, when they go quiet, or when their output says so. A loop can switch itself off once its goal is reached.")
                    .font(.system(size: 12)).foregroundStyle(Color.symDim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if (chrome.loopsPage ?? "list") == "list" && !runner.rows.isEmpty {
                Button { draft.reset(); chrome.loopsPage = "gallery" } label: { Label("New loop", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            Button { chrome.loopsPage = nil } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }.tip("Close loops")
                .buttonStyle(.plainHit).foregroundStyle(Color.symDim).padding(.top, 4)
        }
        .padding(18)
    }

    // MARK: 틀 고르기

    /// 내용이 들어가면 스크롤 없이 내용 높이만큼, 넘치면 스크롤.
    func fitOrScroll<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        let c = content()
        return ViewThatFits(in: .vertical) {
            c
            ScrollView { c }
        }
    }

    var gallery: some View {
        fitOrScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("TEMPLATES").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(LoopTemplate.all) { t in
                        Button { draft.reset(); draft.apply(t); chrome.loopsPage = "form" } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: t.icon).foregroundStyle(Color.symAccent)
                                    Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                                }
                                Text(t.blurb).font(.system(size: 11)).foregroundStyle(Color.symDim).lineLimit(2)
                                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.symBorder))
                        }
                        .buttonStyle(.plainHit).axName(t.name)
                    }
                }
                HStack {
                    Spacer()
                    Button("Start from scratch") { draft.reset(); chrome.loopsPage = "form" }.buttonStyle(PillButtonStyle()).axName("Start from scratch")
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(18)
        }
    }

    // MARK: 목록

    var list: some View {
        fitOrScroll {
            VStack(spacing: 8) {
                ForEach(runner.rows) { row in
                    HStack(spacing: 12) {
                        Circle().fill(row.enabled ? Color.symAccent : Color.symDim).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(row.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                                Text("\(row.runCount) runs").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                                if !row.note.isEmpty { Text(row.note).font(.system(size: 11)).foregroundStyle(Color.symDim) }
                            }
                            Text(row.summary).font(.system(size: 11)).foregroundStyle(Color.symText.opacity(0.8)).lineLimit(1)
                            Text(row.message).font(.system(size: 11)).foregroundStyle(Color.symDim).lineLimit(1)
                        }
                        Spacer()
                        if row.checking {
                            ProgressView().controlSize(.small)
                        } else if let n = row.nextIn {
                            Text("in \(n / 60):\(String(format: "%02d", n % 60))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Color.symAccent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.symAccent.opacity(0.12)))
                        }
                        Button { runner.runNow(row.id) } label: {
                            Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 26, height: 26)
                                .background(Circle().fill(Color.symRaised))
                        }
                        .buttonStyle(.plainHit).foregroundStyle(Color.symText).tip("Run now")
                        Toggle("", isOn: Binding(get: { row.enabled }, set: { runner.setEnabled(row.id, $0) }))
                            .toggleStyle(.switch).labelsHidden().tint(Color.symAccent).controlSize(.small)
                        Menu {
                            Button("Edit") { if let r = runner.rule(row.id) { draft.load(r); chrome.loopsPage = "form" } }
                            Button("Delete", role: .destructive) { runner.remove(row.id) }
                        } label: { Image(systemName: "ellipsis") }.tip("Loop actions")
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised))
                }
            }
            .padding(18)
        }
    }

    // MARK: 양식

    var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(LoopTemplate.all) { t in
                                Button { draft.apply(t) } label: { Label(t.name, systemImage: t.icon) }
                                    .buttonStyle(ChipStyle(on: draft.name == t.name))
                            }
                        }
                    }
                    section("NAME") {
                        TextField("", text: $draft.name, prompt: Text("e.g. Suite watchdog").foregroundColor(Color.symDim)).modifier(FieldLook())
                    }
                    section("INSTRUCTION") {
                        TextEditor(text: $draft.message)
                            .font(.system(size: 13)).scrollContentBackground(.hidden).foregroundStyle(Color.symText)
                            .frame(height: 70).padding(6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                        Text("Typed into each targeted console exactly as written.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                    }
                    section("WHEN") {
                        HStack(spacing: 10) {
                            whenCard("interval", "clock", "On a timer", "Repeats at a fixed interval.")
                            whenCard("idle", "moon.zzz", "When an agent goes quiet", "Fires once a targeted console has finished.")
                            whenCard("output", "text.viewfinder", "When output contains...", "Fires when a console prints matching text.")
                        }
                        switch draft.when {
                        case "idle":
                            HStack { Text("Quiet for").foregroundStyle(Color.symDim); Stepper("\(Int(draft.idleSeconds)) s", value: $draft.idleSeconds, in: 3...600, step: 5) }
                                .font(.system(size: 12))
                        case "output":
                            TextField("", text: $draft.pattern, prompt: Text("Text to watch for, e.g. FAILED").foregroundColor(Color.symDim)).modifier(FieldLook())
                        default:
                            HStack(spacing: 6) {
                                ForEach([5.0, 10, 15, 30, 60, 120], id: \.self) { m in
                                    Button(m >= 60 ? "\(Int(m / 60)) h" : "\(Int(m)) min") { draft.intervalMinutes = m }
                                        .buttonStyle(ChipStyle(on: draft.intervalMinutes == m))
                                }
                                Spacer()
                                Stepper("every \(Int(draft.intervalMinutes)) min", value: $draft.intervalMinutes, in: 1...1440, step: 1)
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                            }
                        }
                    }
                    section("TARGET") {
                        radio(draft.targetAll, "All consoles", "\(consoles.count) on the board, plus any opened later") { draft.targetAll = true }
                        radio(!draft.targetAll, "Pick consoles", "Choose exactly which consoles receive it") { draft.targetAll = false }
                        if !draft.targetAll {
                            FlowRows(items: consoles.map(\.id), perRow: 6) { id in
                                let n = consoles.first { $0.id == id }!
                                Button(n.title) { if draft.picked.contains(id) { draft.picked.remove(id) } else { draft.picked.insert(id) } }
                                    .buttonStyle(ChipStyle(on: draft.picked.contains(id)))
                            }
                            .padding(.leading, 28)
                        }
                    }
                    section("STOP") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                toggle($draft.useRuns, "After a number of runs")
                                if draft.useRuns { Stepper("\(draft.runs) runs", value: $draft.runs, in: 1...500).font(.system(size: 12)) }
                            }
                            HStack {
                                toggle($draft.useTime, "After a time limit")
                                if draft.useTime { Stepper("\(Int(draft.timeMinutes)) min", value: $draft.timeMinutes, in: 5...1440, step: 5).font(.system(size: 12)) }
                            }
                            toggle($draft.useGoal, "When a goal is met")
                            if draft.useGoal { goalEditor.padding(.leading, 44) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised.opacity(0.6)))
                    }
                    section("BEHAVIOR") {
                        toggle($draft.background, "Keep running while another workspace is open")
                        Text("Off: the loop only runs while this workspace is on screen.").font(.system(size: 11)).foregroundStyle(Color.symDim).padding(.leading, 44)
                    }
                }
                .padding(18)
            }
            Divider().overlay(Color.symBorder)
            footer
        }
    }

    var goalEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { draft.goalMode = "text" } label: { Label("Output shows text", systemImage: "text.magnifyingglass") }
                    .buttonStyle(ChipStyle(on: draft.goalMode == "text"))
                Button { draft.goalMode = "command" } label: { Label("A command passes", systemImage: "terminal") }
                    .buttonStyle(ChipStyle(on: draft.goalMode == "command"))
                Button { draft.goalMode = "agent" } label: { Label("An agent judges", systemImage: "scope") }
                    .buttonStyle(ChipStyle(on: draft.goalMode == "agent"))
                if draft.goalMode == "agent" {
                    ForEach(["claude", "codex"], id: \.self) { a in
                        Button(LoopSummary.agentName(a)) { draft.goalAgent = a }.buttonStyle(ChipStyle(on: draft.goalAgent == a))
                    }
                }
            }
            switch draft.goalMode {
            case "command":
                TextField("", text: $draft.goalCommand, prompt: Text("e.g. swift test").foregroundColor(Color.symDim)).modifier(FieldLook())
                Text("Runs in the project folder before each round. Exit code 0 means the goal is met.").font(.system(size: 11)).foregroundStyle(Color.symDim)
            case "agent":
                TextField("", text: $draft.goal, prompt: Text("e.g. all tests are green").foregroundColor(Color.symDim)).modifier(FieldLook())
                Text("Before each round a one-off \(LoopSummary.agentName(draft.goalAgent)) run reads the consoles' recent output and answers yes or no. It changes nothing.")
                    .font(.system(size: 11)).foregroundStyle(Color.symDim)
            default:
                TextField("", text: $draft.goal, prompt: Text("e.g. ALL TESTS PASSED").foregroundColor(Color.symDim)).modifier(FieldLook())
            }
        }
    }

    var footer: some View {
        let r = draft.rule(fallbackNode: consoles.first?.id ?? UUID())
        let count = draft.targetAll ? consoles.count : draft.picked.count
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LoopSummary.sentence(r, consoleCount: count)).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symAccent)
                if let ph = LoopSummary.perHour(r, consoleCount: count) {
                    Text(String(format: "≈ %.1f prompts/h across %d console%@", ph, count, count == 1 ? "" : "s"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                }
            }
            Spacer()
            Button("Cancel") { chrome.loopsPage = runner.rows.isEmpty ? nil : "list" }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Cancel")
            Button(draft.editing == nil ? "Create loop" : "Save loop") { c.saveLoop() }
                .buttonStyle(PillButtonStyle(prominent: true)).disabled(!draft.isValid).opacity(draft.isValid ? 1 : 0.5)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            content()
        }
    }

    func whenCard(_ key: String, _ icon: String, _ title: String, _ sub: String) -> some View {
        let on = draft.when == key
        return Button { draft.when = key } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(on ? Color.symAccent : Color.symDim)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                    Text(sub).font(.system(size: 11)).foregroundStyle(Color.symDim).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.symAccent.opacity(0.08) : Color.symRaised))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.symAccent : Color.symBorder))
        }
        .buttonStyle(.plainHit)
    }

    func radio(_ on: Bool, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Color.symAccent : Color.symDim)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.symDim)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.symAccent.opacity(0.08) : Color.symRaised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Color.symAccent.opacity(0.6) : Color.symBorder))
        }
        .buttonStyle(.plainHit)
    }

    func toggle(_ b: Binding<Bool>, _ title: String) -> some View {
        Toggle(isOn: b) { Text(title).font(.system(size: 13)).foregroundStyle(Color.symText) }
            .toggleStyle(.switch).tint(Color.symAccent).controlSize(.small)
    }
}

struct FieldLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Color.symText)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
    }
}
