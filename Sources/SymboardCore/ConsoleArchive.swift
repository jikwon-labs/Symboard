import Foundation

/// 보관한 콘솔의 기록(17차). 프로세스는 끄고 노드는 작은 카드로 남긴다.
/// 다시 펼치면 같은 대화(claude `--resume`, codex `resume`)로 띄운다.
public struct ArchivedConsole: Codable, Equatable, Sendable {
    /// 보관한 시각.
    public var at: Date
    /// 보관하기 직전 화면 끝부분(worker 의 마지막 보고). 카드와 read_console 이 보여 준다.
    public var report: String
    /// 펼칠 때 돌아갈 크기.
    public var width: Double
    public var height: Double
    /// 자동 보관이었는가.
    public var auto: Bool?

    public init(at: Date, report: String, width: Double, height: Double, auto: Bool? = nil) {
        self.at = at; self.report = report; self.width = width; self.height = height; self.auto = auto
    }
}

public enum ConsoleArchive {
    /// 보관 카드 크기.
    public static let cardWidth: Double = 380
    public static let cardHeight: Double = 210
    /// 보관할 때 남기는 화면 줄 수.
    public static let reportLines = 120

    /// 설정 "Archive finished consoles automatically"(기본 켬).
    public static let autoKey = "agents.autoArchive"
    public static let minutesKey = "agents.autoArchiveMinutes"
    public static let defaultMinutes = 10
    public static let minuteChoices = [1, 3, 5, 10, 15, 30, 60]

    public static func autoEnabled(_ prefs: Prefs) -> Bool { prefs.string(autoKey) != "off" }
    public static func setAutoEnabled(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: autoKey) }
    public static func minutes(_ prefs: Prefs) -> Int { prefs.string(minutesKey).flatMap(Int.init).map { max(1, $0) } ?? defaultMinutes }
    public static func setMinutes(_ n: Int, _ prefs: Prefs) { prefs.set(n == defaultMinutes ? nil : String(n), for: minutesKey) }

    /// 터미널 끝 줄에서 보고만 남긴다. claude·codex 화면 아래의 입력 상자와 안내 줄(경계선 아래)은 뺀다.
    public static func report(fromTranscript text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { l -> String in
            var s = l
            while s.last == " " { s.removeLast() }
            return s
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        // 맨 아래 12줄 안에서 처음 나오는 경계선부터 자른다(입력 상자 ╭─ / ──── 와 그 아래 안내).
        let start = max(0, lines.count - 12)
        if let cut = lines.indices.dropFirst(start).first(where: { isBorder(lines[$0]) }) {
            lines.removeSubrange(cut...)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        return lines.suffix(reportLines).joined(separator: "\n")
    }

    static func isBorder(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let f = t.first, "─╭╰━".contains(f) else { return false }
        return t.filter { $0 == "─" || $0 == "━" }.count >= 8
    }

    /// 카드에 보일 짧은 글: 보고의 끝 n 줄.
    public static func preview(_ report: String, lines n: Int = 6) -> String {
        let lines = report.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(n).joined(separator: "\n")
    }

    /// 지금 저절로 보관해도 되는가.
    /// - openedByAgent: 다른 콘솔이 연 콘솔(worker)만. 사람이 연 콘솔은 저절로 접지 않는다.
    /// - finishedCount: 받은 일을 끝낸 적이 있어야 한다(일 없이 쉬기만 한 콘솔은 그대로).
    /// - restSince: 쉬기(idle·done) 시작한 시각. 그 뒤 minutes 분이 지나야 한다.
    /// - lastUserKey: 사용자가 그 콘솔에 친 마지막 시각. 쉬기 시작한 뒤에 쳤으면 쓰다 만 글이 있을 수 있어 그대로 둔다.
    /// - leadPending: lead 에 아직 끝났다는 알림을 못 넣었다.
    public static func shouldAutoArchive(openedByAgent: Bool, status: NodeStatus?, finishedCount: Int,
                                         restSince: Date?, lastUserKey: Date?, leadPending: Bool,
                                         now: Date, minutes: Int) -> Bool {
        guard openedByAgent, finishedCount > 0, !leadPending else { return false }
        guard status == .idle || status == .done, let since = restSince else { return false }
        if let key = lastUserKey, key >= since { return false }
        return now.timeIntervalSince(since) >= Double(minutes) * 60
    }

    /// lead 머리에 붙일 하위 콘솔 요약.
    public struct ChildSummary: Equatable, Sendable {
        public var working = 0
        public var finished = 0
        public var archived = 0
        public var needsYou = 0
        public init(working: Int = 0, finished: Int = 0, archived: Int = 0, needsYou: Int = 0) {
            self.working = working; self.finished = finished; self.archived = archived; self.needsYou = needsYou
        }
        public var total: Int { working + finished + archived + needsYou }
    }

    /// 이 콘솔이 바로 연 콘솔들(spawned·handoff 선, 사이의 프롬프트 카드는 지나간다).
    public static func children(of lead: UUID, links: [NodeLink], isConsole: (UUID) -> Bool) -> [UUID] {
        var out: [UUID] = []
        var seen: Set<UUID> = [lead]
        var frontier = [lead]
        while let cur = frontier.popLast() {
            for l in links where l.from == cur && AgentLimits.chainStyles.contains(l.style ?? "") && !seen.contains(l.to) {
                seen.insert(l.to)
                if isConsole(l.to) { out.append(l.to) } else { frontier.append(l.to) }
            }
        }
        return out
    }

    /// archived: 보관한 콘솔이면 true, status: 살아 있는 콘솔의 상태.
    public static func summarize(_ children: [(archived: Bool, status: NodeStatus?)]) -> ChildSummary {
        var s = ChildSummary()
        for c in children {
            if c.archived { s.archived += 1; continue }
            switch c.status {
            case .working, .starting: s.working += 1
            case .waiting: s.needsYou += 1
            default: s.finished += 1
            }
        }
        return s
    }
}
