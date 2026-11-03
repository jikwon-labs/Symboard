import AppKit
import SwiftTerm
import SymboardCore

/// 콘솔 화면(TerminalView)과 실제 프로세스 사이. 프로세스를 앱 안에서 돌리거나(LocalLink),
/// 백그라운드 프로그램 symboard-agentd 에 맡긴다(RemoteLink, 13차). 화면 쪽은 어느 쪽인지 모른다.
@MainActor
protocol ConsoleLink: AnyObject {
    var running: Bool { get }
    /// 셸 콘솔이 프롬프트에서 쉬는지(앞 프로세스 그룹이 셸 자신). 모르면 nil.
    var atPrompt: Bool? { get }
    /// 출력. replay 는 다시 붙을 때 받는 지난 출력(상태 판정에 넣지 않는다).
    var onData: ((ArraySlice<UInt8>, _ replay: Bool) -> Void)? { get set }
    var onExit: ((Int32?) -> Void)? { get set }
    func start(_ spec: AgentdSpawn)
    func send(_ bytes: ArraySlice<UInt8>)
    func resize(cols: Int, rows: Int)
    func signal(_ sig: Int32) -> Bool
    /// 프로세스를 끈다. 끝났다는 알림(onExit)은 올 수도, 안 올 수도 있다.
    func terminate()
    /// 프로세스는 두고 이 앱만 떨어진다(앱을 끌 때). 앱 안 프로세스면 아무것도 하지 않는다.
    func detach()
}

// MARK: - 앱 안

/// 예전 방식: 앱이 PTY 를 직접 들고 있어 앱이 끝나면 콘솔도 끝난다.
/// agentd 를 쓰지 않을 때(설정을 껐거나, 실행 파일이 없거나, 띄우지 못했을 때) 쓴다.
@MainActor
final class LocalLink: ConsoleLink, LocalProcessDelegate {
    private var process: LocalProcess!
    private var cols = 80, rows = 24
    var onData: ((ArraySlice<UInt8>, Bool) -> Void)?
    var onExit: ((Int32?) -> Void)?

    init() { process = LocalProcess(delegate: self) }

    var running: Bool { process.running }

    var atPrompt: Bool? {
        let fd = process.childfd, pid = process.shellPid
        guard process.running, fd >= 0, pid > 0 else { return nil }
        let fg = tcgetpgrp(fd)
        guard fg > 0 else { return nil }
        return fg == getpgid(pid)
    }

    func start(_ spec: AgentdSpawn) {
        cols = spec.cols
        rows = spec.rows
        process.startProcess(executable: spec.executable, args: spec.args, environment: spec.env,
                             execName: nil, currentDirectory: spec.cwd)
    }

    func send(_ bytes: ArraySlice<UInt8>) { process.send(data: bytes) }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        guard process.running else { return }
        var size = getWindowSize()
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
    }

    func signal(_ sig: Int32) -> Bool {
        let pid = process.shellPid
        guard process.running, pid > 0 else { return false }
        return killpg(getpgid(pid), sig) == 0 || kill(pid, sig) == 0
    }

    func terminate() { process.terminate() }
    func detach() {}

    nonisolated func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        MainActor.assumeIsolated { onExit?(exitCode) }
    }

    nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { onData?(slice, false) }
    }

    nonisolated func getWindowSize() -> winsize {
        MainActor.assumeIsolated { winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0) }
    }
}

// MARK: - agentd

/// agentd 가 들고 있는 콘솔 하나.
@MainActor
final class RemoteLink: ConsoleLink {
    let id: UUID
    unowned let host: AgentdHost
    private(set) var running = false
    var atPrompt: Bool?
    var onData: ((ArraySlice<UInt8>, Bool) -> Void)?
    var onExit: ((Int32?) -> Void)?

    init(id: UUID, host: AgentdHost) {
        self.id = id
        self.host = host
        host.register(self)
    }

    /// agentd 에 이미 있는 콘솔에 붙는다. 지난 출력이 replay 로 먼저 온다.
    func attach(_ info: AgentdSessionInfo) {
        running = info.running
        host.send(AgentdFrame(.attach, id: id))
    }

    func start(_ spec: AgentdSpawn) {
        guard host.ensureConnected() else {
            onData?(ArraySlice(Array("\u{1b}[31m\(L("Could not reach the console service (symboard-agentd)."))\u{1b}[0m\r\n".utf8)), false)
            onExit?(nil)
            return
        }
        running = true
        atPrompt = nil
        host.send(AgentdFrame(.spawn, id: id, json: spec))
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        guard running else { return }
        host.send(AgentdFrame(.input, id: id, payload: Data(bytes)))
    }

    func resize(cols: Int, rows: Int) {
        host.send(AgentdFrame(.resize, id: id, json: AgentdSize(cols: cols, rows: rows)))
    }

    func signal(_ sig: Int32) -> Bool {
        guard running, host.connected else { return false }
        host.send(AgentdFrame(.signal, id: id, json: AgentdSignal(sig: sig)))
        return true
    }

    func terminate() {
        running = false
        host.send(AgentdFrame(.kill, id: id))
    }

    func detach() { host.send(AgentdFrame(.detach, id: id)) }

    // agentd 에서 온 것.
    func received(_ f: AgentdFrame) {
        switch f.kind {
        case .replay: onData?(ArraySlice(f.payload), true)
        case .output: onData?(ArraySlice(f.payload), false)
        case .foreground: atPrompt = f.decode(AgentdForeground.self)?.atPrompt
        case .exit:
            running = false
            atPrompt = nil
            onExit?(f.decode(AgentdExit.self)?.code)
        default: break
        }
    }

    /// agentd 연결이 끊겼다(agentd 가 죽었다). 프로세스도 같이 끝났다.
    func lost() {
        guard running else { return }
        running = false
        atPrompt = nil
        onExit?(nil)
    }
}

/// agentd 를 찾거나 띄우고 소켓 하나로 모든 콘솔을 주고받는다.
@MainActor
final class AgentdHost {
    let directory: URL
    let socketPath: String
    private var fd: Int32 = -1
    private var reader = AgentdFrameReader()
    private var outbox = Data()
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var writeArmed = false
    private var links: [UUID: Weak] = [:]
    private struct Weak { weak var link: RemoteLink? }

    /// 연결한 agentd 의 인사. 디버그·시험용.
    private(set) var daemon: AgentdHello?
    /// 처음 붙었을 때 agentd 가 이미 맡고 있던 콘솔.
    private(set) var initialSessions: [AgentdSessionInfo] = []

    var connected: Bool { fd >= 0 }

    /// 시험용: SYMBOARD_NO_AGENTD=1 이면 agentd 를 쓰지 않는다(콘솔이 앱 안에서 돈다).
    static let disabledByEnv = ProcessInfo.processInfo.environment["SYMBOARD_NO_AGENTD"] == "1"

    init(directory: URL) {
        self.directory = directory
        socketPath = AgentdPaths.socket(directory: directory.path, temporary: NSTemporaryDirectory())
    }

    /// 앱 번들(또는 빌드 폴더) 안 agentd. 없으면 nil.
    static var bundledExecutable: URL? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let u = dir.appendingPathComponent(Agentd.executableName)
        return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil
    }

    /// 앱이 들고 온 agentd 의 빌드 값(실행 파일 내용의 해시).
    static let bundledBuild: String? = bundledExecutable.flatMap { try? Data(contentsOf: $0) }.map(AgentdPaths.buildID)

    func register(_ link: RemoteLink) { links[link.id] = Weak(link: link) }

    /// 붙어 있지 않으면 붙는다. 돌고 있는 agentd 가 없거나, 맡은 콘솔 없는 옛 빌드면 새로 띄운다.
    @discardableResult
    func ensureConnected() -> Bool {
        if connected { return true }
        guard let build = Self.bundledBuild else { return false }
        if let (cfd, hello, list) = Self.handshake(socketPath) {
            if AgentdUpgrade.decide(daemon: hello, appBuild: build, sessions: list.count) == .use {
                adopt(cfd, hello: hello, sessions: list)
                return true
            }
            // 맡은 콘솔이 없는 옛 빌드: 끄고 새로 띄운다.
            _ = Self.writeAll(cfd, AgentdFrame(.shutdown).encoded())
            close(cfd)
            // 옛 agentd 가 실제로 끝나 잠금을 놓을 때까지 기다린다. 소켓 파일은 먼저 지워지므로 그것만 보면
            // 새 agentd 가 잠금을 못 잡고 바로 끝나, 콘솔이 앱 안에서 도는 예전 방식으로 떨어진다.
            for _ in 0..<60 where kill(hello.pid, 0) == 0 { usleep(50_000) }
        }
        guard launch(build: build) else { return false }
        for _ in 0..<60 {
            if let (cfd, hello, list) = Self.handshake(socketPath) {
                adopt(cfd, hello: hello, sessions: list)
                return true
            }
            usleep(50_000)
        }
        return false
    }

    /// 버전별 폴더에 복사해 둔 agentd 를 앱과 떨어진 세션(setsid)으로 띄운다. 앱이 끝나도 남는다.
    private func launch(build: String) -> Bool {
        guard let src = Self.bundledExecutable else { return false }
        let fm = FileManager.default
        let dest = AgentdPaths.installed(directory: directory.path, build: build)
        if !fm.isExecutableFile(atPath: dest) {
            let dir = (dest as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let tmp = dest + ".tmp-\(getpid())"
            try? fm.removeItem(atPath: tmp)
            guard (try? fm.copyItem(atPath: src.path, toPath: tmp)) != nil else { return false }
            chmod(tmp, 0o755)
            guard rename(tmp, dest) == 0 else { try? fm.removeItem(atPath: tmp); return false }
            Self.pruneOldBuilds(in: (dir as NSString).deletingLastPathComponent, keep: build)
        }
        let log = directory.appendingPathComponent("agentd.log").path
        let args = [dest, "--socket", socketPath, "--lock", AgentdPaths.lock(directory: directory.path), "--build", build]
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var env = ProcessEnvironment.base()
        env.removeValue(forKey: "SYMBOARD_NO_AGENTD")
        let cargs = args.map { strdup($0) } + [nil]
        let cenv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { cargs.forEach { free($0) }; cenv.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, dest, &actions, &attr, cargs, cenv) == 0
    }

    /// 쓰지 않는 옛 빌드 폴더를 지운다. 돌고 있는 옛 agentd 는 이미 열린 파일로 계속 돈다.
    /// 다만 그 agentd 가 끝난 뒤 다시 쓰일 일이 없으므로 지금 빌드와 최근 둘만 남긴다.
    private static func pruneOldBuilds(in root: String, keep: String) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return }
        let dated = names.filter { $0 != keep }.compactMap { n -> (String, Date)? in
            let p = (root as NSString).appendingPathComponent(n)
            return ((try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date).map { (p, $0) }
        }.sorted { $0.1 > $1.1 }
        for (p, _) in dated.dropFirst(2) { try? fm.removeItem(atPath: p) }
    }

    /// 연결하고 인사·목록을 주고받는다(짧게 막고 기다린다. 같은 맥 안 소켓이라 바로 온다).
    nonisolated static func handshake(_ path: String, timeout: TimeInterval = 1.5) -> (Int32, AgentdHello, [AgentdSessionInfo])? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            p.copyBytes(from: bytes)
            p[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, writeAll(fd, AgentdFrame(.hello).encoded() + AgentdFrame(.list).encoded()) else { close(fd); return nil }
        var reader = AgentdFrameReader()
        var hello: AgentdHello?
        var list: [AgentdSessionInfo]?
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while hello == nil || list == nil {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { close(fd); return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, Int32(left * 1000)) > 0 else { close(fd); return nil }
            let n = read(fd, &buf, buf.count)
            guard n > 0, let frames = try? reader.feed(Data(buf[0..<n])) else { close(fd); return nil }
            for f in frames {
                if f.kind == .helloReply { hello = f.decode(AgentdHello.self) }
                if f.kind == .sessions { list = f.decode([AgentdSessionInfo].self) ?? [] }
            }
        }
        return (fd, hello!, list!)
    }

    nonisolated static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { p in
            var off = 0
            while off < p.count {
                let n = write(fd, p.baseAddress! + off, p.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    private func adopt(_ cfd: Int32, hello: AgentdHello, sessions: [AgentdSessionInfo]) {
        fd = cfd
        daemon = hello
        if initialSessions.isEmpty { initialSessions = sessions }
        reader = AgentdFrameReader()
        outbox = Data()
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        // 파일은 두 소스의 취소가 모두 끝난 뒤 닫는다(먼저 닫으면 libdispatch 가 멈춘다).
        let closer = FDCloser(fd: cfd, users: 2)
        let rs = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        rs.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        rs.setCancelHandler { closer.release() }
        rs.resume()
        readSource = rs
        let ws = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
        ws.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        ws.setCancelHandler { closer.release() }
        writeSource = ws
        writeArmed = false
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 256 * 1024)
        let n = read(fd, &buf, buf.count)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { disconnect(); return }
        guard n > 0 else { return }
        guard let frames = try? reader.feed(Data(buf[0..<n])) else { disconnect(); return }
        for f in frames { links[f.id]?.link?.received(f) }
    }

    func send(_ frame: AgentdFrame) {
        guard connected else { return }
        outbox.append(frame.encoded())
        flush()
    }

    private func flush() {
        while !outbox.isEmpty {
            let n = outbox.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 { outbox.removeFirst(n); continue }
            if n < 0 && (errno == EAGAIN || errno == EINTR) { break }
            disconnect()
            return
        }
        if outbox.isEmpty, writeArmed { writeSource?.suspend(); writeArmed = false }
        if !outbox.isEmpty, !writeArmed { writeSource?.resume(); writeArmed = true }
    }

    /// 남은 것을 보내고 연결을 닫는다. 콘솔은 agentd 에서 계속 돈다(앱을 끌 때).
    func closeConnection() {
        guard connected else { return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        _ = Self.writeAll(fd, outbox)
        outbox = Data()
        teardown()
    }

    private func disconnect() {
        teardown()
        for w in links.values { w.link?.lost() }
    }

    private func teardown() {
        guard connected else { return }
        readSource?.cancel()
        if !writeArmed { writeSource?.resume() }
        writeSource?.cancel()
        readSource = nil
        writeSource = nil
        writeArmed = false
        fd = -1
    }
}

/// 여러 디스패치 소스가 같이 쓰는 파일. 마지막 소스가 취소되면 닫는다. 늘 같은 큐에서 불린다.
final class FDCloser: @unchecked Sendable {
    private let fd: Int32
    private var users: Int
    init(fd: Int32, users: Int) { self.fd = fd; self.users = users }
    func release() {
        users -= 1
        if users == 0 { close(fd) }
    }
}
