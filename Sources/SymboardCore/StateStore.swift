import Foundation

public enum StateStoreError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// 앱 상태를 버전 붙은 JSON 으로 읽고 쓴다.
public struct StateStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SYMBOARD_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Symboard", isDirectory: true)
    }

    public var stateURL: URL { directory.appendingPathComponent("state.json") }

    public static func encode(_ state: AppState) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(state)
    }

    public static func decode(_ data: Data) throws -> AppState {
        struct Header: Decodable { var version: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.version <= AppState.currentVersion else {
            throw StateStoreError.unsupportedVersion(header.version)
        }
        // 버전이 올라가면 여기서 이전 형식을 변환한다.
        var state = try JSONDecoder().decode(AppState.self, from: data)
        state.version = AppState.currentVersion
        return state
    }

    public func load() -> AppState {
        guard let data = try? Data(contentsOf: stateURL) else { return .initial() }
        do {
            let state = try Self.decode(data)
            return state.workspaces.isEmpty ? .initial() : state
        } catch {
            // 읽을 수 없는 파일은 지우지 않고 옆으로 치워 둔다.
            let backup = directory.appendingPathComponent("state.broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: stateURL, to: backup)
            return .initial()
        }
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}
