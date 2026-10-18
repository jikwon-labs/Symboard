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
    /// 2차에서 더한 값(통계용). 없을 수 있다.
    public var time: Date? = nil
    public var model: String? = nil
    public var session: String? = nil

    public init(day: String, agent: AgentKind, counts: TokenCounts, time: Date? = nil, model: String? = nil, session: String? = nil) {
        self.day = day; self.agent = agent; self.counts = counts; self.time = time; self.model = model; self.session = session
    }

    /// 이 응답이 받은 문맥 크기(입력 + 캐시).
    public var context: Int { counts.input + counts.cacheRead + counts.cacheWrite }
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
        date(fromISO: s).map { dayFormatter.string(from: $0) } ?? fallback
    }

    nonisolated(unsafe) static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    static func date(fromISO s: String?) -> Date? {
        guard let s else { return nil }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
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
                let t = date(fromISO: field(text, "\"timestamp\":\""))
                out.append(UsageRecord(day: t.map { dayFormatter.string(from: $0) } ?? fallbackDay, agent: .claude, counts: c, time: t,
                                       model: field(text, "\"model\":\""), session: field(text, "\"sessionId\":\"")))
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

    public static func codex(jsonl: String, fallbackDay: String, session: String? = nil) -> [UsageRecord] {
        var out: [UsageRecord] = []
        var prev = TokenCounts()
        var model: String?
        for line in jsonl.split(separator: "\n") {
            if model == nil, line.contains("\"turn_context\""), let r = line.range(of: "\"model\":\"") {
                model = line[r.upperBound...].split(separator: "\"").first.map(String.init)
            }
            guard line.contains("token_count") else { continue }
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
                let t = date(fromISO: obj["timestamp"] as? String)
                out.append(UsageRecord(day: t.map { dayFormatter.string(from: $0) } ?? fallbackDay, agent: .codex, counts: delta,
                                       time: t, model: model, session: session))
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

/// 사용량 팝오버 통계. 모두 로컬 로그에서 계산한다(한도 % 는 로그에 없다).
public struct UsageStats: Equatable, Sendable {
    public var totalTokens = 0
    public var sessions = 0
    public var activeDays = 0
    public var favoriteModel: String?
    public var mostActiveDay: String?
    public var longestSession: TimeInterval = 0
    public var longestStreak = 0
    public var currentStreak = 0
    /// 최근 30일 응답 중 문맥이 150k 를 넘은 비율(0~1).
    public var bigContextShare = 0.0
    /// 최근 30일 응답 중 4개 이상 세션이 함께 돌던 때의 비율(0~1).
    public var parallelShare = 0.0
    /// 날짜(yyyy-MM-dd) → 토큰 합.
    public var byDay: [String: Int] = [:]
    /// 지금 5시간 묶음의 시작과 끝(활동이 없으면 nil).
    public var blockStart: Date?
    public var blockEnd: Date?
    public var blockTokens = 0
    /// 최근 7일 토큰.
    public var weekTokens = 0

    public init() {}

    public static func compute(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current) -> UsageStats {
        var s = UsageStats()
        guard !records.isEmpty else { return s }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.calendar = calendar; fmt.timeZone = calendar.timeZone
        var modelOut: [String: Int] = [:]
        var sessionSpan: [String: (Date, Date)] = [:]
        for r in records {
            let t = r.counts.total
            s.totalTokens += t
            s.byDay[r.day, default: 0] += t
            if let m = r.model, !m.isEmpty, !m.hasPrefix("<") { modelOut[m, default: 0] += r.counts.output }
            if let sid = r.session, let time = r.time {
                let cur = sessionSpan[sid] ?? (time, time)
                sessionSpan[sid] = (min(cur.0, time), max(cur.1, time))
            }
            if let time = r.time, now.timeIntervalSince(time) <= 7 * 86400 { s.weekTokens += t }
        }
        s.sessions = sessionSpan.count
        s.longestSession = sessionSpan.values.map { $0.1.timeIntervalSince($0.0) }.max() ?? 0
        s.activeDays = s.byDay.filter { $0.value > 0 }.count
        s.mostActiveDay = s.byDay.max { $0.value < $1.value }?.key
        s.favoriteModel = modelOut.max { $0.value < $1.value }?.key
        // 연속 활동일
        let days = Set(s.byDay.keys)
        var longest = 0, run = 0
        var prev: Date?
        for d in days.sorted() {
            guard let date = fmt.date(from: d) else { continue }
            if let p = prev, calendar.dateComponents([.day], from: p, to: date).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run); prev = date
        }
        s.longestStreak = longest
        var cur = 0
        var day = calendar.startOfDay(for: now)
        if !days.contains(fmt.string(from: day)) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(fmt.string(from: day)) { cur += 1; day = calendar.date(byAdding: .day, value: -1, to: day)! }
        s.currentStreak = cur
        // 최근 30일 비율들
        let recent = records.filter { ($0.time.map { now.timeIntervalSince($0) <= 30 * 86400 }) ?? false }
        if !recent.isEmpty {
            s.bigContextShare = Double(recent.filter { $0.context > 150_000 }.count) / Double(recent.count)
            let spans = sessionSpan.values.filter { now.timeIntervalSince($0.1) <= 31 * 86400 }
            let parallel = recent.filter { r in spans.filter { $0.0 <= r.time! && r.time! <= $0.1 }.count >= 4 }.count
            s.parallelShare = Double(parallel) / Double(recent.count)
        }
        // 5시간 묶음: 활동 사이가 5시간 넘게 비면 새 묶음, 시작은 정시로 내림.
        let times = records.compactMap(\.time).filter { now.timeIntervalSince($0) <= 2 * 86400 && $0 <= now }.sorted()
        var start: Date?
        var last: Date?
        for t in times {
            if let st = start, let l = last, t.timeIntervalSince(l) < 5 * 3600, t.timeIntervalSince(st) < 5 * 3600 { last = t; continue }
            start = calendar.dateInterval(of: .hour, for: t)?.start ?? t
            last = t
        }
        if let st = start, now.timeIntervalSince(st) < 5 * 3600 {
            s.blockStart = st
            s.blockEnd = st.addingTimeInterval(5 * 3600)
            s.blockTokens = records.filter { ($0.time.map { $0 >= st && $0 <= now }) ?? false }.reduce(0) { $0 + $1.counts.total }
        }
        return s
    }

    /// 3.2K, 12.4M, 1.1B 처럼 줄인 수.
    public static func short(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1e3 { return String(format: "%.0fK", d / 1e3) }
        return "\(n)"
    }
}

/// 위쪽 사용량 알약 문구. 늘 "resets …" 한 가지 꼴로 보인다.
public enum UsagePill {
    public static let placeholder = "resets –:––"

    /// 지금보다 뒤의 가장 가까운 5시간 묶음 끝. 없으면 자리표시.
    public static func text(blockEnds: [Date], now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard let e = blockEnds.filter({ $0 > now }).min() else { return placeholder }
        let f = DateFormatter()
        f.dateFormat = "h:mma"; f.amSymbol = "am"; f.pmSymbol = "pm"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone
        return "resets " + f.string(from: e)
    }
}

/// claude `/usage` 화면에서 읽은 요금제 한도 한 줄.
public struct PlanLimit: Equatable, Sendable {
    public var name: String
    public var percent: Int
    public var resets: String?
    public init(name: String, percent: Int, resets: String?) { self.name = name; self.percent = percent; self.resets = resets }
}

/// claude `/usage` 화면 글자를 읽는다. 로컬 로그에는 한도 % 가 없어서, CLI 가 보여 주는 화면을 그대로 읽는다.
/// 화면 모양(2.1.302):
///   Current session
///   ██████████████▍            29% used
///   Resets 5pm (Asia/Seoul)
///   Current week (all models)
///   █████████                  18% used
///   Resets Oct 22 at 8am (Asia/Seoul)
public enum PlanUsageParser {
    public static func parse(_ screen: String) -> [PlanLimit] {
        let lines = screen.replacingOccurrences(of: "\u{0}", with: " ").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [PlanLimit] = []
        for (i, l) in lines.enumerated() where l.hasPrefix("Current session") || l.hasPrefix("Current week") {
            let name = l.components(separatedBy: "  ").first ?? l
            var percent: Int?
            var resets: String?
            // 같은 줄 또는 아래 세 줄 안에서 "NN% used" 와 "Resets …" 를 찾는다.
            for j in i..<min(lines.count, i + 4) {
                let t = lines[j]
                if j > i, t.hasPrefix("Current ") { break }
                if percent == nil, let r = t.range(of: #"(\d{1,3})% used"#, options: .regularExpression) {
                    percent = Int(t[r].prefix { $0.isNumber })
                }
                if resets == nil, let r = t.range(of: "Resets ") {
                    resets = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if let p = percent { out.append(PlanLimit(name: name.trimmingCharacters(in: .whitespaces), percent: p, resets: resets)) }
        }
        return out
    }
}
