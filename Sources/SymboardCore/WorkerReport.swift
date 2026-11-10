import Foundation

/// 에이전트가 연 콘솔(worker)이 일을 끝내면 그 콘솔을 연 콘솔(lead)에 한 줄로 알린다.
/// 보고 내용은 worker 화면에 그대로 두고, lead 에는 "끝났으니 read_console 로 읽어라" 만 넣는다.
/// 넣는 때는 앱이 고른다: lead 가 쉬고 있고, 사용자가 lead 에 쓰다 만 글이 없을 때만.
public enum WorkerReport {
    /// 설정 "Tell the lead when a console it opened finishes"(기본 켬).
    public static let prefKey = "agents.reportToLead"
    public static func enabled(_ prefs: Prefs) -> Bool { prefs.string(prefKey) != "off" }
    public static func setEnabled(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: prefKey) }

    /// lead 에 넣는 줄의 머리. lead 안내문이 이 머리를 보고 알림인 줄 안다.
    public static let tag = "[symboard]"

    /// 이 콘솔을 연 콘솔. spawned·handoff 선을 거슬러 올라가 처음 만나는 콘솔(사이의 프롬프트 카드는 지나간다). 없으면 nil.
    public static func parentConsole(of id: UUID, links: [NodeLink], isConsole: (UUID) -> Bool) -> UUID? {
        var parent: [UUID: UUID] = [:]
        for l in links where AgentLimits.chainStyles.contains(l.style ?? "") && parent[l.to] == nil { parent[l.to] = l.from }
        var seen: Set<UUID> = [id]
        var cur = id
        while let p = parent[cur], !seen.contains(p) {
            if isConsole(p) { return p }
            seen.insert(p)
            cur = p
        }
        return nil
    }

    /// 끝 알림에 붙이는 검토 지시. 보고를 옮기기만 하지 말고 직접 확인한 뒤 알리게 한다.
    static let reviewRule = "do not take the report on trust. Check the changed files (the diff) and the verification it claims against the goal you gave, " +
        "rerunning a check yourself when that is cheap. Tell the user the result with what you confirmed and what you could not confirm kept apart, " +
        "and send the console back with send_to_console if something is wrong or missing."

    /// lead 에 넣을 한 줄. 에이전트가 읽는 글이라 영어(DECISIONS 10차-3).
    public static func notice(workers: [String]) -> String {
        let names = workers.map { "\"\($0)\"" }
        if names.count == 1 {
            return "\(tag) Console \(names[0]) finished its goal. Read its report with read_console(\(names[0])), then review it before you pass it on: \(reviewRule) Then start any goal that was waiting on it."
        }
        return "\(tag) Consoles \(names.joined(separator: ", ")) finished their goals. Read each report with read_console, then review each one before you pass it on: \(reviewRule) Then start any goals that were waiting on them."
    }

    /// 지금 lead 에 넣어도 되는가.
    /// - leadStatus: lead 의 지금 상태. 쉬는 중(idle·done)일 때만 넣는다. 일하는 중이면 끼어들고, 선택을 기다리면 그 답으로 들어간다.
    /// - leadIdleSince: lead 가 지금 상태가 된 시각.
    /// - lastUserKey: 사용자가 lead 에 마지막으로 친 시각. lead 가 쉬기 시작한 뒤에 쳤으면 쓰다 만 글이 있을 수 있어 기다린다
    ///   (알림이 그 글에 붙어 같이 보내지지 않게). 사용자가 그 글을 보내면 lead 가 일했다 다시 쉬므로 그때 넣는다.
    public static func canDeliver(leadStatus: NodeStatus?, leadIdleSince: Date?, lastUserKey: Date?) -> Bool {
        guard leadStatus == .idle || leadStatus == .done else { return false }
        guard let key = lastUserKey else { return true }
        guard let since = leadIdleSince else { return false }
        return key < since
    }

    /// lead 별로 아직 넣지 못한 알림. 같은 worker 는 한 번만 센다. 순서는 끝난 순서.
    public struct Queue: Sendable, Equatable {
        public private(set) var pending: [UUID: [UUID]] = [:]
        public init() {}

        public mutating func add(worker: UUID, lead: UUID) {
            var list = pending[lead] ?? []
            if !list.contains(worker) { list.append(worker) }
            pending[lead] = list
        }

        /// lead 에 넣을 worker 들을 꺼낸다(꺼내면 지운다).
        public mutating func take(lead: UUID) -> [UUID] {
            pending.removeValue(forKey: lead) ?? []
        }

        /// 사라진 콘솔을 뺀다(lead 가 사라지면 그 대기열째로).
        public mutating func prune(keeping alive: (UUID) -> Bool) {
            for (lead, workers) in pending {
                let kept = workers.filter(alive)
                if !alive(lead) || kept.isEmpty { pending[lead] = nil } else { pending[lead] = kept }
            }
        }

        public var isEmpty: Bool { pending.isEmpty }
    }
}
