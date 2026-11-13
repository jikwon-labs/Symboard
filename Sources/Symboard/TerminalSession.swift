import AppKit
import SwiftTerm
import SymboardCore

/// SwiftTerm 터미널 뷰. 프로세스는 들고 있지 않다. 입출력은 TerminalSession 이 ConsoleLink 로 주고받는다(13차).
final class SymTerminalView: TerminalView {
    var onUserInput: (() -> Void)?

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
}

/// 노드 하나에 붙은 콘솔 프로세스와 그 상태. 프로세스는 앱 안(LocalLink) 또는 agentd(RemoteLink)에 있다.
@MainActor
final class TerminalSession: NSObject, TerminalViewDelegate {
    let nodeID: UUID
    let view: SymTerminalView
    let link: ConsoleLink
    private(set) var tracker: StatusTracker
    private(set) var plan: LaunchPlan?
    private(set) var running = false
    let statusFile: URL
    private var statusMTime: Date?
    /// 루프·넘겨주기에서 쓰는 최근 출력 텍스트(제어 문자 제거).
    private(set) var recentText = ""
    /// 새 출력 텍스트가 들어올 때 불린다.
    var outputListeners: [UUID: (String) -> Void] = [:]
    /// 받은 그대로의 최근 출력(보기 전용 공유가 새로 들어온 사람에게 다시 보여 준다). 한도는 ShareLink.tailLimit.
    private(set) var rawTail: [UInt8] = []
    /// 받은 그대로의 출력이 들어올 때 불린다(보기 전용 공유).
    var rawListeners: [UUID: (ArraySlice<UInt8>) -> Void] = [:]
    var onTitle: ((String) -> Void)?
    var onExit: ((Int32?) -> Void)?
    private var stripper = ANSIStripper()

    init(nodeID: UUID, statusDirectory: URL, usesHooks: Bool, link: ConsoleLink) {
        self.nodeID = nodeID
        self.link = link
        self.view = SymTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        self.tracker = StatusTracker(usesHooks: usesHooks)
        self.statusFile = statusDirectory.appendingPathComponent(nodeID.uuidString)
        super.init()
        view.terminalDelegate = self
        view.lineHeightScale = TerminalFont.lineHeight
        view.font = TerminalFont.current
        view.nativeBackgroundColor = Theme.terminalBackground
        view.nativeForegroundColor = Theme.terminalText
        // 콘솔 몸통은 두 모드 모두 어둡다(DECISIONS 10차-1). 스크롤 막대·선택 색도 어두운 모드로.
        view.appearance = NSAppearance(named: .darkAqua)
        view.onUserInput = { [weak self] in
            self?.tracker.noteInput()
        }
        link.onData = { [weak self] slice, replay in self?.received(slice, replay: replay) }
        // 그냥 글자로 찍힌 주소의 Cmd+클릭(15차, SwiftTerm 패치 9).
        view.onCommandClickText = { [nodeID] text, index, shift in
            MainWindowController.current?.webLinks.commandClick(text: text, index: index, in: nodeID, external: shift)
        }
        link.onExit = { [weak self] code in self?.processTerminated(exitCode: code) }
    }

    /// 앱 밖(agentd)에서 이미 돌고 있는 콘솔에 붙는다. 지난 출력이 먼저 와서 화면이 되살아난다.
    func attach(_ info: AgentdSessionInfo, plan: LaunchPlan?) {
        guard let remote = link as? RemoteLink else { return }
        self.plan = plan
        missingFolder = nil
        running = info.running
        remote.attach(info)
        // agentd 의 PTY 크기는 지난 앱이 마지막으로 알린 값이다. 앱을 끄기 직전 크기 변경(0.12초 대기 중)이 버려졌거나
        // 꺼진 사이 글꼴·줄 간격이 바뀌면 화면 칸 수와 달라져, claude 가 넓은 폭으로 그린 줄이 접혀 화면이 깨졌다.
        // 붙을 때 지금 칸 수를 한 번 알린다. 크기가 같으면 프로세스에 신호가 가지 않는다.
        if info.running {
            let term = view.getTerminal()
            scheduleResize(cols: term.cols, rows: term.rows)
        }
        if !info.running { tracker.noteExit() }
        endedWhileAway = !info.running
    }

    /// 사용자가 이 콘솔에 마지막으로 직접 친 시각. lead 알림이 쓰다 만 글에 붙지 않게 본다.
    /// sendText 로 넣은 글과 터미널이 스스로 보내는 것(마우스·초점 보고, 질의 응답)은 세지 않는다.
    private(set) var lastUserKey: Date?
    /// sendText 가 글을 넣는 중(이때 나가는 바이트는 사용자가 친 것이 아니다).
    private var injecting = false
    private func inject(_ text: String) {
        injecting = true
        view.send(txt: text)
        injecting = false
    }

    /// 받은 일을 끝낸 횟수(StatusTracker.finishedCount).
    var finishedCount: Int { tracker.finishedCount }

    func start(plan: LaunchPlan, shell: String) {
        self.plan = plan
        missingFolder = nil
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
        let term = view.getTerminal()
        running = true
        link.start(AgentdSpawn(executable: wrapped.executable, args: wrapped.args, env: envList, cwd: cwd,
                               cols: term.cols, rows: term.rows))
    }

    func terminate() {
        guard running else { return }
        running = false
        link.terminate()
    }

    /// 앱이 꺼진 사이 agentd 에서 끝난 콘솔에 붙었다(다시 띄우기 띠를 바로 보인다).
    private(set) var endedWhileAway = false

    /// 프로세스는 그대로 두고 떨어진다(앱을 끌 때 콘솔을 계속 돌리는 경우).
    func detach() { link.detach() }

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
            // 여러 줄은 bracketed paste 로 감싸서 CLI 가 한 번에 받게 한다(줄마다 따로 실행되지 않게).
            // claude·codex 는 늘, 셸 등은 프로그램이 그 모드를 켰을 때만.
            if text.contains("\n") && (self.alwaysBracketedPaste || self.view.getTerminal().bracketedPasteMode) {
                self.inject("\u{1b}[200~" + text + "\u{1b}[201~")
            } else {
                self.inject(text)
            }
            self.tracker.noteInput()
            if submit {
                // CLI 가 붙여넣기를 처리할 시간을 조금 준 뒤 Enter.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.inject("\r")
                }
            }
        }
        if wait > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: deliver) } else { deliver() }
    }

    /// 자식 프로세스 그룹에 신호를 보낸다(일시정지 SIGSTOP, 재개 SIGCONT).
    func signal(_ sig: Int32) -> Bool {
        guard running else { return false }
        paused = sig == SIGSTOP
        return link.signal(sig)
    }

    private(set) var paused = false

    /// claude·codex 처럼 여러 줄을 늘 한 덩어리 붙여넣기로 받아야 하는 CLI.
    var alwaysBracketedPaste = false

    /// 일반 셸이면 true. 출력 대신 "앞에 도는 프로세스" 로 쉬는 중인지 본다.
    var isPlainShell = false

    func currentStatus(now: Date = Date()) -> NodeStatus {
        pollStatusFile()
        return tracker.status(now: now, shellAtPrompt: isPlainShell ? shellAtPrompt() : nil)
    }

    /// 1초마다 부르는 최종 판정. 화면 끝 글자로 선택 대기를 잡고, 끝낸 일을 Done 으로 남긴다.
    /// 폴더가 없어 띄우지 않은 콘솔의 폴더(9차 4번). 있으면 상태는 exited.
    var missingFolder: String?

    /// 폴더가 없어 띄우지 않는다. 홈 폴더로 몰래 넘어가지 않고 콘솔에 알린다.
    func showMissingFolder(_ path: String) {
        missingFolder = path
        view.feed(text: "\u{1b}[33mFolder not found: \(path)\u{1b}[0m\r\n"
                      + "\u{1b}[2mThis console did not start. Open a folder from Home → Open folder, then press Restart.\u{1b}[0m\r\n")
    }

    func resolveStatus(now: Date = Date()) -> NodeStatus {
        if missingFolder != nil, !running { return .exited }
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
        guard running else { return nil }
        return link.atPrompt
    }

    func idleSeconds(now: Date = Date()) -> TimeInterval { tracker.idleSeconds(now: now) }

    /// 지난 줄까지 포함한 끝 n 줄(보드 도구 read_console). 대체 화면(claude 등)이면 지금 화면.
    func transcript(lastLines n: Int) -> String {
        let data = view.getTerminal().getBufferAsData(kind: .active)
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").map { line -> String in
            var l = line.replacingOccurrences(of: "\u{0}", with: " ")
            while l.last == " " { l.removeLast() }
            return l
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.suffix(max(1, n)).joined(separator: "\n")
    }

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

    private func received(_ slice: ArraySlice<UInt8>, replay: Bool) {
        view.feed(byteArray: slice)
        // 다시 붙을 때 받은 지난 출력은 "지금 일하는 중" 으로 치지 않는다.
        if !replay { tracker.noteOutput() }
        // 보기 전용 공유: 지난 출력도 다시 보여 줄 기록에는 넣고, 실시간으로 보내는 것은 새 출력만.
        rawTail.append(contentsOf: slice)
        if rawTail.count > ShareLink.tailLimit { rawTail = ShareLink.trimmedTail(rawTail) }
        if !replay { for l in rawListeners.values { l(slice) } }
        let text = stripper.feed(slice)
        guard !text.isEmpty else { return }
        recentText += text
        // 길이는 utf8.count(바로 나옴)로 본다. 글자 수(count)는 조각마다 처음부터 세어, 대량 출력 때 메인 스레드 시간의 대부분이었다.
        // 한글은 글자당 3바이트라 바이트 기준을 넉넉히 둔다(글자 기준 이전 64,000 / 48,000 과 비슷한 양).
        if recentText.utf8.count > 192_000 { recentText = String(recentText.suffix(48_000)) }
        guard !replay else { return }
        for l in outputListeners.values { l(text) }
    }

    func clearRecentText() { recentText = "" }

    private func processTerminated(exitCode: Int32?) {
        if let p = pendingRestart {
            // 다시 띄우려고 끈 옛 프로세스. 끝남으로 기록하지 않고 새로 띄운다.
            pendingRestart = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { p() }
            return
        }
        // 우리가 끈 프로세스(노드 지우기 등)의 늦은 알림은 버린다.
        guard running else { return }
        running = false
        tracker.noteExit()
        onExit?(exitCode)
    }

    // MARK: TerminalViewDelegate

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { scheduleResize(cols: newCols, rows: newRows) }
    }

    /// 마지막으로 정한 콘솔 크기(아직 프로세스에 알리지 않은 것).
    private var pendingSize: (cols: Int, rows: Int)?
    private var resizeWork: DispatchWorkItem?

    /// 노드 크기를 끄는 동안에는 한 칸 바뀔 때마다 프로세스에 알리지 않고, 멎은 뒤(0.12초) 마지막 크기만 알린다.
    /// 알릴 때마다 claude·codex 가 화면 전체를 다시 그려 보내서, 끄는 내내 큰 출력이 쏟아졌다(성능 점검 2차).
    private func scheduleResize(cols: Int, rows: Int) {
        pendingSize = (cols, rows)
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let size = self.pendingSize else { return }
            self.pendingSize = nil
            self.resizeWork = nil
            self.link.resize(cols: size.cols, rows: size.rows)
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        MainActor.assumeIsolated { onTitle?(title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated {
            view.onUserInput?()
            if !injecting, !TerminalReport.isReportOnly(data) { lastUserKey = Date() }
            link.send(data)
        }
    }

    nonisolated func scrolled(source: TerminalView, position: Double) {
        MainActor.assumeIsolated { view.onScrolled?() }
    }

    /// OSC 8 링크 Cmd+클릭(15차): 앱 안 웹 타일로, Shift 를 같이 누르면 기본 브라우저로.
    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        MainActor.assumeIsolated {
            let external = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            guard let opener = MainWindowController.current?.webLinks else {
                if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                return
            }
            opener.open(link, from: nodeID, external: external)
        }
    }

    nonisolated func bell(source: TerminalView) {}

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let str = String(bytes: content, encoding: .utf8) else { return }
        MainActor.assumeIsolated {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([str as NSString])
        }
    }

    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
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
