import AppKit
import SwiftTerm
import SymboardCore

/// SwiftTerm 터미널 뷰. 출력이 들어올 때마다 세션에 알린다.
final class SymTerminalView: LocalProcessTerminalView {
    var onOutput: ((ArraySlice<UInt8>) -> Void)?
    var onUserInput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?(slice)
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onUserInput?()
        super.send(source: source, data: data)
    }
}

/// 노드 하나에 붙은 PTY 프로세스와 그 상태.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let nodeID: UUID
    let view: SymTerminalView
    private(set) var tracker: StatusTracker
    private(set) var plan: LaunchPlan?
    private(set) var running = false
    let statusFile: URL
    private var statusMTime: Date?
    /// 루프·넘겨주기에서 쓰는 최근 출력 텍스트(제어 문자 제거).
    private(set) var recentText = ""
    /// 새 출력 텍스트가 들어올 때 불린다.
    var outputListeners: [UUID: (String) -> Void] = [:]
    var onTitle: ((String) -> Void)?
    var onExit: ((Int32?) -> Void)?
    private var stripper = ANSIStripper()

    init(nodeID: UUID, statusDirectory: URL, usesHooks: Bool) {
        self.nodeID = nodeID
        self.view = SymTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        self.tracker = StatusTracker(usesHooks: usesHooks)
        self.statusFile = statusDirectory.appendingPathComponent(nodeID.uuidString)
        super.init()
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        view.onOutput = { [weak self] slice in
            MainActor.assumeIsolated { self?.handleOutput(slice) }
        }
        view.onUserInput = { [weak self] in
            MainActor.assumeIsolated { self?.tracker.noteInput() }
        }
    }

    func start(plan: LaunchPlan, shell: String) {
        self.plan = plan
        try? FileManager.default.createDirectory(at: statusFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: statusFile)
        statusMTime = nil
        tracker = StatusTracker(usesHooks: tracker.usesHooks)

        var env = ProcessEnvironment.base()
        for (k, v) in plan.environment { env[k] = v }
        let envList = env.map { "\($0.key)=\($0.value)" }
        let wrapped = LaunchPlanner.shellWrapped(plan.command, shell: shell)
        let cwd = FileManager.default.fileExists(atPath: plan.cwd) ? plan.cwd : NSHomeDirectory()
        view.startProcess(executable: wrapped.executable, args: wrapped.args, environment: envList,
                          execName: nil, currentDirectory: cwd)
        running = true
    }

    func terminate() {
        guard running else { return }
        running = false
        view.terminate()
    }

    /// 사용자가 친 것처럼 문자열을 보낸다. submit 이면 Enter 까지 보낸다.
    func sendText(_ text: String, submit: Bool) {
        guard running else { return }
        // 여러 줄은 bracketed paste 로 감싸서 CLI 가 한 번에 받게 한다. 프로그램이 그 모드를 켰을 때만.
        if text.contains("\n") && view.getTerminal().bracketedPasteMode {
            view.send(txt: "\u{1b}[200~" + text + "\u{1b}[201~")
        } else {
            view.send(txt: text)
        }
        tracker.noteInput()
        if submit {
            // CLI 가 붙여넣기를 처리할 시간을 조금 준 뒤 Enter.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.view.send(txt: "\r")
            }
        }
    }

    func currentStatus(now: Date = Date()) -> NodeStatus {
        pollStatusFile()
        return tracker.status(now: now)
    }

    func idleSeconds(now: Date = Date()) -> TimeInterval { tracker.idleSeconds(now: now) }

    /// 화면에 보이는 터미널 내용을 텍스트로.
    func screenText() -> String {
        let term = view.getTerminal()
        var lines: [String] = []
        for row in 0..<term.rows {
            guard let line = term.getLine(row: row) else { continue }
            lines.append(line.translateToString(trimRight: true))
        }
        return lines.joined(separator: "\n")
    }

    private func pollStatusFile() {
        guard tracker.usesHooks,
              let attrs = try? FileManager.default.attributesOfItem(atPath: statusFile.path),
              let mtime = attrs[.modificationDate] as? Date, mtime != statusMTime else { return }
        statusMTime = mtime
        if let word = try? String(contentsOf: statusFile, encoding: .utf8),
           let state = HookState(rawValue: word.trimmingCharacters(in: .whitespacesAndNewlines)) {
            tracker.noteHook(state, at: mtime)
        }
    }

    private func handleOutput(_ slice: ArraySlice<UInt8>) {
        tracker.noteOutput()
        let text = stripper.feed(slice)
        guard !text.isEmpty else { return }
        recentText += text
        if recentText.count > 64_000 { recentText = String(recentText.suffix(48_000)) }
        for l in outputListeners.values { l(text) }
    }

    func clearRecentText() { recentText = "" }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated { onTitle?(title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            running = false
            tracker.noteExit()
            onExit?(exitCode)
        }
    }
}

/// 자식 프로세스 환경 변수. 앱을 Finder 에서 띄우면 환경이 빈약하므로 최소한을 채운다.
enum ProcessEnvironment {
    static func base() -> [String: String] {
        var env = LaunchPlanner.sanitized(ProcessInfo.processInfo.environment)
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["TERM_PROGRAM"] = "Symboard"
        // 앱 번들 안에서 상속될 수 있는 값은 지운다.
        env.removeValue(forKey: "SYMBOARD_HOME")
        return env
    }

    static var userShell: String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], !s.isEmpty { return s }
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
        return "/bin/zsh"
    }
}
