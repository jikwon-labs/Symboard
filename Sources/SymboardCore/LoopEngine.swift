import Foundation

/// 루프 규칙 하나의 실행 중 상태. 디스크에는 저장하지 않는다.
public struct LoopRuntime: Sendable {
    public var startedAt: Date
    public var lastFired: Date?
    /// 아직 확인하지 않은 최근 출력(조각 경계에 걸친 문구도 찾도록 모아 둔다).
    public var pending: String = ""

    public init(startedAt: Date = Date()) { self.startedAt = startedAt }
}

public enum LoopDecision: Equatable, Sendable {
    case none
    case fire
    /// 목표 문구가 나왔거나 최대 횟수에 닿아 끈다.
    case stop(reason: String)
}

public enum LoopEngine {
    /// 같은 규칙이 연달아 터지지 않게 두는 최소 간격(초).
    public static let cooldown: TimeInterval = 3

    /// - Parameters:
    ///   - lastOutputAt: 노드의 마지막 출력 시각. 유휴 조건에서 "보낸 뒤 다시 일했는가"를 본다.
    ///   - idleSeconds: 마지막 출력 뒤 지난 초.
    public static func evaluate(rule: LoopRule, runtime: inout LoopRuntime, now: Date,
                                idleSeconds: TimeInterval, lastOutputAt: Date?) -> LoopDecision {
        guard rule.enabled else { runtime.pending = ""; return .none }
        // 우리가 보낸 문장이 화면에 다시 찍힌 것은 목표·출력 조건에서 뺀다.
        var text = runtime.pending
        if !rule.message.isEmpty { text = text.replacingOccurrences(of: rule.message, with: "") }
        runtime.pending = String(runtime.pending.suffix(400))

        if (rule.goalMode ?? "text") == "text", !rule.goal.isEmpty, text.localizedCaseInsensitiveContains(rule.goal) {
            runtime.pending = ""
            return .stop(reason: "goal")
        }
        if rule.useMaxRuns != false && rule.runCount >= rule.maxRuns { return .stop(reason: "max runs") }
        if let limit = rule.timeLimit, now.timeIntervalSince(runtime.startedAt) >= limit { return .stop(reason: "time limit") }
        if let last = runtime.lastFired, now.timeIntervalSince(last) < cooldown { return .none }

        switch rule.trigger {
        case .interval(let seconds):
            let base = runtime.lastFired ?? runtime.startedAt
            guard now.timeIntervalSince(base) >= seconds else { return .none }
        case .idle(let seconds):
            guard idleSeconds >= seconds else { return .none }
            // 보낸 뒤 노드가 한 번도 출력하지 않았으면 다시 보내지 않는다.
            if let last = runtime.lastFired, (lastOutputAt ?? .distantPast) <= last { return .none }
        case .output(let pattern):
            guard !pattern.isEmpty, text.localizedCaseInsensitiveContains(pattern) else { return .none }
            runtime.pending = ""
        }
        runtime.lastFired = now
        return .fire
    }
}

/// 루프 설정을 한 문장으로. 생성 창 아래와 목록 줄에 쓴다.
public enum LoopSummary {
    public static func interval(_ s: Double) -> String {
        if s >= 3600, s.truncatingRemainder(dividingBy: 3600) == 0 { return "\(Int(s / 3600)) h" }
        if s >= 60, s.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(s / 60)) min" }
        return "\(Int(s)) s"
    }

    public static func when(_ t: LoopTrigger) -> String {
        switch t {
        case .interval(let s): return "Every \(interval(s))"
        case .idle: return "Whenever a console goes idle"
        case .output(let p): return "Whenever output contains \"\(p)\""
        }
    }

    public static func agentName(_ id: String?) -> String {
        switch id { case "codex": return "Codex"; default: return "Claude" }
    }

    /// 예: "Every 15 min, the instruction is sent to every console on the board, until Claude judges the goal met."
    public static func sentence(_ r: LoopRule, consoleCount: Int) -> String {
        var s = when(r.trigger) + ", the instruction is sent to "
        if r.targetAll == true { s += "every console on the board" }
        else { s += consoleCount == 1 ? "1 console" : "\(consoleCount) consoles" }
        var stops: [String] = []
        if r.useMaxRuns != false { stops.append("\(r.maxRuns) runs") }
        if let t = r.timeLimit { stops.append(interval(t)) }
        switch r.goalMode ?? "text" {
        case "command": if let c = r.goalCommand, !c.isEmpty { stops.append("`\(c)` passes") }
        case "agent": if !r.goal.isEmpty { stops.append("\(agentName(r.goalAgent)) judges the goal met") }
        default: if !r.goal.isEmpty { stops.append("output shows \"\(r.goal)\"") }
        }
        if !stops.isEmpty { s += ", until " + stops.joined(separator: " or ") }
        return s + "."
    }

    /// 시간당 대략 보내는 수(간격 조건만). 아니면 nil.
    public static func perHour(_ r: LoopRule, consoleCount: Int) -> Double? {
        guard case .interval(let s) = r.trigger, s > 0 else { return nil }
        return 3600 / s * Double(max(consoleCount, 1))
    }

    /// 다음 실행까지 남은 초(간격 조건만).
    public static func secondsUntilNext(_ r: LoopRule, startedAt: Date, lastFired: Date?, now: Date) -> Double? {
        guard r.enabled, case .interval(let s) = r.trigger else { return nil }
        return max(0, (lastFired ?? startedAt).addingTimeInterval(s).timeIntervalSince(now))
    }
}
