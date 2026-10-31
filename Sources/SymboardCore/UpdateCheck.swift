import Foundation

/// 새 버전 알림. 자동으로 받거나 설치하지 않고, GitHub 최신 릴리스가 지금 버전보다 높으면 위쪽 막대에 알약만 띄운다.
/// 하루에 한 번만 묻고, 설정 "Check for updates" 로 끈다(기본 켬).
public enum UpdateCheck {
    public static let repo = "jikwon-labs/Symboard"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!
    public static let prefKey = "updates.check"
    public static let lastCheckKey = "updates.lastCheck"
    /// 마지막으로 받은 최신 릴리스(태그 \t 주소). 하루 안에 다시 켜도 알약이 바로 보이게 남긴다.
    public static let latestKey = "updates.latest"
    public static let interval: TimeInterval = 24 * 60 * 60

    public struct Release: Equatable, Sendable {
        public var version: String
        public var url: URL
        public init(version: String, url: URL) { self.version = version; self.url = url }
    }

    public static func enabled(_ prefs: Prefs) -> Bool { prefs.string(prefKey) != "off" }
    public static func setEnabled(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: prefKey) }

    /// 마지막 확인에서 하루가 지났는지. 시계가 뒤로 갔으면(미래 시각이 남아 있으면) 다시 묻는다.
    public static func isDue(_ prefs: Prefs, now: Date = Date()) -> Bool {
        let last = prefs.double(lastCheckKey)
        guard last > 0 else { return true }
        let elapsed = now.timeIntervalSince1970 - last
        return elapsed >= interval || elapsed < 0
    }

    /// `releases/latest` 응답에서 태그와 페이지 주소를 꺼낸다. 초안·시험판은 빼고, 모양이 다르면 nil.
    public static func parse(_ data: Data) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              obj["draft"] as? Bool != true, obj["prerelease"] as? Bool != true,
              parseVersion(tag) != nil else { return nil }
        let url = (obj["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        return Release(version: normalized(tag), url: url)
    }

    /// "v1.2.3" → [1, 2, 3]. 빠진 자리는 0 으로 본다. 숫자가 아닌 조각이 있으면 nil.
    public static func parseVersion(_ s: String) -> [Int]? {
        let t = normalized(s)
        guard !t.isEmpty else { return nil }
        var parts: [Int] = []
        for p in t.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(p), n >= 0 else { return nil }
            parts.append(n)
        }
        while parts.count < 3 { parts.append(0) }
        return parts
    }

    /// `candidate` 가 `current` 보다 높은 버전인지.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parseVersion(candidate), let b = parseVersion(current) else { return false }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    public static func normalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("v") || t.hasPrefix("V") ? String(t.dropFirst()) : t
    }

    public static func store(_ r: Release, _ prefs: Prefs, now: Date = Date()) {
        prefs.set(now.timeIntervalSince1970, for: lastCheckKey)
        prefs.set("\(r.version)\t\(r.url.absoluteString)", for: latestKey)
    }

    public static func cached(_ prefs: Prefs) -> Release? {
        guard let s = prefs.string(latestKey) else { return nil }
        let parts = s.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2, let url = URL(string: parts[1]), parseVersion(parts[0]) != nil else { return nil }
        return Release(version: parts[0], url: url)
    }

    /// 알약에 보일 릴리스: 남겨 둔 최신이 지금 버전보다 높을 때만.
    public static func available(_ prefs: Prefs, current: String = Symboard.version) -> Release? {
        guard enabled(prefs), let r = cached(prefs), isNewer(r.version, than: current) else { return nil }
        return r
    }
}
