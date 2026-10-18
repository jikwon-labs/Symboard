import AppKit
import SwiftUI
import SymboardCore

/// 로컬 git 명령 실행.
enum GitRunner {
    struct Output: Sendable {
        var code: Int32
        var out: String
        var err: String
    }

    static func run(_ args: [String], cwd: String) async -> Output {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = args
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                var env = LaunchPlanner.sanitized(ProcessInfo.processInfo.environment)
                // 비밀번호를 물으며 멈추지 않게 한다.
                env["GIT_TERMINAL_PROMPT"] = "0"
                p.environment = env
                let o = Pipe(), e = Pipe()
                p.standardOutput = o
                p.standardError = e
                do { try p.run() } catch {
                    cont.resume(returning: Output(code: -1, out: "", err: error.localizedDescription))
                    return
                }
                let od = o.fileHandleForReading.readDataToEndOfFile()
                let ed = e.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: Output(code: p.terminationStatus, out: String(decoding: od, as: UTF8.self),
                                              err: String(decoding: ed, as: UTF8.self)))
            }
        }
    }
}

/// git 카드 상태.
@MainActor
final class GitCardModel: ObservableObject {
    @Published var repo: String
    @Published var status: GitStatus?
    @Published var message = ""
    /// 마지막 동작 결과(셸 출력). 화면에는 요약 줄만 보인다.
    @Published var log = ""
    @Published var busy = false
    @Published var phase = ""
    /// 커밋에서 뺀 파일(나머지는 모두 고른 것으로 본다).
    @Published var excluded: Set<String> = []
    @Published var recent: [GitInfo.Commit] = []
    @Published var added = 0
    @Published var removed = 0
    @Published var resultLine: String?
    @Published var resultOK = true
    @Published var showHistory = false
    @Published var generating = false
    let onRepoChange: (String) -> Void
    private var job: AgentJob?

    init(repo: String, onRepoChange: @escaping (String) -> Void) {
        self.repo = repo
        self.onRepoChange = onRepoChange
        Task { await refresh() }
    }

    var selected: [GitStatus.Change] { (status?.changes ?? []).filter { !excluded.contains($0.path) } }

    var repoName: String { (repo as NSString).lastPathComponent }

    func refresh() async {
        let r = await GitRunner.run(["status", "--porcelain=v2", "--branch", "-uall"], cwd: repo)
        guard r.code == 0 else { status = nil; log = r.err.trimmingCharacters(in: .whitespacesAndNewlines); return }
        let s = GitStatus.parse(r.out)
        status = s
        excluded = excluded.intersection(s.changes.map(\.path))
        let ns = await GitRunner.run(["diff", "HEAD", "--numstat"], cwd: repo)
        (added, removed) = GitInfo.numstat(ns.out)
        let l = await GitRunner.run(["log", "-n", "30", "--format=\(GitInfo.logFormat)"], cwd: repo)
        recent = GitInfo.parseLog(l.out)
    }

    func perform(_ name: String, _ steps: [[String]]) async {
        busy = true
        defer { busy = false }
        var out: [String] = []
        var ok = true
        for args in steps {
            let r = await GitRunner.run(args, cwd: repo)
            out.append("$ git \(args.joined(separator: " "))\n\(r.out)\(r.err)".trimmingCharacters(in: .whitespacesAndNewlines))
            if r.code != 0 { out.append("(\(name) failed: exit \(r.code))"); ok = false; break }
        }
        log = out.joined(separator: "\n")
        resultOK = ok
        if !ok { resultLine = "\(name.capitalized) failed: " + (log.split(separator: "\n").last(where: { !$0.hasPrefix("(") }).map(String.init) ?? "") }
        await refresh()
    }

    /// 고른 파일만 커밋하고, 올릴 곳이 있으면 이어서 push 한다.
    func commit() async {
        let files = selected
        guard !files.isEmpty else { resultLine = "Nothing selected"; resultOK = false; return }
        var msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { msg = GitInfo.defaultMessage(files) }
        let paths = files.map(\.path)
        phase = "Committing..."
        await perform("commit", [["add", "--"] + paths, ["commit", "-m", msg, "--"] + paths])
        guard resultOK else { phase = ""; return }
        message = ""
        let remotes = await GitRunner.run(["remote"], cwd: repo).out
        if status?.upstream != nil || remotes.contains(where: { !$0.isWhitespace }) {
            phase = "Pushing..."
            let pushArgs: [String] = status?.upstream != nil ? ["push"] : ["push", "-u", "origin", status?.branch ?? "HEAD"]
            await perform("push", [pushArgs])
            phase = ""
            resultLine = resultOK ? "Committed \(files.count) file\(files.count == 1 ? "" : "s") · pushed" : resultLine
        } else {
            phase = ""
            resultLine = "Committed \(files.count) file\(files.count == 1 ? "" : "s") · no remote"
        }
    }

    /// 고른 변경의 diff 를 CLI 에 보내 한 줄 메시지를 받는다(사용자 CLI 사용량을 쓴다).
    func generateMessage(agent: String) async {
        let paths = selected.map(\.path)
        guard !paths.isEmpty else { return }
        let d = await GitRunner.run(["diff", "HEAD", "--stat", "--"] + paths, cwd: repo)
        let body = await GitRunner.run(["diff", "HEAD", "--"] + paths, cwd: repo)
        let untracked = selected.filter { $0.code == "??" }.map(\.path)
        let prompt = """
        Write one git commit subject line (imperative, under 60 characters, no quotes, no trailing period) for this change.
        Reply with the subject line only.

        \(d.out)
        New files: \(untracked.joined(separator: ", "))

        \(String(body.out.prefix(12000)))
        """
        generating = true
        let j = AgentJob(.init(agent: agent, prompt: prompt, cwd: repo, tools: ""))
        job = j
        j.onDone = { [weak self] text, ok in
            guard let self else { return }
            self.generating = false
            let line = text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \"'`")) } ?? ""
            if ok, !line.isEmpty { self.message = line } else { self.resultLine = "Could not generate a message"; self.resultOK = false }
        }
        j.start()
    }

    func openInFinder() { NSWorkspace.shared.open(URL(fileURLWithPath: repo)) }
}

struct GitCardView: View {
    @ObservedObject var card: GitCardModel
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.symBorder)
            if card.showHistory { history } else { changes }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.symSurface)
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symText)
                .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 8).fill(Color.symRaised))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.repoName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText).lineLimit(1).truncationMode(.middle)
                if let s = card.status {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text(s.branch).font(.system(size: 11, design: .monospaced))
                        Text(syncText(s)).font(.system(size: 11)).foregroundStyle(Color.symDim)
                    }
                    .foregroundStyle(Color.symText.opacity(0.8))
                }
            }
            Spacer()
            circle("clock.arrow.circlepath", "History", on: card.showHistory) { card.showHistory.toggle() }
            circle("arrow.up.right", "Open in Finder") { card.openInFinder() }
            circle("arrow.clockwise", "Refresh") { Task { await card.refresh() } }
            if let onClose { circle("xmark", "Close", action: onClose) }
        }
        .padding(12)
    }

    func syncText(_ s: GitStatus) -> String {
        if s.upstream == nil { return "local" }
        if s.ahead == 0 && s.behind == 0 { return "synced" }
        return [s.ahead > 0 ? "\u{2191}\(s.ahead)" : nil, s.behind > 0 ? "\u{2193}\(s.behind)" : nil].compactMap { $0 }.joined(separator: " ")
    }

    func circle(_ symbol: String, _ tip: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(on ? Color.symAccent.opacity(0.18) : Color.symRaised))
                .foregroundStyle(on ? Color.symAccent : Color.symText.opacity(0.8))
        }
        .buttonStyle(.plainHit).help(tip)
    }

    func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
    }

    @ViewBuilder var changes: some View {
        if let s = card.status {
            VStack(alignment: .leading, spacing: 10) {
                if s.isClean {
                    section("CHANGES")
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: "#6FCF97"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Working tree clean").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.symText)
                            Text("Nothing to commit.").font(.system(size: 11)).foregroundStyle(Color.symDim)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        section("CHANGES")
                        Text("\(card.selected.count)/\(s.changes.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                        Text("+\(card.added)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "#6FCF97"))
                        Text("\u{2212}\(card.removed)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "#E8564A"))
                        Spacer()
                        Button(card.excluded.isEmpty ? "None" : "All") {
                            card.excluded = card.excluded.isEmpty ? Set(s.changes.map(\.path)) : []
                        }
                        .buttonStyle(.plainHit).font(.system(size: 11)).foregroundStyle(Color.symDim)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(s.changes, id: \.path) { c in fileRow(c) }
                        }
                    }
                    .frame(maxHeight: 220)
                    HStack(spacing: 6) {
                        TextField("", text: $card.message, prompt: Text(GitInfo.defaultMessage(card.selected.isEmpty ? s.changes : card.selected)).foregroundColor(Color.symDim))
                            .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText)
                            .onSubmit { Task { await card.commit() } }
                        if card.generating { ProgressView().controlSize(.mini) } else {
                            Button { Task { await card.generateMessage(agent: "claude") } } label: { Image(systemName: "sparkles") }
                                .buttonStyle(.plainHit).foregroundStyle(Color.symAccent).help("Write the message with Claude (uses your plan)")
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                    Button { Task { await card.commit() } } label: {
                        HStack(spacing: 6) {
                            if card.busy { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "arrow.up.circle.fill") }
                            Text(card.busy ? (card.phase.isEmpty ? "Working..." : card.phase) : buttonTitle(s))
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Capsule().fill(Color.symAccent.opacity(card.selected.isEmpty ? 0.4 : 1)))
                    }
                    .buttonStyle(.plainHit).disabled(card.busy || card.selected.isEmpty)
                }
                section("RECENT").padding(.top, 4)
                ForEach(card.recent.prefix(3), id: \.hash) { c in
                    HStack(spacing: 8) {
                        Circle().fill(Color.symDim).frame(width: 4, height: 4)
                        Text(c.subject).font(.system(size: 12)).foregroundStyle(Color.symText).lineLimit(1)
                        Spacer()
                        Text(GitInfo.relative(c.date)).font(.system(size: 11)).foregroundStyle(Color.symDim)
                    }
                }
                Spacer(minLength: 0)
                if let r = card.resultLine {
                    HStack(spacing: 6) {
                        Image(systemName: card.resultOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(card.resultOK ? Color(hex: "#6FCF97") : Color.symAccent)
                        Text(r).font(.system(size: 12)).foregroundStyle(Color.symText).lineLimit(2)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                }
            }
            .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not a git repository").foregroundStyle(Color.symDim).font(.system(size: 12))
                TextField("Repository path", text: $card.repo).textFieldStyle(.roundedBorder)
                    .onSubmit {
                        card.repo = (card.repo as NSString).expandingTildeInPath
                        card.onRepoChange(card.repo)
                        Task { await card.refresh() }
                    }
            }
            .padding(12)
        }
    }

    func buttonTitle(_ s: GitStatus) -> String {
        let n = card.selected.count
        return "Commit\(s.upstream != nil ? " & Push" : "") \(n) file\(n == 1 ? "" : "s")"
    }

    func fileRow(_ c: GitStatus.Change) -> some View {
        let on = !card.excluded.contains(c.path)
        let letter = GitInfo.letter(c.code)
        let color: Color = ["A": Color(hex: "#6FCF97"), "U": Color(hex: "#6FCF97"), "D": Color(hex: "#E8564A"), "R": Color(hex: "#56A8F5")][letter] ?? Color(hex: "#E9C46A")
        let dir = (c.path as NSString).deletingLastPathComponent
        return Button {
            if on { card.excluded.insert(c.path) } else { card.excluded.remove(c.path) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.symAccent : Color.symDim)
                Text(letter).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(color)
                    .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 0) {
                    Text((c.path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText).lineLimit(1)
                    if !dir.isEmpty { Text(dir).font(.system(size: 10)).foregroundStyle(Color.symDim).lineLimit(1).truncationMode(.head) }
                }
                Spacer()
            }
            .padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plainHit)
    }

    var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("HISTORY")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(card.recent, id: \.hash) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.subject).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText)
                            HStack(spacing: 6) {
                                Text(c.hash).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symAccent)
                                Text(c.author).font(.system(size: 10)).foregroundStyle(Color.symDim)
                                Spacer()
                                Text(GitInfo.relative(c.date)).font(.system(size: 10)).foregroundStyle(Color.symDim)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

final class GitContent: NodeContent {
    let card: GitCardModel
    let host: NSView
    var view: NSView { host }

    init(node: BoardNode, model: AppModel) {
        let id = node.id
        card = GitCardModel(repo: node.text ?? NSHomeDirectory()) { [weak model] path in
            model?.mutateNode(id) { $0.text = path }
        }
        host = CanvasHostingView(rootView: GitCardView(card: card).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Refresh") { [weak self] in
            guard let self else { return }
            Task { await self.card.refresh() }
        }]
    }
}
