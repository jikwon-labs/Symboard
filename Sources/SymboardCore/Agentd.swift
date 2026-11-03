import Foundation

/// 콘솔을 앱 밖에서 돌리는 백그라운드 프로그램(symboard-agentd, 13차)과 앱 사이의 약속.
///
/// - agentd 는 PTY 와 자식 프로세스, 최근 출력만 들고 있다. 화면·상태 판정·루프는 전부 앱에 있다.
/// - 앱을 꺼도 agentd 와 콘솔은 계속 돈다. 앱을 다시 켜면 소켓으로 붙어 최근 출력을 다시 받고 이어서 본다.
/// - 업데이트: agentd 는 버전별 폴더에 복사해서 띄우므로 앱 번들을 바꿔도 돌던 agentd 는 그대로다.
///   새 앱은 옛 agentd 에 그대로 붙는다. 그래서 이 약속은 **늘 덧붙이기만 한다**:
///   메시지 종류를 새로 더할 수는 있어도 있던 것의 뜻·모양을 바꾸지 않는다. 모르는 종류는 양쪽 다 버린다.
///   agentd 가 맡은 콘솔이 하나도 없을 때만 새 버전으로 바꾼다(`AgentdUpgrade`).
public enum Agentd {
    /// 덧붙이기만 하므로 거의 오르지 않는다. 오르면 "이 기능은 옛 agentd 에 없다" 를 가리는 데만 쓴다.
    public static let protocolVersion = 1
    public static let executableName = "symboard-agentd"
    /// 한 프레임 최대 크기. 넘으면 연결을 끊는다(잘못된 상대).
    public static let maxFrame = 16 * 1024 * 1024
    /// 콘솔마다 남겨 두는 최근 출력(다시 붙을 때 화면을 되살린다).
    public static let replayBytes = 1024 * 1024
}

// MARK: - 프레임

/// [u32 길이(BE, 뒤 전체)][u8 종류][16바이트 노드 id][내용]. 노드와 상관없는 메시지는 id 가 0 이다.
public struct AgentdFrame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        // 앱 → agentd
        case hello = 1, list = 2, spawn = 3, attach = 4, detach = 5, input = 6, resize = 7, signal = 8
        /// 프로세스를 끄고 기록도 지운다.
        case kill = 9
        /// 끝난 콘솔의 기록을 지운다.
        case close = 10
        /// 모든 콘솔을 끄고 agentd 도 끝낸다.
        case shutdown = 11
        // agentd → 앱
        case helloReply = 64, sessions = 65, replay = 66, output = 67, exit = 68, foreground = 69, spawned = 70, error = 71
    }

    public var rawKind: UInt8
    public var id: UUID
    public var payload: Data

    public var kind: Kind? { Kind(rawValue: rawKind) }

    public static let noID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public init(_ kind: Kind, id: UUID = AgentdFrame.noID, payload: Data = Data()) {
        self.rawKind = kind.rawValue
        self.id = id
        self.payload = payload
    }

    public init(rawKind: UInt8, id: UUID, payload: Data) {
        self.rawKind = rawKind
        self.id = id
        self.payload = payload
    }

    public init<T: Encodable>(_ kind: Kind, id: UUID = AgentdFrame.noID, json: T) {
        self.init(kind, id: id, payload: (try? JSONEncoder().encode(json)) ?? Data())
    }

    public func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: payload) }

    public func encoded() -> Data {
        var d = Data(capacity: 4 + 17 + payload.count)
        let len = UInt32(17 + payload.count)
        d.append(contentsOf: [UInt8(len >> 24 & 0xff), UInt8(len >> 16 & 0xff), UInt8(len >> 8 & 0xff), UInt8(len & 0xff)])
        d.append(rawKind)
        withUnsafeBytes(of: id.uuid) { d.append(contentsOf: $0) }
        d.append(payload)
        return d
    }
}

/// 소켓에서 읽은 조각을 모아 프레임으로 자른다.
public struct AgentdFrameReader: Sendable {
    public enum ReadError: Error, Equatable { case tooLarge(Int) }
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ chunk: Data) throws -> [AgentdFrame] {
        buffer.append(chunk)
        var out: [AgentdFrame] = []
        var start = buffer.startIndex
        while buffer.endIndex - start >= 4 {
            let len = Int(buffer[start]) << 24 | Int(buffer[start + 1]) << 16 | Int(buffer[start + 2]) << 8 | Int(buffer[start + 3])
            guard len >= 17, len <= Agentd.maxFrame else { throw ReadError.tooLarge(len) }
            guard buffer.endIndex - start >= 4 + len else { break }
            let body = start + 4
            var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: buffer[(body + 1)..<(body + 17)]) }
            out.append(AgentdFrame(rawKind: buffer[body], id: UUID(uuid: raw), payload: Data(buffer[(body + 17)..<(body + len)])))
            start = body + len
        }
        buffer = start == buffer.endIndex ? Data() : Data(buffer[start...])
        return out
    }
}

// MARK: - 내용

public struct AgentdHello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    /// 실행 파일 내용으로 만든 값. 앱과 agentd 가 같은 빌드인지 본다.
    public var build: String
    public var pid: Int32
    public init(protocolVersion: Int = Agentd.protocolVersion, build: String, pid: Int32) {
        self.protocolVersion = protocolVersion
        self.build = build
        self.pid = pid
    }
}

public struct AgentdSpawn: Codable, Equatable, Sendable {
    public var executable: String
    public var args: [String]
    public var env: [String]
    public var cwd: String
    public var cols: Int
    public var rows: Int
    public init(executable: String, args: [String], env: [String], cwd: String, cols: Int, rows: Int) {
        self.executable = executable
        self.args = args
        self.env = env
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
    }
}

public struct AgentdSessionInfo: Codable, Equatable, Sendable {
    public var id: UUID
    public var pid: Int32
    public var running: Bool
    public var exitCode: Int32?
    public var startedAt: Double
    public init(id: UUID, pid: Int32, running: Bool, exitCode: Int32?, startedAt: Double) {
        self.id = id
        self.pid = pid
        self.running = running
        self.exitCode = exitCode
        self.startedAt = startedAt
    }
}

public struct AgentdSize: Codable, Equatable, Sendable {
    public var cols: Int
    public var rows: Int
    public init(cols: Int, rows: Int) { self.cols = cols; self.rows = rows }
}

public struct AgentdSignal: Codable, Equatable, Sendable {
    public var sig: Int32
    public init(sig: Int32) { self.sig = sig }
}

public struct AgentdExit: Codable, Equatable, Sendable {
    public var code: Int32?
    public init(code: Int32?) { self.code = code }
}

/// 터미널 앞 프로세스 그룹이 셸 자신인지(셸 콘솔이 프롬프트에서 쉬는 중인지). 바뀔 때만 보낸다.
public struct AgentdForeground: Codable, Equatable, Sendable {
    public var atPrompt: Bool
    public init(atPrompt: Bool) { self.atPrompt = atPrompt }
}

public struct AgentdError: Codable, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

// MARK: - 최근 출력

/// 콘솔마다 최근 출력을 정해진 크기까지 남긴다. 넘치면 앞을 잘라내되, 이스케이프 열 한가운데서 시작하지 않게
/// 잘라낸 자리 다음 줄바꿈부터 남긴다(4KB 안에 없으면 그냥 자른다).
public struct AgentdOutputRing: Sendable {
    public let capacity: Int
    public private(set) var data = Data()

    public init(capacity: Int = Agentd.replayBytes) { self.capacity = capacity }

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        data.append(contentsOf: bytes)
        guard data.count > capacity else { return }
        var cut = data.count - capacity * 3 / 4
        let limit = min(data.count, cut + 4096)
        if let nl = data[(data.startIndex + cut)..<(data.startIndex + limit)].firstIndex(of: 0x0a) {
            cut = nl - data.startIndex + 1
        }
        data = Data(data[(data.startIndex + cut)...])
    }
}

// MARK: - 경로·버전

public enum AgentdPaths {
    /// 상태 폴더마다 agentd 하나(시험 인스턴스 SYMBOARD_HOME 끼리 섞이지 않게).
    /// 유닉스 소켓 경로는 104바이트 아래여야 해서 길면 임시 폴더의 해시 이름을 쓴다.
    public static func socket(directory: String, temporary: String) -> String {
        let p = (directory as NSString).appendingPathComponent("agentd.sock")
        if p.utf8.count < 104 { return p }
        return (temporary as NSString).appendingPathComponent("symboard-agentd-\(fnv(directory.utf8)).sock")
    }

    public static func lock(directory: String) -> String {
        (directory as NSString).appendingPathComponent("agentd.lock")
    }

    /// 버전별 실행 파일 자리: <상태 폴더>/agentd/<빌드>/symboard-agentd.
    /// 앱 번들 안에서 바로 띄우지 않는다. 업데이트가 번들을 통째로 바꿔도 돌던 agentd 는 제 파일로 계속 돈다.
    public static func installed(directory: String, build: String) -> String {
        ((directory as NSString).appendingPathComponent("agentd/\(build)") as NSString).appendingPathComponent(Agentd.executableName)
    }

    /// 실행 파일 내용의 FNV-1a 해시(실행마다 같은 값).
    public static func buildID(of data: Data) -> String { fnv(data) }

    static func fnv(_ bytes: some Sequence<UInt8>) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}

public enum AgentdUpgrade {
    public enum Decision: Equatable, Sendable {
        /// 지금 agentd 를 그대로 쓴다.
        case use
        /// 맡은 콘솔이 없는 옛 빌드라 끄고 새로 띄운다.
        case replace
    }

    /// 다른 빌드라도 콘솔(끝난 것 포함)을 하나라도 맡고 있으면 그대로 쓴다. 약속이 덧붙이기만 하므로 새 앱이 옛 agentd 와 통한다.
    public static func decide(daemon: AgentdHello, appBuild: String, sessions: Int) -> Decision {
        daemon.build != appBuild && sessions == 0 ? .replace : .use
    }
}

/// 앱을 끌 때 콘솔을 계속 돌릴지(기본 켬). 끄면 예전처럼 앱과 함께 끝난다.
public enum KeepConsolesPrefs {
    public static let key = "consoles.keepRunning"
    public static func enabled(_ prefs: Prefs) -> Bool { prefs.string(key) != "off" }
    public static func setEnabled(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: key) }
}
