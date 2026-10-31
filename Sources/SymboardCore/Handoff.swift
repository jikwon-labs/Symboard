import Foundation

/// 넘겨주기: 보내는 노드의 CLI 에게 요약을 부탁하고, 그 답을 받는 노드에 넣는다.
public enum Handoff {
    public static let begin = "HANDOFF-BEGIN"
    public static let end = "HANDOFF-END"

    /// 보내는 노드에 넣을 요청문. 한 줄이라 붙여넣기 없이 바로 들어간다.
    public static func request(note: String) -> String {
        var s = "Summarize your work in this session so another agent can continue it: goal, what is done, what is left, key files, and any gotchas. "
        s += "Do not run tools or change files for this. Put the summary between a line with \(begin) and a line with \(end)."
        if !note.isEmpty { s += " Also note: \(note)" }
        return s
    }

    /// 받는 노드에 넣을 문장.
    public static func message(from source: String, summary: String) -> String {
        "Handoff from \"\(source)\". Continue from this summary:\n\n\(summary)"
    }

    /// 표시 사이 내용. 요청문이 다시 찍힌 것과 헷갈리지 않게 마지막 BEGIN 뒤의 END 까지를 쓴다.
    public static func extractMarked(_ text: String) -> String? {
        guard let b = text.range(of: begin, options: .backwards) else { return nil }
        let rest = text[b.upperBound...]
        guard let e = rest.range(of: end) else { return nil }
        let body = rest[..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// claude 대화 기록(jsonl)에서 마지막 사용자 입력 뒤 assistant 글을 이어 붙인다.
    public static func claudeLastReply(jsonl: String) -> String? {
        // 끝에서부터 사람이 친 마지막 user 줄까지만 본다(앞에서부터 모든 줄을 JSON 으로 풀면 큰 기록에서 1초 넘게 걸렸다).
        var parts: [String] = []
        for line in jsonl.split(separator: "\n").reversed() {
            // JSON 으로 풀기 전에 글자로 거른다. 공백 없는 꼴과 있는 꼴 둘 다.
            guard line.contains("\"user\"") || line.contains("\"assistant\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String, let msg = obj["message"] as? [String: Any] else { continue }
            if type == "user" {
                // 도구 결과도 user 로 들어오므로 사람이 친 글일 때만 차례의 시작으로 본다.
                if msg["content"] is String { break }
                if let blocks = msg["content"] as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "text" }) { break }
            } else if type == "assistant", let blocks = msg["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { b -> String? in
                    guard b["type"] as? String == "text", let t = b["text"] as? String, !t.isEmpty else { return nil }
                    return t
                }
                parts.insert(contentsOf: texts, at: 0)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// codex 세션 기록(jsonl)에서 마지막 assistant 글.
    public static func codexLastReply(jsonl: String) -> String? {
        // 끝에서부터 처음 만나는 assistant 글.
        for line in jsonl.split(separator: "\n").reversed() {
            guard line.contains("assistant") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "response_item",
                  let p = obj["payload"] as? [String: Any], p["type"] as? String == "message",
                  p["role"] as? String == "assistant", let blocks = p["content"] as? [[String: Any]] else { continue }
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return nil
    }
}
