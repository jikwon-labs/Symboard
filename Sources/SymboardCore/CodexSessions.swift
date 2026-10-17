import Foundation

/// codex 세션 기록(~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) 읽기.
/// 첫 줄은 type=session_meta 이고 payload 에 id·cwd·timestamp 가 있다(디스크에서 직접 확인).
public enum CodexSessions {
    public struct Meta: Equatable, Sendable {
        public var id: String
        public var cwd: String
        public var path: String
    }

    public static func parseMeta(firstLine: String, path: String) -> Meta? {
        guard let data = firstLine.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let id = (payload["id"] as? String) ?? (payload["session_id"] as? String),
              let cwd = payload["cwd"] as? String else { return nil }
        return Meta(id: id, cwd: cwd, path: path)
    }

    public static func firstLine(of path: String, maxBytes: Int = 256 * 1024) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: maxBytes)) ?? Data()
        guard let nl = data.firstIndex(of: 0x0A) else { return String(data: data, encoding: .utf8) }
        return String(data: data[..<nl], encoding: .utf8)
    }

    public static func sessionsRoot(configDir: String?) -> String {
        (configDir ?? NSHomeDirectory() + "/.codex") + "/sessions"
    }

    /// startedAfter 이후 수정된 세션 중 cwd 가 같고 excluded 에 없는 가장 이른 것.
    public static func findSession(root: String, cwd: String, startedAfter: Date, excluded: Set<String>) -> Meta? {
        let fm = FileManager.default
        var found: [(Date, Meta)] = []
        // codex 는 /private/tmp 처럼 실제 경로를 적으므로 양쪽 다 실제 경로로 맞춘다.
        let want = LaunchPlanner.resolvedPath(cwd)
        // 전체를 훑지 않고 시작일 전날부터 오늘까지의 날짜 폴더만 본다.
        var paths: [String] = []
        var day = startedAfter.addingTimeInterval(-86400)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        while day <= Date().addingTimeInterval(86400) {
            let dir = root + "/" + fmt.string(from: day)
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".jsonl") {
                paths.append(dir + "/" + name)
            }
            day = day.addingTimeInterval(86400)
        }
        for path in Set(paths) {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date, mtime >= startedAfter,
                  let line = firstLine(of: path), let meta = parseMeta(firstLine: line, path: path),
                  LaunchPlanner.resolvedPath(meta.cwd) == want, !excluded.contains(meta.id) else { continue }
            let created = (attrs[.creationDate] as? Date) ?? mtime
            found.append((created, meta))
        }
        return found.min { $0.0 < $1.0 }?.1
    }
}
