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

    /// Ctrl+글자는 SwiftTerm 이 charactersIgnoringModifiers 의 글자(c)를 제어 문자로 바꿔 보낸다.
    /// 그런데 입력 소스가 한글이면 그 값이 "ㅊ" 처럼 한글 자모로 와서 SwiftTerm 이 아무것도 보내지 않는다(Ctrl+C 가 안 먹음).
    /// 이때 event.characters 에는 시스템이 만든 제어 문자(Ctrl+C 면 3)가 들어 있으므로 그것을 돌려준다.
    /// keyDown 은 덮어쓸 수 없어 창의 키 감시에서 부른다.
    static func rawControlByte(_ event: NSEvent) -> UInt8? {
        let flags = event.modifierFlags
        return KeyInput.controlByte(control: flags.contains(.control), command: flags.contains(.command), option: flags.contains(.option),
                                    characters: event.characters, ignoringModifiers: event.charactersIgnoringModifiers)
    }

    /// 지난 줄 보기 위치가 바뀔 때(휠·스크롤 막대·입력으로 맨 아래 복귀).
    var onScrolled: (() -> Void)?

    override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        onScrolled?()
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
        view.font = TerminalFont.current
        view.nativeBackgroundColor = Theme.terminalBackground
        view.nativeForegroundColor = Theme.text
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
        try? FileManager.default.removeItem(atPath: statusFile.path + ".sid")
        reportedSessionID = nil
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

    /// 다시 띄우기를 기다리는 시작 함수. 옛 프로세스의 종료 알림이 온 뒤에 부른다.
    private var pendingRestart: (() -> Void)?

    /// 프로세스를 끄고, 끝났다는 알림을 받은 뒤 start 를 부른다.
    /// 바로 새로 띄우면 옛 프로세스의 늦은 종료 알림이 새 프로세스를 "끝남" 으로 만들어 입력이 막힌다.
    func restart(then start: @escaping () -> Void) {
        guard running else { start(); return }
        pendingRestart = start
        terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let p = self.pendingRestart else { return }
            self.pendingRestart = nil
            p()
        }
    }

    /// 앞서 보낸 입력의 Enter 가 끝나는 시각. 연달아 보낸 입력이 섞이지 않게 뒤로 미룬다.
    private var busyUntil = Date.distantPast

    /// 사용자가 친 것처럼 문자열을 보낸다. submit 이면 Enter 까지 보낸다.
    func sendText(_ text: String, submit: Bool) {
        guard running else { return }
        let wait = max(0, busyUntil.timeIntervalSinceNow)
        busyUntil = Date().addingTimeInterval(wait + (submit ? 0.35 : 0.05))
        let deliver = { [weak self] in
            guard let self, self.running else { return }
            // 여러 줄은 bracketed paste 로 감싸서 CLI 가 한 번에 받게 한다. 프로그램이 그 모드를 켰을 때만.
            if text.contains("\n") && self.view.getTerminal().bracketedPasteMode {
                self.view.send(txt: "\u{1b}[200~" + text + "\u{1b}[201~")
            } else {
                self.view.send(txt: text)
            }
            self.tracker.noteInput()
            if submit {
                // CLI 가 붙여넣기를 처리할 시간을 조금 준 뒤 Enter.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.view.send(txt: "\r")
                }
            }
        }
        if wait > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: deliver) } else { deliver() }
    }

    /// 자식 프로세스 그룹에 신호를 보낸다(일시정지 SIGSTOP, 재개 SIGCONT).
    func signal(_ sig: Int32) -> Bool {
        let pid = view.process.shellPid
        guard running, pid > 0 else { return false }
        paused = sig == SIGSTOP
        return killpg(getpgid(pid), sig) == 0 || kill(pid, sig) == 0
    }

    private(set) var paused = false

    /// 일반 셸이면 true. 출력 대신 "앞에 도는 프로세스" 로 쉬는 중인지 본다.
    var isPlainShell = false

    func currentStatus(now: Date = Date()) -> NodeStatus {
        pollStatusFile()
        return tracker.status(now: now, shellAtPrompt: isPlainShell ? shellAtPrompt() : nil)
    }

    /// 1초마다 부르는 최종 판정. 화면 끝 글자로 선택 대기를 잡고, 끝낸 일을 Done 으로 남긴다.
    func resolveStatus(now: Date = Date()) -> NodeStatus {
        pollStatusFile()
        if isPlainShell { return tracker.resolve(now: now, shellAtPrompt: shellAtPrompt()) }
        if view.window?.firstResponder === view { tracker.acknowledge() }
        let st = tracker.resolve(now: now, screen: running ? screenText() : nil)
        lastResolved = st
        return st
    }

    /// 마지막 최종 판정(넘겨주기·디버그용).
    private(set) var lastResolved: NodeStatus?

    /// 사용자가 이 노드를 봤다(선택·Go to). Done 을 푼다.
    func acknowledge() { tracker.acknowledge() }

    /// 터미널의 앞 프로세스 그룹이 셸 자신이면 프롬프트에서 입력을 기다리는 중이다.
    private func shellAtPrompt() -> Bool? {
        let fd = view.process.childfd, pid = view.process.shellPid
        guard running, fd >= 0, pid > 0 else { return nil }
        let fg = tcgetpgrp(fd)
        guard fg > 0 else { return nil }
        return fg == getpgid(pid)
    }

    func idleSeconds(now: Date = Date()) -> TimeInterval { tracker.idleSeconds(now: now) }

    /// 화면에 보이는 터미널 내용을 텍스트로.
    func screenText() -> String {
        let term = view.getTerminal()
        var lines: [String] = []
        for row in 0..<term.rows {
            guard let line = term.getLine(row: row) else { continue }
            // 한 번도 쓰지 않은 칸은 NUL 로 나온다. 글자 사이 빈칸이므로 공백으로 바꾼다.
            lines.append(line.translateToString(trimRight: true).replacingOccurrences(of: "\u{0}", with: " "))
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
        // claude 가 실제로 쓰는 세션 id(훅이 적어 둔 것). 다르면 알려서 이어하기가 그 id 를 쓰게 한다.
        if let raw = try? String(contentsOfFile: statusFile.path + ".sid", encoding: .utf8),
           let sid = LaunchPlanner.hookSessionID(raw), sid != reportedSessionID {
            reportedSessionID = sid
            onSessionID?(sid)
        }
    }

    private var reportedSessionID: String?
    /// 훅이 알려 준 claude 세션 id.
    var onSessionID: ((String) -> Void)?

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
            if let p = pendingRestart {
                // 다시 띄우려고 끈 옛 프로세스. 끝남으로 기록하지 않고 새로 띄운다.
                pendingRestart = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { p() }
                return
            }
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
