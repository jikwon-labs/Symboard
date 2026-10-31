import AppKit
import SymboardCore

/// 사용자가 로그인해 둔 CLI 를 백그라운드로 한 번 돌리고 출력을 실시간으로 넘긴다.
/// 외부 API 키를 쓰지 않는다. PTY 화면을 긁지 않고 비대화형 JSON 출력을 읽는다.
@MainActor
final class AgentJob {
    struct Options {
        var agent: String = "claude"
        var prompt: String
        var cwd: String
        /// claude --tools 값. ""=도구 없음, 예: "Read,Glob,Grep".
        var tools: String = "Read,Glob,Grep"
        var systemPrompt: String?
    }

    private(set) var process: Process?
    private(set) var output = ""
    var onText: ((String) -> Void)?
    var onActivity: ((String) -> Void)?
    var onDone: ((String, Bool) -> Void)?
    private var parser: AgentStreamParser
    private var buffer = Data()
    private var finished = false
    let options: Options
    let startedAt = Date()

    init(_ options: Options) {
        self.options = options
        parser = AgentStreamParser(agent: options.agent)
    }

    /// 실행할 명령(셸 한 줄). 시험·기록용으로 드러낸다.
    static func commandLine(_ o: Options) -> [String] {
        switch o.agent {
        case "codex":
            return ["codex", "exec", "--json", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", "-C", o.cwd,
                    (o.systemPrompt.map { $0 + "\n\n" } ?? "") + o.prompt]
        default:
            var a = ["claude", "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                     "--no-session-persistence", "--permission-mode", "dontAsk", "--tools", o.tools]
            if let s = o.systemPrompt { a += ["--append-system-prompt", s] }
            return a + ["--", o.prompt]
        }
    }

    func start() {
        let p = Process()
        let shell = ProcessEnvironment.userShell
        p.executableURL = URL(fileURLWithPath: shell)
        let cmd = Self.commandLine(options).map(Self.quote).joined(separator: " ")
        p.arguments = ["-lc", "exec " + cmd]
        p.currentDirectoryURL = URL(fileURLWithPath: options.cwd)
        p.environment = ProcessEnvironment.base()
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        // 출력이 끝나면(빈 데이터) 읽기 핸들러를 꼭 뗀다. 그대로 두면 끝난 파이프에서 빈 데이터로 끝없이 다시 불려
        // CPU 코어를 차지하고 메인 큐를 메웠다(작업 객체가 사라진 뒤에도).
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        // stderr 는 쓰지 않지만 읽어서 버린다. 읽지 않으면 64KB 가 찼을 때 자식이 쓰기에서 멈춘다.
        err.fileHandleForReading.readabilityHandler = { h in
            if h.availableData.isEmpty { h.readabilityHandler = nil }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { self?.finish(ok: code == 0) }
        }
        do { try p.run(); process = p } catch { finish(ok: false) }
    }

    func cancel() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
    }

    private func consume(_ d: Data) {
        guard !d.isEmpty else { return }
        buffer.append(d)
        // 줄을 하나씩 앞에서 지우면 조각 하나 안에서 매번 남은 바이트를 당겨 와 줄 수에 비례해 느려진다. 끝에 한 번만 지운다.
        var start = buffer.startIndex
        defer { buffer.removeSubrange(buffer.startIndex..<start) }
        while let nl = buffer[start...].firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[start..<nl], as: UTF8.self)
            start = buffer.index(after: nl)
            for ev in parser.parse(line: line) {
                switch ev {
                case .text(let t):
                    output += t
                    onText?(t)
                case .activity(let a):
                    onActivity?(a)
                case .done(let final, let ok):
                    if output.isEmpty, let f = final { output = f; onText?(f) }
                    finish(ok: ok)
                }
            }
        }
    }

    private func finish(ok: Bool) {
        guard !finished else { return }
        finished = true
        onDone?(output, ok && !output.isEmpty)
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
