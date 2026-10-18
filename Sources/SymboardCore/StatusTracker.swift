import Foundation

public enum NodeStatus: String, Codable, Sendable {
    case starting
    case working
    case idle
    case waiting
    case exited

    public var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .idle: return "Idle"
        case .waiting: return "Needs input"
        case .exited: return "Exited"
        }
    }
}

/// 노드 하나의 상태를 판정한다. 훅 신호가 있으면 그것을 따르고, 없으면 마지막 출력 시각으로 추정한다.
public struct StatusTracker: Sendable {
    public var usesHooks: Bool
    /// 출력이 이 초만큼 멈추면 유휴로 본다.
    public var idleAfter: TimeInterval
    public private(set) var lastOutput: Date?
    public private(set) var lastInput: Date?
    public private(set) var hookState: HookState?
    public private(set) var hookUpdatedAt: Date?
    public private(set) var exited = false
    public let startedAt: Date

    public init(usesHooks: Bool, idleAfter: TimeInterval = 3, startedAt: Date = Date()) {
        self.usesHooks = usesHooks
        self.idleAfter = idleAfter
        self.startedAt = startedAt
    }

    public mutating func noteOutput(at date: Date = Date()) { lastOutput = date }
    public mutating func noteInput(at date: Date = Date()) { lastInput = date }
    public mutating func noteExit() { exited = true }
    public mutating func noteHook(_ state: HookState, at date: Date = Date()) {
        hookState = state
        hookUpdatedAt = date
        if state == .exited { exited = true }
    }

    public func idleSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(lastOutput ?? startedAt)
    }

    /// shellAtPrompt: 일반 셸일 때 "터미널 앞에 셸 자신만 있는가"(실행 중인 명령 없음). 모르면 nil.
    /// 셸은 프롬프트를 다시 그리느라 출력이 생겨도 명령을 돌리는 게 아니므로, 이 값이 있으면 출력 시각보다 먼저 본다.
    public func status(now: Date = Date(), shellAtPrompt: Bool? = nil) -> NodeStatus {
        if exited { return .exited }
        if let atPrompt = shellAtPrompt {
            // 첫 출력(프롬프트) 전에는 아직 뜨는 중.
            if lastOutput == nil && now.timeIntervalSince(startedAt) < idleAfter { return .starting }
            return atPrompt ? .idle : .working
        }
        if usesHooks, let hook = hookState {
            switch hook {
            case .working: return .working
            case .waiting: return .waiting
            case .idle: return .idle
            case .exited: return .exited
            }
        }
        guard let out = lastOutput else {
            return now.timeIntervalSince(startedAt) < idleAfter ? .starting : .idle
        }
        return now.timeIntervalSince(out) < idleAfter ? .working : .idle
    }
}
