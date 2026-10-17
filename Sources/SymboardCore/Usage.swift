import Foundation

/// 로컬 세션 로그에서 읽은 토큰 사용량.
public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }
}

public struct UsageRecord: Equatable, Sendable {
    /// 로컬 날짜 yyyy-MM-dd.
    public var day: String
    public var agent: AgentKind
    public var counts: TokenCounts
}

/// 형식은 디스크에서 직접 확인했다.
/// - claude: ~/.claude/projects/<폴더>/<세션>.jsonl, type=assistant 줄의 message.usage. 한 응답이 여러 줄로 나뉘어
///   같은 usage 가 반복되므로 message.id + requestId 로 한 번만 센다.
/// - codex: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, type=event_msg / payload.type=token_count 의
///   info.total_token_usage(누적). 누적값이 늘어난 만큼을 그 시각의 사용량으로 본다.
public enum UsageParser {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func day(fromISO s: String?, fallback: String) -> String {
        guard let s else { return fallback }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return dayFormatter.string(from: d) }
        return fallback
    }

    public static func claude(jsonl: String, fallbackDay: String, seen: inout Set<String>) -> [UsageRecord] {
        claude(data: Data(jsonl.utf8), fallbackDay: fallbackDay, seen: &seen)
    }

    /// 큰 로그를 빨리 읽으려고 줄 전체를 JSON 으로 풀지 않고, 바이트로 거른 뒤 usage 객체만 푼다.
    public static func claude(data: Data, fallbackDay: String, seen: inout Set<String>) -> [UsageRecord] {
        var out: [UsageRecord] = []
        let assistant = Data(#""type":"assistant""#.utf8)
        let usageKey = Data(#""usage":{"#.utf8)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lineStart = 0
            let n = bytes.count
            while lineStart < n {
                var lineEnd = lineStart
                while lineEnd < n && bytes[lineEnd] != 0x0A { lineEnd += 1 }
                defer { lineStart = lineEnd + 1 }
                let line = Data(bytes: raw.baseAddress! + lineStart, count: lineEnd - lineStart)
                guard let u = line.range(of: usageKey), line.range(of: assistant) != nil else { continue }
                // usage 객체 끝(괄호 짝)을 찾는다.
                var depth = 0, i = u.upperBound - 1, end = -1
                var inString = false, escaped = false
                while i < line.endIndex {
                    let c = line[i]
                    if inString {
                        if escaped { escaped = false } else if c == 0x5C { escaped = true } else if c == 0x22 { inString = false }
                    } else if c == 0x22 { inString = true }
                    else if c == 0x7B { depth += 1 }
                    else if c == 0x7D { depth -= 1; if depth == 0 { end = i; break } }
                    i += 1
                }
                guard end > 0, let usage = try? JSONSerialization.jsonObject(with: line[(u.upperBound - 1)...end]) as? [String: Any] else { continue }
                let text = String(decoding: line, as: UTF8.self)
                let key = "\(messageID(text) ?? UUID().uuidString)|\(field(text, "\"requestId\":\"") ?? "")"
                guard seen.insert(key).inserted else { continue }
                let c = TokenCounts(input: usage["input_tokens"] as? Int ?? 0, output: usage["output_tokens"] as? Int ?? 0,
                                    cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                                    cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
                out.append(UsageRecord(day: day(fromISO: field(text, "\"timestamp\":\""), fallback: fallbackDay), agent: .claude, counts: c))
            }
        }
        return out
    }

    /// prefix 바로 뒤부터 다음 따옴표까지.
    static func field(_ text: String, _ prefix: String, from: String.Index? = nil) -> String? {
        guard let r = text.range(of: prefix, range: (from ?? text.startIndex)..<text.endIndex),
              let q = text[r.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(text[r.upperBound..<q])
    }

    /// "message": 뒤 처음 나오는 "id".
    static func messageID(_ text: String) -> String? {
        guard let m = text.range(of: "\"message\":") else { return nil }
        return field(text, "\"id\":\"", from: m.upperBound)
    }

    public static func codex(jsonl: String, fallbackDay: String) -> [UsageRecord] {
        var out: [UsageRecord] = []
        var prev = TokenCounts()
        for line in jsonl.split(separator: "\n") where line.contains("token_count") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let p = obj["payload"] as? [String: Any], p["type"] as? String == "token_count",
                  let info = p["info"] as? [String: Any], let t = info["total_token_usage"] as? [String: Any] else { continue }
            // codex 의 input_tokens 는 캐시 읽기를 포함하므로 뺀다.
            let cached = t["cached_input_tokens"] as? Int ?? 0
            let cur = TokenCounts(input: max(0, (t["input_tokens"] as? Int ?? 0) - cached), output: t["output_tokens"] as? Int ?? 0,
                                  cacheRead: cached, cacheWrite: t["cache_write_input_tokens"] as? Int ?? 0)
            let delta = TokenCounts(input: max(0, cur.input - prev.input), output: max(0, cur.output - prev.output),
                                    cacheRead: max(0, cur.cacheRead - prev.cacheRead), cacheWrite: max(0, cur.cacheWrite - prev.cacheWrite))
            if cur.total >= prev.total { prev = cur }
            if delta.total > 0 {
                out.append(UsageRecord(day: day(fromISO: obj["timestamp"] as? String, fallback: fallbackDay), agent: .codex, counts: delta))
            }
        }
        return out
    }

    /// 날짜 → 에이전트 → 합계.
    public static func aggregate(_ records: [UsageRecord]) -> [String: [AgentKind: TokenCounts]] {
        var out: [String: [AgentKind: TokenCounts]] = [:]
        for r in records { out[r.day, default: [:]][r.agent, default: TokenCounts()] = out[r.day, default: [:]][r.agent, default: TokenCounts()] + r.counts }
        return out
    }
}
