import Darwin
import Foundation
import SwiftTerm
import SymboardCore

// symboard-agentd: 콘솔(PTY 와 자식 프로세스)을 앱 밖에서 들고 있는 백그라운드 프로그램(13차).
// 앱이 꺼져도 콘솔은 계속 돈다. 앱은 유닉스 소켓으로 붙어 출력을 받고 입력을 보낸다(약속은 SymboardCore/Agentd.swift).
// 화면·상태 판정·루프는 앱에 있다. 여기는 일부러 단순하게 둔다. 그래야 앱만 업데이트해도 이 프로그램을 바꿀 일이 드물다.
//
// 쓰는 법: symboard-agentd --socket <경로> --lock <경로> --build <빌드>
// 같은 상태 폴더에 이미 돌고 있으면(잠금 파일) 바로 끝난다.

signal(SIGHUP, SIG_IGN)
signal(SIGPIPE, SIG_IGN)

func argument(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

guard let socketPath = argument("--socket"), let lockPath = argument("--lock") else {
    FileHandle.standardError.write(Data("usage: symboard-agentd --socket <path> --lock <path> [--build <id>]\n".utf8))
    exit(2)
}
let build = argument("--build") ?? "dev"

// 한 상태 폴더에 하나만. 잠금은 프로세스가 끝나면 저절로 풀린다.
// 막 끝나는 옛 agentd 가 아직 쥐고 있을 수 있어 2초까지 다시 해 본다.
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
guard lockFD >= 0 else { exit(1) }
var locked = false
for _ in 0..<40 {
    if flock(lockFD, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
    usleep(50_000)
}
guard locked else { exit(0) }

let queue = DispatchQueue(label: "symboard.agentd")

/// 콘솔 하나. LocalProcess 의 알림은 모두 queue 에서 온다.
final class Session: LocalProcessDelegate {
    let id: UUID
    let startedAt = Date()
    var process: LocalProcess!
    var ring = AgentdOutputRing()
    var cols: Int
    var rows: Int
    var running = false
    var exitCode: Int32?
    var endedAt: Date?
    var atPrompt: Bool?
    var subscribers: [ObjectIdentifier: Client] = [:]
    unowned let daemon: Daemon

    init(id: UUID, cols: Int, rows: Int, daemon: Daemon) {
        self.id = id
        self.cols = max(2, cols)
        self.rows = max(2, rows)
        self.daemon = daemon
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    var info: AgentdSessionInfo {
        AgentdSessionInfo(id: id, pid: process.shellPid, running: running, exitCode: exitCode, startedAt: startedAt.timeIntervalSince1970)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        ring.append(slice)
        guard !subscribers.isEmpty else { return }
        let frame = AgentdFrame(.output, id: id, payload: Data(slice)).encoded()
        for c in subscribers.values { c.send(frame) }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        guard daemon.sessions[id] === self, running else { return }
        markExited(exitCode)
    }

    func markExited(_ code: Int32?) {
        running = false
        exitCode = code
        endedAt = Date()
        let frame = AgentdFrame(.exit, id: id, json: AgentdExit(code: code)).encoded()
        for c in subscribers.values { c.send(frame) }
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
    }

    func resize(cols: Int, rows: Int) {
        self.cols = max(2, cols)
        self.rows = max(2, rows)
        guard running, process.childfd >= 0 else { return }
        var size = getWindowSize()
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
    }

    /// 프로세스를 끈다. LocalProcess.terminate 는 셸에만 SIGTERM 을 보내는데, sh 처럼 자식을 기다리는 셸은 바로 끝나지 않고
    /// PTY 도 바로 닫히지 않아 자식이 남는다. 그래서 콘솔의 프로세스 그룹 전체에 SIGHUP·SIGTERM 을 보내고,
    /// 3초 뒤에도 남아 있으면 SIGKILL 한다(forkpty 자식은 세션 우두머리라 그룹 id == pid).
    func stop() {
        let pid = process.shellPid
        process.terminate()
        guard pid > 0 else { return }
        killpg(pid, SIGHUP)
        killpg(pid, SIGTERM)
        queue.asyncAfter(deadline: .now() + 3) {
            if killpg(pid, 0) == 0 { killpg(pid, SIGKILL) }
            var st: Int32 = 0
            _ = waitpid(pid, &st, WNOHANG)
        }
    }

    /// 셸 콘솔이 프롬프트에서 쉬는지. 앞 프로세스 그룹이 셸 자신이면 true.
    func foreground() -> Bool? {
        let fd = process.childfd, pid = process.shellPid
        guard running, fd >= 0, pid > 0 else { return nil }
        let fg = tcgetpgrp(fd)
        guard fg > 0 else { return nil }
        return fg == getpgid(pid)
    }
}

/// 붙어 있는 앱 하나(소켓 연결 하나).
final class Client {
    let fd: Int32
    private var reader = AgentdFrameReader()
    private var outbox = Data()
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var writeArmed = false
    private(set) var closed = false
    unowned let daemon: Daemon

    init(fd: Int32, daemon: Daemon) {
        self.fd = fd
        self.daemon = daemon
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    func start() {
        // 파일은 두 소스의 취소가 모두 끝난 뒤 닫는다(먼저 닫으면 libdispatch 가 멈춘다).
        var users = 2
        let fd = self.fd
        let release = { users -= 1; if users == 0 { Darwin.close(fd) } }
        let rs = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        rs.setEventHandler { [weak self] in self?.readAvailable() }
        rs.setCancelHandler(handler: release)
        rs.resume()
        readSource = rs
        let ws = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        ws.setEventHandler { [weak self] in self?.flush() }
        ws.setCancelHandler(handler: release)
        writeSource = ws
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(fd, &buf, buf.count)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { close(); return }
        guard n > 0 else { return }
        do {
            for f in try reader.feed(Data(buf[0..<n])) { daemon.handle(f, from: self) }
        } catch {
            close()
        }
    }

    func send(_ frame: AgentdFrame) { send(frame.encoded()) }

    func send(_ data: Data) {
        guard !closed else { return }
        outbox.append(data)
        // 앱이 읽지 않고 멈춰 있으면 끊는다. 다시 붙으면 최근 출력부터 다시 받는다.
        if outbox.count > 64 * 1024 * 1024 { close(); return }
        flush()
    }

    private func flush() {
        while !outbox.isEmpty {
            let n = outbox.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 { outbox.removeFirst(n); continue }
            if n < 0 && (errno == EAGAIN || errno == EINTR) { break }
            close()
            return
        }
        if outbox.isEmpty, writeArmed { writeSource?.suspend(); writeArmed = false }
        if !outbox.isEmpty, !writeArmed { writeSource?.resume(); writeArmed = true }
    }

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        // 멈춘 소스는 취소 전에 다시 켜야 한다.
        if !writeArmed { writeSource?.resume() }
        writeSource?.cancel()
        daemon.clientClosed(self)
    }
}

final class Daemon {
    let socketPath: String
    let build: String
    init(socketPath: String, build: String) {
        self.socketPath = socketPath
        self.build = build
    }

    var sessions: [UUID: Session] = [:]
    var clients: [ObjectIdentifier: Client] = [:]
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var idleSince: Date? = Date()

    func start() {
        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { exit(1) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { exit(1) }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            p.copyBytes(from: bytes)
            p[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { exit(1) }
        chmod(socketPath, 0o600)
        guard listen(listenFD, 16) == 0 else { exit(1) }
        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        acceptSource = src

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func acceptOne() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        let c = Client(fd: fd, daemon: self)
        clients[ObjectIdentifier(c)] = c
        c.start()
        idleSince = nil
    }

    func clientClosed(_ c: Client) {
        clients[ObjectIdentifier(c)] = nil
        for s in sessions.values { s.subscribers[ObjectIdentifier(c)] = nil }
    }

    func handle(_ f: AgentdFrame, from c: Client) {
        // 모르는 종류는 버린다(약속은 덧붙이기만 한다).
        guard let kind = f.kind else { return }
        switch kind {
        case .hello:
            c.send(AgentdFrame(.helloReply, json: AgentdHello(build: build, pid: getpid())))
        case .list:
            c.send(AgentdFrame(.sessions, json: sessions.values.map(\.info)))
        case .spawn:
            guard let spec = f.decode(AgentdSpawn.self) else {
                c.send(AgentdFrame(.error, id: f.id, json: AgentdError(message: "bad spawn")))
                return
            }
            if let old = sessions[f.id], old.running { old.stop() }
            let s = Session(id: f.id, cols: spec.cols, rows: spec.rows, daemon: self)
            sessions[f.id] = s
            s.subscribers[ObjectIdentifier(c)] = c
            s.process.startProcess(executable: spec.executable, args: spec.args, environment: spec.env,
                                   execName: nil, currentDirectory: spec.cwd)
            s.running = s.process.running
            c.send(AgentdFrame(.spawned, id: f.id, json: s.info))
            if !s.running { s.markExited(nil) }
        case .attach:
            guard let s = sessions[f.id] else {
                c.send(AgentdFrame(.exit, id: f.id, json: AgentdExit(code: nil)))
                return
            }
            s.subscribers[ObjectIdentifier(c)] = c
            c.send(AgentdFrame(.replay, id: f.id, payload: s.ring.data))
            if s.running {
                if let p = s.atPrompt { c.send(AgentdFrame(.foreground, id: f.id, json: AgentdForeground(atPrompt: p))) }
            } else {
                c.send(AgentdFrame(.exit, id: f.id, json: AgentdExit(code: s.exitCode)))
            }
        case .detach:
            sessions[f.id]?.subscribers[ObjectIdentifier(c)] = nil
        case .input:
            guard let s = sessions[f.id], s.running else { return }
            s.process.send(data: [UInt8](f.payload)[...])
        case .resize:
            guard let s = sessions[f.id], let size = f.decode(AgentdSize.self) else { return }
            s.resize(cols: size.cols, rows: size.rows)
        case .signal:
            guard let s = sessions[f.id], s.running, let sig = f.decode(AgentdSignal.self)?.sig else { return }
            let pid = s.process.shellPid
            if pid > 0, killpg(getpgid(pid), sig) != 0 { kill(pid, sig) }
        case .kill:
            guard let s = sessions.removeValue(forKey: f.id) else { return }
            if s.running {
                s.stop()
                s.markExited(nil)
            }
        case .close:
            if let s = sessions[f.id], !s.running { sessions[f.id] = nil }
        case .shutdown:
            for s in sessions.values where s.running { s.stop() }
            unlink(socketPath)
            queue.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        case .helloReply, .sessions, .replay, .output, .exit, .foreground, .spawned, .error:
            return
        }
    }

    private func tick() {
        let now = Date()
        for s in sessions.values {
            // 출력 끝(EOF)을 먼저 받으면 LocalProcess 가 종료 알림 없이 멈출 수 있다. 그러면 여기서 끝남으로 본다.
            if s.running, !s.process.running {
                var status: Int32 = 0
                let r = waitpid(s.process.shellPid, &status, WNOHANG)
                s.markExited(r > 0 ? status : nil)
                continue
            }
            let fg = s.foreground()
            if fg != s.atPrompt {
                s.atPrompt = fg
                if let fg {
                    let frame = AgentdFrame(.foreground, id: s.id, json: AgentdForeground(atPrompt: fg)).encoded()
                    for c in s.subscribers.values { c.send(frame) }
                }
            }
        }
        // 끝난 지 사흘 넘은 기록은 버린다(앱을 오래 켜지 않은 경우).
        for (id, s) in sessions where !s.running && s.subscribers.isEmpty {
            if let e = s.endedAt, now.timeIntervalSince(e) > 3 * 24 * 3600 { sessions[id] = nil }
        }
        // 붙은 앱도 맡은 콘솔도 없으면 잠시 뒤 끝낸다. 다음에 앱이 다시 띄운다.
        if clients.isEmpty && sessions.isEmpty {
            if let since = idleSince {
                if now.timeIntervalSince(since) > 60 { unlink(socketPath); exit(0) }
            } else {
                idleSince = now
            }
        } else {
            idleSince = nil
        }
    }
}

let daemon = Daemon(socketPath: socketPath, build: build)
queue.async { daemon.start() }
dispatchMain()
