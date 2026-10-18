import Foundation
import SwiftTerm
import SymboardCore

/// 화면 없는 터미널에 claude 를 띄워 `/usage` 화면을 읽는다. 모델에 질문하지 않으므로 사용량을 쓰지 않는다.
/// 로컬 로그에는 요금제 한도 % 와 초기화 시각이 없어서, CLI 가 보여 주는 값을 그대로 가져온다.
@MainActor
final class PlanUsageProbe {
    private var term: HeadlessTerminal?
    private var started = Date()
    private var phase = 0
    private var timer: Timer?
    private var done: (([PlanLimit], String?) -> Void)?

    var running: Bool { term != nil }
    /// 마지막으로 읽은 화면(디버그 `usageProbe` 로 본다).
    private(set) var lastScreen = ""

    /// cwd 는 이미 신뢰한 폴더여야 한다. 신뢰 확인 화면이 나오면 대신 답하지 않고 그만둔다.
    func run(cwd: String, configDir: String?, completion: @escaping ([PlanLimit], String?) -> Void) {
        guard term == nil else { return }
        done = completion
        let t = HeadlessTerminal(queue: .main, options: TerminalOptions(cols: 110, rows: 60)) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish([], "claude exited") }
        }
        term = t
        var env = ProcessEnvironment.base()
        if let configDir { env["CLAUDE_CONFIG_DIR"] = configDir }
        let shell = ProcessEnvironment.userShell
        let wrapped = LaunchPlanner.shellWrapped(["claude"], shell: shell)
        t.process.startProcess(executable: wrapped.executable, args: wrapped.args,
                               environment: env.map { "\($0.key)=\($0.value)" }, execName: nil,
                               currentDirectory: FileManager.default.fileExists(atPath: cwd) ? cwd : NSHomeDirectory())
        started = Date()
        phase = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func screen() -> String {
        guard let terminal = term?.terminal else { return "" }
        var lines: [String] = []
        for row in 0..<terminal.rows {
            if let line = terminal.getLine(row: row) { lines.append(line.translateToString(trimRight: true)) }
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\u{0}", with: " ")
    }

    private func step() {
        guard let t = term else { return }
        let s = screen()
        lastScreen = s
        let age = Date().timeIntervalSince(started)
        switch phase {
        case 0:
            // 입력창이 뜨기를 기다린다. 선택 화면(폴더 신뢰·첫 실행)이면 대신 고르지 않고 그만둔다.
            if PromptDetector.isWaitingForChoice(s) { finish([], "claude is asking a question in this folder; open it once in a console first"); return }
            if s.contains("? for shortcuts") || s.contains("for shortcuts") || s.contains("/effort") {
                t.send("/usage")
                phase = 1
                started = Date()
            } else if age > 20 { finish([], "claude did not start") }
        case 1:
            if age > 0.8 { t.send("\r"); phase = 2; started = Date() }
        case 2:
            let limits = PlanUsageParser.parse(s)
            // 화면이 다 그려질 시간을 조금 둔다(주간 모델별 줄이 늦게 나온다).
            if limits.contains(where: { $0.resets != nil }) && age > 3 { finish(limits, nil) }
            else if age > 15 { finish(limits, limits.isEmpty ? "could not read /usage" : nil) }
        default: break
        }
    }

    private func finish(_ limits: [PlanLimit], _ error: String?) {
        timer?.invalidate(); timer = nil
        if let t = term {
            term = nil
            t.send("\u{1b}")
            t.send("/exit\r")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { t.process.terminate() }
        }
        let cb = done; done = nil
        cb?(limits, error)
    }
}

/// 화면 없는 터미널에 codex 를 띄워 `/status` 의 한도 줄을 읽는다. 질문하지 않는다.
/// 업데이트 안내는 Esc(건너뛰기)로 닫는다. Enter 는 입력칸에 `/status` 가 보일 때만 보낸다(업데이트 메뉴의 기본값이 "지금 업데이트" 라서).
/// 폴더 신뢰 같은 다른 선택 화면이면 대신 답하지 않고 그만둔다.
@MainActor
final class CodexStatusProbe {
    private var term: HeadlessTerminal?
    private var started = Date()
    private var phase = 0
    private var escapedUpdate = false
    private var timer: Timer?
    private var done: (([PlanLimit], String?) -> Void)?
    private(set) var lastScreen = ""

    var running: Bool { term != nil }

    func run(cwd: String, configDir: String?, completion: @escaping ([PlanLimit], String?) -> Void) {
        guard term == nil else { return }
        done = completion
        let t = HeadlessTerminal(queue: .main, options: TerminalOptions(cols: 120, rows: 50)) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish([], "codex exited") }
        }
        term = t
        var env = ProcessEnvironment.base()
        if let configDir { env["CODEX_HOME"] = configDir }
        let wrapped = LaunchPlanner.shellWrapped(["codex", "--no-daemon"], shell: ProcessEnvironment.userShell)
        t.process.startProcess(executable: wrapped.executable, args: wrapped.args,
                               environment: env.map { "\($0.key)=\($0.value)" }, execName: nil,
                               currentDirectory: FileManager.default.fileExists(atPath: cwd) ? cwd : NSHomeDirectory())
        started = Date()
        phase = 0
        escapedUpdate = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func screen() -> String {
        guard let terminal = term?.terminal else { return "" }
        var lines: [String] = []
        for row in 0..<terminal.rows {
            if let line = terminal.getLine(row: row) { lines.append(line.translateToString(trimRight: true)) }
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\u{0}", with: " ")
    }

    private func step() {
        guard let t = term else { return }
        let s = screen()
        lastScreen = s
        let age = Date().timeIntervalSince(started)
        let updateMenu = s.contains("Update now")
        switch phase {
        case 0:
            if updateMenu {
                if !escapedUpdate { t.send("\u{1b}"); escapedUpdate = true; started = Date() }
                else if age > 5 { finish([], "codex update screen did not close") }
                return
            }
            if PromptDetector.isWaitingForChoice(s) { finish([], "codex is asking a question in this folder; open it once in a console first"); return }
            if s.contains("for shortcuts") || s.contains("Ask Codex") {
                t.send("/status")
                phase = 1
                started = Date()
            } else if age > 20 { finish([], "codex did not start") }
        case 1:
            guard age > 0.8 else { return }
            if updateMenu || !s.contains("/status") { finish([], "codex input not ready"); return }
            t.send("\r"); phase = 2; started = Date()
        case 2:
            let limits = CodexLimitParser.parseStatus(s)
            if !limits.isEmpty && age > 1.5 { finish(limits, nil) }
            else if age > 10 { finish(limits, limits.isEmpty ? "no limits in codex /status" : nil) }
        default: break
        }
    }

    private func finish(_ limits: [PlanLimit], _ error: String?) {
        timer?.invalidate(); timer = nil
        if let t = term {
            term = nil
            t.send("\u{3}")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { t.send("\u{3}") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { t.process.terminate() }
        }
        let cb = done; done = nil
        cb?(limits, error)
    }
}
