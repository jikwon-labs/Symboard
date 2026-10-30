import AppKit
import SymboardCore

/// claude 가 보드에 콘솔을 띄우는 도구의 앱 쪽(8차 3번). 상태 폴더의 유닉스 소켓에서 한 줄 요청을 받아
/// 메인 스레드에서 처리하고 한 줄로 답한다. 요청은 `symboard-mcp`(claude 가 띄운 stdio MCP 서버)가 보낸다.
final class BoardToolServer: @unchecked Sendable {
    let socketPath: String
    private var listenFD: Int32 = -1
    /// 실제 처리. 메인 스레드에서 불리고, 답을 줄 때 reply 를 부른다(콘솔이 준비되기를 기다릴 수도 있다).
    var handler: (@MainActor (_ caller: String, _ tool: String, _ args: [String: Any], _ reply: @escaping (String, Bool) -> Void) -> Void)?

    init(directory: URL) {
        socketPath = BoardTools.socketPath(directory: directory.path, temporary: NSTemporaryDirectory())
    }

    /// 앱 번들(또는 빌드 폴더) 안 stdio MCP 서버. 없으면 nil(도구를 붙이지 않는다).
    static var serverExecutable: String? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let p = dir.appendingPathComponent("symboard-mcp").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    func start() {
        // 처음 켜면 상태 폴더가 아직 없을 수 있다(없으면 bind 가 실패한다).
        try? FileManager.default.createDirectory(atPath: (socketPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return }
        chmod(socketPath, 0o600)
        listenFD = fd
        let t = Thread { [weak self] in self?.acceptLoop() }
        t.name = "symboard.boardtools"
        t.start()
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let c = accept(listenFD, nil, nil)
            if c < 0 { if errno == EINTR { continue } else { return } }
            DispatchQueue.global().async { [weak self] in self?.serve(c) }
        }
    }

    private func serve(_ fd: Int32) {
        guard let line = BoardBridge.readLine(fd: fd),
              let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { close(fd); return }
        let caller = obj["caller"] as? String ?? ""
        let tool = obj["tool"] as? String ?? ""
        let args = obj["args"] as? [String: Any] ?? [:]
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var answer = ("", true)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let h = self?.handler else { answer = ("Board tools are off in Symboard settings", true); done.signal(); return }
                h(caller, tool, args) { text, isError in answer = (text, isError); done.signal() }
            }
        }
        _ = done.wait(timeout: .now() + 120)
        let data = BoardBridge.encodeReply(text: answer.0, isError: answer.1)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}
