import Foundation

public enum NodeStatus: String, Codable, Sendable {
    case starting
    case working
    case idle
    case waiting
    /// 받은 일을 끝내고 멈췄는데 사용자가 아직 보지 않았다.
    case done
    case exited

    public var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .idle: return "Idle"
        case .waiting: return "Needs input"
        case .done: return "Done"
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

    /// 이번 일이 시작된 시각(작업 중으로 처음 판정된 때).
    public private(set) var workStartedAt: Date?
    /// 사용자가 보낸 일을 실제로 하고 있다고 본 적이 있는가(부팅 출력은 빼고).
    public private(set) var workConfirmed = false
    /// 일을 끝냈는데 사용자가 아직 보지 않았다.
    public private(set) var finishedUnseen = false
    /// 훅이 없을 때 출력이 이만큼 이어져야 일로 친다(부팅·화면 다시 그리기를 거르려고).
    public static let minWorkSeconds: TimeInterval = 3

    public init(usesHooks: Bool, idleAfter: TimeInterval = 3, startedAt: Date = Date()) {
        self.usesHooks = usesHooks
        self.idleAfter = idleAfter
        self.startedAt = startedAt
    }

    public mutating func noteOutput(at date: Date = Date()) { lastOutput = date }
    public mutating func noteInput(at date: Date = Date()) {
        lastInput = date
        finishedUnseen = false
    }
    /// 사용자가 그 노드를 봤다(선택·초점·Go to). Done 표시를 푼다.
    public mutating func acknowledge() { finishedUnseen = false }
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

    /// 화면 글자와 지난 판정을 함께 써서 최종 상태를 낸다. 1초마다 한 번 부른다.
    /// - screen: 터미널에 지금 보이는 글자. 선택을 기다리는 화면이면 훅 신호가 없어도 `.waiting`.
    public mutating func resolve(now: Date = Date(), shellAtPrompt: Bool? = nil, screen: String? = nil) -> NodeStatus {
        var st = status(now: now, shellAtPrompt: shellAtPrompt)
        if st != .exited, shellAtPrompt == nil, let screen, PromptDetector.isWaitingForChoice(screen) {
            st = .waiting
        }
        // 일반 셸은 명령 하나하나가 일이라 Done 을 쓰지 않는다.
        guard shellAtPrompt == nil else { return st }
        switch st {
        case .working:
            if workStartedAt == nil { workStartedAt = now }
            let byHook = usesHooks && hookState == .working
            let byOutput = lastInput != nil && now.timeIntervalSince(workStartedAt!) >= Self.minWorkSeconds
            if byHook || byOutput { workConfirmed = true; finishedUnseen = false }
        case .waiting:
            break
        case .idle:
            workStartedAt = nil
            if workConfirmed { workConfirmed = false; finishedUnseen = true }
            if finishedUnseen { return .done }
        default:
            workStartedAt = nil
        }
        return st
    }
}

/// 터미널 화면 끝부분 글자로 "사용자 선택을 기다리는 화면" 인지 알아낸다.
/// claude 의 폴더 신뢰·권한 확인, codex 의 폴더 신뢰·승인·업데이트 안내처럼 훅이 돌기 전이거나 훅이 없는 화면을 잡는다.
public enum PromptDetector {
    /// 화면 아래쪽에서 이만큼의 글 줄만 본다(오래된 출력에 남은 문구를 잡지 않게).
    public static let tailLines = 18

    static let hintPatterns = [
        "enter to confirm", "enter to select", "enter to continue", "enter continue",
        "esc to cancel", "esc to exit", "esc to quit", "esc to skip", "esc cancel", "esc quit", "esc skip",
        "press enter to confirm", "to navigate",
    ]
    static let questionPatterns = [
        "do you want to", "would you like to", "trust this folder", "i trust this folder",
        "allow command", "approve", "proceed?",
    ]

    public static func isWaitingForChoice(_ screen: String) -> Bool {
        let lines = screen.replacingOccurrences(of: "\u{0}", with: " ").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(tailLines)
        guard !tail.isEmpty else { return false }
        // 고르는 줄: "❯ 1. Yes", "› 1. Trust and continue", "❯ No, exit"
        let selected = tail.filter { l in
            guard let f = l.first, "❯›▶".contains(f) else { return false }
            return l.dropFirst().trimmingCharacters(in: .whitespaces).count >= 2
        }
        // 번호 붙은 선택지: "1. Yes", "2. No"
        let numbered = tail.filter { l in
            var t = Substring(l)
            if let f = t.first, "❯›▶>".contains(f) { t = t.dropFirst().drop(while: { $0 == " " }) }
            guard let dot = t.firstIndex(of: "."), dot > t.startIndex, t[t.startIndex..<dot].allSatisfy(\.isNumber) else { return false }
            return t[t.index(after: dot)...].hasPrefix(" ")
        }
        let lower = tail.map { $0.lowercased() }
        let hasHint = lower.contains { l in hintPatterns.contains { l.contains($0) } }
        let hasQuestion = lower.contains { l in questionPatterns.contains { l.contains($0) } }
        if !selected.isEmpty && hasHint { return true }
        // 고르는 표시가 번호 붙은 선택지 위에 있으면 안내 줄이 없어도 메뉴다(codex 데몬 설정 화면).
        let selectedNumbered = selected.contains { l in numbered.contains(l) }
        if selectedNumbered && numbered.count >= 2 { return true }
        if numbered.count >= 2 && (hasHint || hasQuestion) && (!selected.isEmpty || hasQuestion) { return true }
        return false
    }
}
