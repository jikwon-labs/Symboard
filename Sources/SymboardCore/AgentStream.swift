import Foundation

/// 백그라운드로 돌린 CLI 의 JSON 줄 출력을 글 조각으로 바꾼다.
/// claude: `-p --output-format stream-json --verbose --include-partial-messages`
/// codex: `exec --json`
public struct AgentStreamParser: Sendable {
    public enum Event: Equatable, Sendable {
        /// 새로 붙는 글.
        case text(String)
        /// 도구 사용 같은 진행 표시(짧은 설명).
        case activity(String)
        /// 끝. 최종 글(있으면)과 성공 여부.
        case done(String?, Bool)
    }

    public let agent: String
    private var sawDelta = false

    public init(agent: String) { self.agent = agent }

    public mutating func parse(line: String) -> [Event] {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return [] }
        if agent == "codex" { return parseCodex(type: type, obj) }
        switch type {
        case "stream_event":
            guard let ev = obj["event"] as? [String: Any], let et = ev["type"] as? String else { return [] }
            if et == "content_block_delta", let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta",
               let t = d["text"] as? String {
                sawDelta = true
                return [.text(t)]
            }
            if et == "content_block_start", let b = ev["content_block"] as? [String: Any], b["type"] as? String == "tool_use",
               let name = b["name"] as? String {
                return [.activity(name)]
            }
            return []
        case "assistant":
            // 조각을 못 받았을 때(옵션 차이)만 통째 글을 쓴다.
            guard !sawDelta, let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { c in c["type"] as? String == "text" ? (c["text"] as? String).map(Event.text) : nil }
        case "result":
            let ok = (obj["is_error"] as? Bool) != true && (obj["subtype"] as? String ?? "success") == "success"
            return [.done(obj["result"] as? String, ok)]
        default:
            return []
        }
    }

    private func parseCodex(type: String, _ obj: [String: Any]) -> [Event] {
        switch type {
        case "item.completed", "item.started":
            guard let item = obj["item"] as? [String: Any], let it = item["type"] as? String else { return [] }
            if it == "agent_message", type == "item.completed", let t = item["text"] as? String { return [.text(t)] }
            if it == "command_execution", type == "item.started" { return [.activity((item["command"] as? String) ?? "command")] }
            if it == "reasoning", type == "item.completed" { return [.activity("thinking")] }
            return []
        case "turn.completed":
            return [.done(nil, true)]
        case "turn.failed", "error":
            return [.done((obj["message"] as? String) ?? ((obj["error"] as? [String: Any])?["message"] as? String), false)]
        default:
            return []
        }
    }

    /// 판정 답에서 YES/NO 를 읽는다. 첫 단어 기준.
    public static func verdict(_ text: String) -> Bool? {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .split(whereSeparator: { !$0.isLetter }).first.map(String.init)
        if first == "YES" { return true }
        if first == "NO" { return false }
        return nil
    }
}
