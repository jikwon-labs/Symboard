import Foundation

/// Finder·Dock 으로 띄운 앱은 터미널의 PATH 를 물려받지 않는다(/usr/bin:/bin:/usr/sbin:/sbin).
/// 사용자의 로그인·대화형 셸에서 PATH 를 한 번 얻어 오고, 실패하면 흔한 설치 위치를 더한다.
public enum LoginPath {
    public static let beginMarker = "__SYMBOARD_PATH_BEGIN__"
    public static let endMarker = "__SYMBOARD_PATH_END__"

    /// 셸에 넘길 인자. .zshrc 에서만 잡히는 nvm 같은 PATH 를 얻으려면 -l -i 가 필요하다.
    public static func probeArguments() -> [String] {
        ["-l", "-i", "-c", "printf '%s%s%s' '\(beginMarker)' \"$PATH\" '\(endMarker)'"]
    }

    /// 셸 출력에서 표식 사이의 PATH 를 꺼낸다. 프롬프트 테마·인사말 같은 앞뒤 잡음은 버린다.
    public static func parse(_ output: String) -> String? {
        guard let end = output.range(of: endMarker, options: .backwards),
              let begin = output.range(of: beginMarker, options: .backwards, range: output.startIndex..<end.lowerBound)
        else { return nil }
        let path = output[begin.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path.contains("/"), !path.contains("\n") else { return nil }
        return path
    }

    /// 순서를 지키며 겹치는 칸과 빈 칸을 뺀 PATH.
    public static func merge(_ parts: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for part in parts {
            for dir in part.split(separator: ":").map(String.init) where !dir.isEmpty && !seen.contains(dir) {
                seen.insert(dir)
                out.append(dir)
            }
        }
        return out.joined(separator: ":")
    }

    /// 셸에서 못 얻었을 때 더해 볼 흔한 위치(앞쪽이 우선).
    public static func fallbackCandidates(home: String, nvmBin: String?) -> [String] {
        var dirs: [String] = []
        if let nvmBin { dirs.append(nvmBin) }
        dirs += [
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
            "\(home)/.local/share/mise/shims",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/Library/pnpm",
            "\(home)/.local/share/pnpm",
            "\(home)/.npm-global/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
        ]
        return dirs
    }

    /// nvm 의 현재 버전 bin. `alias/default`(예: "24", "v24.1.0", "node") 에 맞는 가장 높은 버전, 없으면 가장 높은 버전.
    public static func nvmBin(home: String, defaultAlias: String?, versions: [String]) -> String? {
        let installed = versions.filter { $0.hasPrefix("v") }.sorted { versionKey($0).lexicographicallyPrecedes(versionKey($1)) }
        guard !installed.isEmpty else { return nil }
        var pick = installed.last!
        if let raw = defaultAlias?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           raw != "node", raw != "stable", !raw.hasPrefix("lts/") {
            let want = raw.hasPrefix("v") ? raw : "v" + raw
            if let m = installed.last(where: { $0 == want || $0.hasPrefix(want + ".") }) { pick = m }
        }
        return "\(home)/.nvm/versions/node/\(pick)/bin"
    }

    static func versionKey(_ v: String) -> [Int] {
        v.dropFirst().split(separator: ".").map { Int($0) ?? 0 }
    }

    /// 셸 결과(없으면 nil: 실패·시간 초과)와 지금 PATH 로 최종 PATH 를 만든다.
    /// 셸이 성공하면 그 PATH 가 앞, 지금 PATH 는 뒤. 실패하면 존재하는 흔한 위치를 앞에 더한다.
    public static func resolve(shellOutput: String?, currentPath: String, home: String, nvmBin: String?,
                               exists: (String) -> Bool) -> (path: String, fromShell: Bool) {
        if let out = shellOutput, let p = parse(out) {
            return (merge([p, currentPath]), true)
        }
        let extra = fallbackCandidates(home: home, nvmBin: nvmBin).filter(exists)
        return (merge([extra.joined(separator: ":"), currentPath]), false)
    }

    /// PATH 에서 실행 파일을 찾는다.
    public static func which(_ name: String, path: String, isExecutable: (String) -> Bool) -> String? {
        if name.contains("/") { return isExecutable(name) ? name : nil }
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let full = "\(dir)/\(name)"
            if isExecutable(full) { return full }
        }
        return nil
    }

    /// 로그인·대화형 셸을 한 번 돌려 표준 출력을 모은다. 끝 표식이 보이거나 셸이 끝나면 멈추고, 시간 초과면 nil.
    /// 셸 설정이 띄운 데몬(예: 프롬프트 테마의 gitstatus)이 파이프를 잡고 있어도 기다리지 않는다.
    public static func runProbe(shell: String, arguments: [String], timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = env["TERM"] ?? "dumb"
        env["SYMBOARD_PATH_PROBE"] = "1"
        p.environment = env
        p.currentDirectoryURL = URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let box = ProbeBox()
        let signal = box.signal
        let endBytes = Data(endMarker.utf8)
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            let finished = box.append(d, until: endBytes)
            if finished { signal() }
        }
        p.terminationHandler = { _ in
            // 남은 출력이 handler 로 들어올 틈을 조금 준다.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { signal() }
        }
        do { try p.run() } catch { return nil }
        let timedOut = box.done.wait(timeout: .now() + timeout) == .timedOut
        pipe.fileHandleForReading.readabilityHandler = nil
        if p.isRunning { p.terminate() }
        let text = String(decoding: box.data, as: UTF8.self)
        if timedOut && parse(text) == nil { return nil }
        return text
    }
}

/// 셸 출력 모으기와 "끝났다" 신호를 스레드 사이에서 안전하게 다룬다.
final class ProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var signalled = false
    let done = DispatchSemaphore(value: 0)

    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }

    /// 빈 조각(EOF)이거나 끝 표식이 보이면 true.
    func append(_ d: Data, until end: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        buffer.append(d)
        return d.isEmpty || buffer.range(of: end) != nil
    }

    func signal() {
        lock.lock(); defer { lock.unlock() }
        if !signalled { signalled = true; done.signal() }
    }
}
