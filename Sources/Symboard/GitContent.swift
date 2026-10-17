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
    @Published var log = ""
    @Published var busy = false
    let onRepoChange: (String) -> Void

    init(repo: String, onRepoChange: @escaping (String) -> Void) {
        self.repo = repo
        self.onRepoChange = onRepoChange
        Task { await refresh() }
    }

    func refresh() async {
        let r = await GitRunner.run(["status", "--porcelain=v2", "--branch"], cwd: repo)
        if r.code == 0 { status = GitStatus.parse(r.out) }
        else { status = nil; log = r.err.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func perform(_ name: String, _ steps: [[String]]) async {
        busy = true
        defer { busy = false }
        var out: [String] = []
        for args in steps {
            let r = await GitRunner.run(args, cwd: repo)
            out.append("$ git \(args.joined(separator: " "))\n\(r.out)\(r.err)".trimmingCharacters(in: .whitespacesAndNewlines))
            if r.code != 0 { out.append("(\(name) failed: exit \(r.code))"); break }
        }
        log = out.joined(separator: "\n")
        await refresh()
    }

    func commit() async {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { log = "Write a commit message first."; return }
        await perform("commit", [["add", "-A"], ["commit", "-m", msg]])
        if log.contains("failed") == false { message = "" }
    }
}

struct GitCardView: View {
    @ObservedObject var card: GitCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Repository path", text: $card.repo)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        card.repo = (card.repo as NSString).expandingTildeInPath
                        card.onRepoChange(card.repo)
                        Task { await card.refresh() }
                    }
                Button { Task { await card.refresh() } } label: { Image(systemName: "arrow.clockwise") }
            }
            if let s = card.status {
                HStack(spacing: 8) {
                    Label(s.branch, systemImage: "arrow.triangle.branch").font(.system(size: 13, weight: .semibold))
                    if s.ahead > 0 { Text("\u{2191}\(s.ahead)").foregroundStyle(.green) }
                    if s.behind > 0 { Text("\u{2193}\(s.behind)").foregroundStyle(.orange) }
                    Spacer()
                    Text(s.isClean ? "clean" : "\(s.changes.count) changed").foregroundStyle(s.isClean ? Color.green : Color.orange)
                }
                .font(.system(size: 12))
                if let up = s.upstream { Text("tracking \(up)").font(.system(size: 10)).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(s.changes.enumerated()), id: \.offset) { _, c in
                            HStack(spacing: 6) {
                                Text(c.code).font(.system(size: 11, design: .monospaced)).foregroundStyle(color(for: c.code)).frame(width: 22, alignment: .leading)
                                Text(c.path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Not a git repository").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
            }
            TextField("Commit message", text: $card.message).textFieldStyle(.roundedBorder)
            HStack {
                Button("Commit All") { Task { await card.commit() } }
                Button("Pull") { Task { await card.perform("pull", [["pull", "--ff-only"]]) } }
                Button("Push") { Task { await card.perform("push", [["push"]]) } }
                if card.busy { ProgressView().controlSize(.small) }
            }
            .disabled(card.busy || card.status == nil)
            .controlSize(.small)
            if !card.log.isEmpty {
                ScrollView {
                    Text(card.log).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 70)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.12))
    }

    private func color(for code: String) -> Color {
        if code == "??" { return .gray }
        if code.contains("D") { return .red }
        if code.contains("A") { return .green }
        return .orange
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
        host = NSHostingView(rootView: GitCardView(card: card).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Refresh") { [weak self] in
            guard let self else { return }
            Task { await self.card.refresh() }
        }]
    }
}
