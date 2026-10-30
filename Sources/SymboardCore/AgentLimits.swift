import Foundation

/// 에이전트가 보드 도구로 콘솔을 이어 띄울 때의 멈춤 장치(9차 5번).
/// 단계: 사람이 연 콘솔이 0, 그 콘솔이 띄운 콘솔이 1, … (spawned·handoff 선을 거슬러 센다. 사이의 프롬프트 카드는 세지 않는다).
/// 개수: 작업공간에서 에이전트가 연(들어오는 spawned·handoff 선이 있는) 콘솔 수.
/// 넘으면 앱이 사용자에게 묻고, 사용자가 허락하면 그 한 번만 연다.
public enum AgentLimits {
    public static let depthKey = "agents.maxChainDepth"
    public static let openedKey = "agents.maxOpened"
    public static let defaultDepth = 4
    public static let defaultOpened = 12
    public static let choices = Array(1...20)

    /// 에이전트가 이어 띄운 선의 모양.
    public static let chainStyles: Set<String> = [NodeLink.spawnedStyle, NodeLink.handoffStyle]

    public static func maxDepth(_ prefs: Prefs) -> Int { value(prefs, depthKey, defaultDepth) }
    public static func maxOpened(_ prefs: Prefs) -> Int { value(prefs, openedKey, defaultOpened) }
    public static func setMaxDepth(_ n: Int, _ prefs: Prefs) { prefs.set(n == defaultDepth ? nil : String(n), for: depthKey) }
    public static func setMaxOpened(_ n: Int, _ prefs: Prefs) { prefs.set(n == defaultOpened ? nil : String(n), for: openedKey) }

    static func value(_ prefs: Prefs, _ key: String, _ fallback: Int) -> Int {
        prefs.string(key).flatMap(Int.init).map { max(1, $0) } ?? fallback
    }

    /// 콘솔의 단계. 위로 콘솔이 몇 개 있는지(카드 같은 콘솔 아닌 노드는 지나가기만 한다). 순환이 있어도 멈춘다.
    public static func depth(of id: UUID, links: [NodeLink], isConsole: (UUID) -> Bool) -> Int {
        var parent: [UUID: UUID] = [:]
        for l in links where chainStyles.contains(l.style ?? "") && parent[l.to] == nil { parent[l.to] = l.from }
        var seen: Set<UUID> = [id]
        var cur = id, n = 0
        while let p = parent[cur], !seen.contains(p) {
            seen.insert(p)
            if isConsole(p) { n += 1 }
            cur = p
        }
        return n
    }

    /// 에이전트가 연 콘솔 수.
    public static func openedCount(consoles: [UUID], links: [NodeLink]) -> Int {
        let targets = Set(links.filter { chainStyles.contains($0.style ?? "") }.map(\.to))
        return consoles.filter { targets.contains($0) }.count
    }

    /// 하나 더 열면 넘는 제한. 없으면 nil. 문구는 사용자 확인 띠에 그대로 쓴다(앱 글자가 영어).
    public static func exceeded(callerDepth: Int, opened: Int, maxDepth: Int, maxOpened: Int) -> String? {
        if callerDepth + 1 > maxDepth { return "chain step \(callerDepth + 1) is past the limit of \(maxDepth)" }
        if opened + 1 > maxOpened { return "agents already opened \(opened) console\(opened == 1 ? "" : "s") (limit \(maxOpened))" }
        return nil
    }
}
