import Foundation

/// 앱 설정 몇 가지(마지막 폴더·마지막 CLI·창 위치 등)를 상태 폴더 안 prefs.json 에 둔다.
/// UserDefaults 에 두면 SYMBOARD_HOME 을 바꿔도 앞 실행의 값이 따라와서, 새 폴더로 띄워도 예전 프로젝트가 열렸다.
public final class Prefs: @unchecked Sendable {
    public let url: URL
    private var values: [String: String]

    public init(directory: URL) {
        url = directory.appendingPathComponent("prefs.json")
        if let data = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([String: String].self, from: data) {
            values = v
        } else {
            values = [:]
        }
    }

    /// 지금 상태 폴더(SYMBOARD_HOME 또는 기본 폴더)의 설정.
    public static let shared = Prefs(directory: StateStore.defaultDirectory)

    public func string(_ key: String) -> String? { values[key] }

    public func double(_ key: String) -> Double { values[key].flatMap(Double.init) ?? 0 }

    public func set(_ value: String?, for key: String) {
        guard values[key] != value else { return }
        values[key] = value
        save()
    }

    public func set(_ value: Double, for key: String) { set(String(value), for: key) }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(values) { try? data.write(to: url, options: .atomic) }
    }
}
