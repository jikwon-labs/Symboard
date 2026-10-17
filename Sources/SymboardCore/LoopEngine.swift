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

        if !rule.goal.isEmpty, text.localizedCaseInsensitiveContains(rule.goal) {
            runtime.pending = ""
            return .stop(reason: "goal")
        }
        if rule.runCount >= rule.maxRuns { return .stop(reason: "max runs") }
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
