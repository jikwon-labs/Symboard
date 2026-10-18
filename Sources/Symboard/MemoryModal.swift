import AppKit
import SwiftUI
import SymboardCore

/// 메모리 모달 상태: 목록·편집·레포 스캔·제안 검토.
@MainActor
final class MemoryHub: ObservableObject {
    unowned let model: AppModel
    weak var c: MainWindowController?
    /// nil 이면 닫힘. "list", "edit", "pick", "scan", "review".
    @Published var page: String?
    @Published var allRepos = false
    @Published var editing: MemoryNote?
    @Published var agent = "claude"
    @Published var phase = 0
    @Published var proposals: [Proposal] = []
    @Published var scanError: String?
    @Published var startedAt = Date()
    @Published var rewriting = false
    private var stream = FactStream()
    private var job: AgentJob?

    struct Proposal: Identifiable, Equatable {
        let id = UUID()
        var fact: FactStream.Fact
        var selected = true
    }

    init(model: AppModel) { self.model = model }

    var repo: String? {
        guard let p = c?.projectPath else { return nil }
        return MemoryScope.repoRoot(for: p) ?? p
    }

    var notes: [MemoryNote] {
        // 원본처럼 두 칸은 적용 범위로 나눈다: 이 레포 것 / 모든 레포에 적용되는 것.
        model.state.memories.filter { allRepos ? $0.repoPath == nil : $0.repoPath == repo }
    }

    func newMemory() {
        editing = MemoryNote(repoPath: repo, title: "", body: "", category: "Context")
        page = "edit"
    }

    func save(_ n: MemoryNote) {
        model.mutateState { s in
            if let i = s.memories.firstIndex(where: { $0.id == n.id }) { s.memories[i] = n } else { s.memories.append(n) }
        }
        page = "list"
    }

    func delete(_ id: UUID) {
        model.mutateState { $0.memories.removeAll { $0.id == id } }
        page = "list"
    }

    // MARK: 레포 스캔

    static let scanPrompt = """
    Read this repository (README, manifests such as package.json or Package.swift, the top-level layout and a few key source files) \
    and propose 6 to 12 short facts that an AI coding agent should know before working here: how it is built and run, where things live, \
    conventions to follow, and traps to avoid. Be concrete and cite real paths and commands.
    Output ONLY JSON Lines, one object per line, no other text:
    {"category": "Architecture|Structure|Commands|Conventions|Gotchas|Context", "title": "short title", "body": "one or two sentences"}
    """

    func startScan() {
        guard let repo else { return }
        proposals = []
        scanError = nil
        phase = 0
        stream = FactStream()
        startedAt = Date()
        page = "scan"
        let j = AgentJob(.init(agent: agent, prompt: Self.scanPrompt, cwd: repo, tools: "Read,Glob,Grep"))
        job = j
        j.onActivity = { [weak self] _ in if let self, self.phase < 1 { self.phase = 1 } }
        j.onText = { [weak self] t in
            guard let self else { return }
            if self.phase < 2 { self.phase = 2 }
            for f in self.stream.feed(t) { self.proposals.append(Proposal(fact: f)) }
        }
        j.onDone = { [weak self] _, ok in
            guard let self else { return }
            for f in self.stream.finish() { self.proposals.append(Proposal(fact: f)) }
            self.phase = 3
            if self.proposals.isEmpty { self.scanError = ok ? "The agent did not return any facts." : "The scan did not finish. Check that the CLI is signed in." }
            else { self.page = "review" }
        }
        j.start()
    }

    func cancelScan() {
        job?.cancel()
        job = nil
        page = "list"
    }

    func acceptProposals() {
        let picked = proposals.filter(\.selected).map { MemoryNote(repoPath: repo, title: $0.fact.title, body: $0.fact.body, category: $0.fact.category) }
        model.mutateState { $0.memories += picked }
        proposals = []
        page = "list"
    }

    /// 편집 중인 본문을 에이전트로 짧고 분명하게 다시 쓴다.
    func rewrite(_ n: MemoryNote, done: @escaping (String) -> Void) {
        guard let repo else { return }
        rewriting = true
        let prompt = "Rewrite this note for an AI coding agent so it is short, concrete and correct. Reply with the rewritten note only.\n\nTitle: \(n.title)\n\n\(n.body)"
        let j = AgentJob(.init(agent: agent, prompt: prompt, cwd: repo, tools: ""))
        job = j
        j.onDone = { [weak self] text, ok in
            self?.rewriting = false
            if ok { done(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        j.start()
    }
}

struct MemoryModalView: View {
    @ObservedObject var hub: MemoryHub
    @ObservedObject var model: AppModel

    var body: some View {
        if let page = hub.page {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { if page != "scan" { hub.page = nil } }
                VStack(alignment: .leading, spacing: 0) {
                    header(page)
                    Divider().overlay(Color.symBorder)
                    switch page {
                    case "edit": if let n = hub.editing { MemoryEditor(hub: hub, note: n) }
                    case "pick": pick
                    case "scan": scan
                    case "review": review
                    default: list
                    }
                }
                .frame(maxWidth: 780, maxHeight: 640)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
                .padding(.horizontal, 120).padding(.vertical, 70)
            }
            .environment(\.locale, Locale(identifier: "en_US"))
        }
    }

    func header(_ page: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain").foregroundStyle(Color.symAccent)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Color.symAccent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.symText)
                Text("What your agents should know, sent from a memory card when you choose.").font(.system(size: 12)).foregroundStyle(Color.symDim)
            }
            Spacer()
            if page == "list" {
                Button { hub.page = "pick" } label: { Label("Scan repo", systemImage: "sparkle.magnifyingglass") }.buttonStyle(PillButtonStyle())
                Button { hub.newMemory() } label: { Label("New memory", systemImage: "plus") }.buttonStyle(PillButtonStyle(prominent: true))
            }
            Button { hub.page = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.tip("Close memory")
                .buttonStyle(.plainHit).foregroundStyle(Color.symDim).padding(.top, 4)
        }
        .padding(18)
    }

    static func color(_ cat: String?) -> Color {
        switch cat {
        case "Architecture": return Color(hex: "#56A8F5")
        case "Structure": return Color(hex: "#B48CF2")
        case "Commands": return Color(hex: "#E9C46A")
        case "Conventions": return Color(hex: "#6FCF97")
        case "Gotchas": return Color(hex: "#E8564A")
        default: return Color.symDim
        }
    }

    func categoryTag(_ cat: String?) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Self.color(cat)).frame(width: 5, height: 5)
            Text(cat ?? "Context").font(.system(size: 10))
        }
        .foregroundStyle(Self.color(cat))
    }

    var list: some View {
        let notes = hub.notes
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { hub.allRepos = false } label: {
                    Text("\(hub.repo.map { ($0 as NSString).lastPathComponent } ?? "This repo") \(model.state.memories.filter { $0.repoPath == hub.repo }.count)")
                }
                .buttonStyle(ChipStyle(on: !hub.allRepos))
                let globalCount = model.state.memories.filter { $0.repoPath == nil }.count
                Button("All repos \(globalCount)") { hub.allRepos = true }.buttonStyle(ChipStyle(on: hub.allRepos)).axName("All repos \(globalCount)")
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 12)
            if notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "brain").font(.system(size: 28)).foregroundStyle(Color.symDim)
                    Text("No memory yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText)
                    Text("Scan the repo with a CLI, or write the first fact yourself.").font(.system(size: 12)).foregroundStyle(Color.symDim)
                    HStack {
                        Button { hub.page = "pick" } label: { Label("Scan repo", systemImage: "sparkle.magnifyingglass") }.buttonStyle(PillButtonStyle(prominent: true))
                        Button { hub.newMemory() } label: { Label("Write memory", systemImage: "square.and.pencil") }.buttonStyle(PillButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(notes) { n in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        categoryTag(n.category)
                                        Text(n.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                                        if n.repoPath == nil { Text("all repos").font(.system(size: 10)).foregroundStyle(Color.symDim) }
                                    }
                                    Text(n.body).font(.system(size: 12)).foregroundStyle(Color.symText.opacity(0.75)).lineLimit(2)
                                }
                                Spacer()
                                Button { hub.editing = n; hub.page = "edit" } label: { Image(systemName: "pencil") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Edit note")
                            }
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            HStack {
                Text("Cards on the board send these to a console only when you press Send.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                Spacer()
                Button { hub.c?.placeMemoryCard() } label: { Label("Place card on board", systemImage: "rectangle.on.rectangle") }.buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
        }
    }

    var pick: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCAN THIS REPOSITORY").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            Text("A one-off read-only CLI run looks through \(hub.repo.map { ($0 as NSString).lastPathComponent } ?? "the repo") and proposes facts. Nothing is saved until you accept them.")
                .font(.system(size: 12)).foregroundStyle(Color.symText.opacity(0.8))
            HStack(spacing: 6) {
                ForEach(["claude", "codex"], id: \.self) { a in
                    let ch = AgentCatalog.choice(id: a)!
                    Button { hub.agent = a } label: { HStack(spacing: 6) { AgentBadge(choice: ch, size: 18); Text(ch.name) } }
                        .buttonStyle(ChipStyle(on: hub.agent == a))
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { hub.page = "list" }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Cancel")
                Button("Scan with \(AgentCatalog.choice(id: hub.agent)?.name ?? "CLI")") { hub.startScan() }.buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(18)
    }

    var scan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("Scanning with \(AgentCatalog.choice(id: hub.agent)?.name ?? "CLI") · \(Int(ctx.date.timeIntervalSince(hub.startedAt)))s")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                    }
                    Text("Facts appear here as the agent writes them.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
                Spacer()
                Button("Cancel") { hub.cancelScan() }.buttonStyle(PillButtonStyle()).axName("Cancel")
            }
            HStack(spacing: 14) {
                ForEach(Array(["Launch", "Read the repo", "Write facts"].enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 5) {
                        Image(systemName: hub.phase > i ? "checkmark.circle.fill" : (hub.phase == i ? "circle.dotted" : "circle"))
                            .foregroundStyle(hub.phase >= i ? Color.symAccent : Color.symDim)
                        Text(s).font(.system(size: 11)).foregroundStyle(hub.phase >= i ? Color.symText : Color.symDim)
                    }
                }
            }
            if let e = hub.scanError { Text(e).font(.system(size: 12)).foregroundStyle(Color.symAccent) }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(hub.proposals) { p in proposalRow(p, editable: false) }
                    if hub.phase < 3 {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10).fill(Color.symRaised.opacity(0.5)).frame(height: 54)
                        }
                    }
                }
            }
        }
        .padding(18)
    }

    var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("REVIEW PROPOSALS").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
                Text("\(hub.proposals.filter(\.selected).count) of \(hub.proposals.count) selected").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
            }
            Text("Keep what is true. Accepted entries join this repo's memory.").font(.system(size: 12)).foregroundStyle(Color.symDim)
            ScrollView {
                VStack(spacing: 6) { ForEach(hub.proposals) { p in proposalRow(p, editable: true) } }
            }
            HStack {
                Spacer()
                Button("Discard") { hub.proposals = []; hub.page = "list" }.buttonStyle(PillButtonStyle()).axName("Discard")
                Button("Add \(hub.proposals.filter(\.selected).count) to memory") { hub.acceptProposals() }.buttonStyle(PillButtonStyle(prominent: true)).axName("Add \(hub.proposals.filter(\.selected).count) to memory")
            }
        }
        .padding(18)
    }

    func proposalRow(_ p: MemoryHub.Proposal, editable: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if editable {
                Button { if let i = hub.proposals.firstIndex(of: p) { hub.proposals[i].selected.toggle() } } label: {
                    Image(systemName: p.selected ? "checkmark.circle.fill" : "circle").foregroundStyle(p.selected ? Color.symAccent : Color.symDim)
                }
                .buttonStyle(.plainHit)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) { categoryTag(p.fact.category); Text(p.fact.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText) }
                Text(p.fact.body).font(.system(size: 12)).foregroundStyle(Color.symText.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if editable {
                Button {
                    hub.editing = MemoryNote(repoPath: hub.repo, title: p.fact.title, body: p.fact.body, category: p.fact.category)
                    hub.proposals.removeAll { $0.id == p.id }
                    hub.page = "edit"
                } label: { Image(systemName: "pencil") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Edit note")
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct MemoryEditor: View {
    @ObservedObject var hub: MemoryHub
    @State var note: MemoryNote

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EDIT MEMORY").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            HStack(spacing: 4) {
                ForEach(FactStream.categories, id: \.self) { c in
                    Button { note.category = c } label: {
                        HStack(spacing: 4) { Circle().fill(MemoryModalView.color(c)).frame(width: 5, height: 5); Text(c) }
                    }
                    .buttonStyle(ChipStyle(on: (note.category ?? "Context") == c))
                }
            }
            HStack {
                TextField("", text: $note.title, prompt: Text("Title").foregroundColor(Color.symDim)).modifier(FieldLook())
                    .autoFocus(note.title.isEmpty)
                    .onSubmit { hub.save(note) }
                Button {
                    hub.rewrite(note) { note.body = $0 }
                } label: { if hub.rewriting { ProgressView().controlSize(.small) } else { Label("Rewrite", systemImage: "sparkles") } }
                    .buttonStyle(PillButtonStyle()).tip("Rewrite with \(AgentCatalog.choice(id: hub.agent)?.name ?? "CLI") (uses your plan)")
            }
            TextEditor(text: $note.body)
                .font(.system(size: 13)).scrollContentBackground(.hidden).foregroundStyle(Color.symText)
                .frame(minHeight: 160).padding(8).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
            HStack(spacing: 6) {
                Text("APPLIES TO").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.symDim)
                Button("This repo") { note.repoPath = hub.repo }.buttonStyle(ChipStyle(on: note.repoPath != nil)).axName("This repo")
                Button("All repos") { note.repoPath = nil }.buttonStyle(ChipStyle(on: note.repoPath == nil)).axName("All repos")
            }
            Spacer()
            HStack {
                Button("Delete") { hub.delete(note.id) }.buttonStyle(.plainHit).foregroundStyle(Color.symAccent).axName("Delete")
                Spacer()
                Button("Cancel") { hub.page = "list" }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Cancel")
                Button("Save memory") { hub.save(note) }.keyboardShortcut(.return, modifiers: .command).buttonStyle(PillButtonStyle(prominent: true)).axName("Save memory")
                    .disabled(note.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
    }
}

/// 보드 위 메모리 카드: 고른 메모를 고른 콘솔에 보낸다(Send 를 눌렀을 때만).
final class MemoryCardContent: NodeContent {
    let host: NSView
    var view: NSView { host }

    init(node: BoardNode, model: AppModel) {
        host = CanvasHostingView(rootView: MemoryCardView(model: model, repo: node.text).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}
}

struct MemoryCardView: View {
    @ObservedObject var model: AppModel
    let repo: String?
    @State private var picked: Set<UUID> = []
    @State private var target: UUID?
    @State private var enter = false
    @State private var sent = ""

    var notes: [MemoryNote] { model.state.memories.filter { $0.repoPath == repo || $0.repoPath == nil } }
    var consoles: [BoardNode] { model.selectedWorkspace.nodes.filter { $0.kind == .terminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes) { n in
                        Button { if picked.contains(n.id) { picked.remove(n.id) } else { picked.insert(n.id) } } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: picked.contains(n.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(n.id) ? Color.symAccent : Color.symDim)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText)
                                    Text(n.body).font(.system(size: 11)).foregroundStyle(Color.symDim).lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plainHit).axName(n.title)
                    }
                }
            }
            HStack(spacing: 6) {
                Menu(target.flatMap { id in consoles.first { $0.id == id }?.title } ?? "Pick a console") {
                    ForEach(consoles) { n in Button(n.title) { target = n.id } }
                }
                .menuStyle(.borderlessButton).fixedSize()
                Toggle("Enter", isOn: $enter).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Button("Send \(picked.isEmpty ? notes.count : picked.count)") { send() }.buttonStyle(PillButtonStyle(prominent: true)).axName("Send \(picked.isEmpty ? notes.count : picked.count)")
                    .disabled(target == nil || notes.isEmpty)
            }
            if !sent.isEmpty { Text(sent).font(.system(size: 10)).foregroundStyle(Color.symDim) }
        }
        .padding(10)
        .background(Color.symSurface)
    }

    func send() {
        guard let t = target, let s = model.sessions.session(for: t), s.running else { sent = "That console is not running."; return }
        let chosen = notes.filter { picked.isEmpty || picked.contains($0.id) }
        s.sendText(chosen.map(MemoryScope.text(for:)).joined(separator: "\n\n"), submit: enter)
        sent = "Sent \(chosen.count) to \(model.node(t)?.title ?? "console")"
    }
}
