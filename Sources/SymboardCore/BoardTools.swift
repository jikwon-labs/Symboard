import Foundation

/// claude·codex 가 보드에 콘솔을 띄우고 넘겨주고 그리는 도구(8차 3번, 9차).
/// 앱이 유닉스 소켓을 열고, 앱 번들 안 `symboard-mcp`(stdio MCP 서버)가 도구 호출마다 그 소켓에 한 줄 JSON 을 보낸다.
/// claude 콘솔은 `--mcp-config <앱이 만든 임시 json>` 과 `--append-system-prompt` 로, codex 콘솔은 `-c` 인자로 붙인다. 사용자 ~/.claude·~/.codex 는 건드리지 않는다.
public enum BoardTools {
    public static let serverName = "symboard"
    public static let prefKey = "agents.boardTools"

    /// 설정 "Let agents open consoles on the board"(기본 켬).
    public static func enabled(_ prefs: Prefs) -> Bool { prefs.string(prefKey) != "off" }
    public static func setEnabled(_ on: Bool, _ prefs: Prefs) { prefs.set(on ? nil : "off", for: prefKey) }

    /// 앱 소켓 경로. 유닉스 소켓 경로는 103바이트까지라, 상태 폴더 경로가 길면 임시 폴더에 폴더별 이름으로 둔다.
    public static func socketPath(directory: String, temporary: String) -> String {
        let p = (directory as NSString).appendingPathComponent("bridge.sock")
        if p.utf8.count < 104 { return p }
        // 폴더마다 같은 이름이 나오게 경로의 FNV-1a 해시를 쓴다(Hasher 는 실행마다 바뀐다).
        var h: UInt64 = 0xcbf29ce484222325
        for b in directory.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return (temporary as NSString).appendingPathComponent("symboard-\(String(h, radix: 16)).sock")
    }

    /// claude 에 덧붙이는 짧은 안내.
    public static let systemPrompt = """
        You are running in a console on Symboard, a board where the user watches many terminal consoles side by side. \
        The symboard tools let you work on that board. \
        When a task splits into parts that can run in parallel, prefer them over your built-in subagents: \
        open a console per part with spawn_console (agent "claude", "codex" or "shell", with the instructions as prompt), \
        or send work to an existing console with send_to_console, and collect results with read_console. \
        When the user asks you to pass work on, or the next stage should run in a fresh session, write a complete, self-contained prompt \
        (goal, context, relevant files, what is done, what remains, how to verify) and call hand_off. \
        The prompt is pinned on the board as a card linked to the new console, and that console can hand off again. \
        After handing off, do not do that stage yourself. \
        Use add_note for short notes and draw_diagram for boxes and arrows (plans, flows, architecture). \
        The user can see and steer every console. Leave consoles open; use close_console only when the user asks. \
        If a tool says a limit was reached or the user declined, stop and tell the user instead of retrying.
        """

    public static func claudeArgs(configPath: String) -> [String] {
        ["--mcp-config", configPath, "--append-system-prompt", systemPrompt]
    }

    /// codex 는 `-c 키=TOML값` 으로만 붙인다(사용자 ~/.codex/config.toml 은 그대로). 안내는 developer_instructions,
    /// 도구는 claude 와 같은 `symboard-mcp` 를 mcp_servers.symboard 로. `codex resume` 에도 같은 인자가 통한다.
    public static func codexArgs(serverPath: String, socketPath: String, nodeID: UUID) -> [String] {
        let env = "{SYMBOARD_SOCKET=\(tomlString(socketPath)), SYMBOARD_CALLER=\(tomlString(nodeID.uuidString))}"
        return [
            "-c", "developer_instructions=\(tomlString(systemPrompt))",
            "-c", "mcp_servers.\(serverName).command=\(tomlString(serverPath))",
            "-c", "mcp_servers.\(serverName).env=\(env)",
        ]
    }

    /// TOML 기본 문자열(큰따옴표). 역슬래시·따옴표·제어 문자를 이스케이프한다.
    static func tomlString(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if u.value < 0x20 || u.value == 0x7f { out += String(format: "\\u%04X", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// `--mcp-config` 에 줄 JSON. 서버는 콘솔마다 따로 뜨고, 부른 콘솔은 환경 변수로 안다.
    public static func mcpConfigJSON(serverPath: String, socketPath: String, nodeID: UUID) -> String {
        let obj: [String: Any] = ["mcpServers": [serverName: [
            "type": "stdio",
            "command": serverPath,
            "args": [String](),
            "env": ["SYMBOARD_SOCKET": socketPath, "SYMBOARD_CALLER": nodeID.uuidString],
        ]]]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    /// MCP tools/list 에 보이는 도구.
    public static var toolDefinitions: [[String: Any]] {
        func schema(_ props: [String: [String: Any]], required: [String]) -> [String: Any] {
            ["type": "object", "properties": props, "required": required]
        }
        let name: [String: Any] = ["type": "string", "description": "Console name as shown on the board, e.g. \"Ada\""]
        return [
            ["name": "list_consoles",
             "description": "List the consoles on the current Symboard board: name, agent, status and group.",
             "inputSchema": schema([:], required: [])],
            ["name": "spawn_console",
             "description": "Open a new console next to yours on the board and optionally give it a first prompt (sent once it is ready). Returns the new console's name.",
             "inputSchema": schema([
                "agent": ["type": "string", "enum": ["claude", "codex", "shell"], "description": "What runs in the console"],
                "name": ["type": "string", "description": "Optional name; a short free name is picked if omitted or taken"],
                "prompt": ["type": "string", "description": "Optional first message (claude/codex) or command line (shell)"],
                "group": ["type": "string", "description": "Optional group to put the console in (created if missing)"],
             ], required: ["agent"])],
            ["name": "send_to_console",
             "description": "Type text into a console and press Enter (a prompt for claude/codex, a command for a shell).",
             "inputSchema": schema(["name": name, "text": ["type": "string"]], required: ["name", "text"])],
            ["name": "read_console",
             "description": "Read the last lines of a console's screen and history, plus its status (starting, working, idle, done, needs you).",
             "inputSchema": schema(["name": name, "lines": ["type": "integer", "description": "How many lines from the end (default 40, max 400)"]], required: ["name"])],
            ["name": "close_console",
             "description": "Close a console and stop its process.",
             "inputSchema": schema(["name": name], required: ["name"])],
            ["name": "hand_off",
             "description": "Pass the next stage of work to a new console: pins the prompt on the board as a card next to yours, opens the console beside it, links you → card → console, and sends the prompt once the console is ready. The new console has these tools too and can hand off again.",
             "inputSchema": schema([
                "prompt": ["type": "string", "description": "Complete, self-contained instructions for the next session"],
                "agent": ["type": "string", "enum": ["claude", "codex", "shell"], "description": "What runs in the new console (default claude)"],
                "title": ["type": "string", "description": "Optional short card title, e.g. \"Step 2: tests\""],
                "name": ["type": "string", "description": "Optional console name"],
             ], required: ["prompt"])],
            ["name": "add_note",
             "description": "Put a sticky note next to your console on the board.",
             "inputSchema": schema([
                "text": ["type": "string"],
                "title": ["type": "string", "description": "Optional short title"],
                "color": ["type": "string", "enum": ["yellow", "blue", "green", "pink", "purple", "gray"]],
             ], required: ["text"])],
            ["name": "draw_diagram",
             "description": "Draw a hand-drawn style diagram of boxes and arrows on the board (laid out top to bottom). Groups draw dashed frames around their boxes.",
             "inputSchema": schema([
                "title": ["type": "string"],
                "nodes": ["type": "array", "items": ["type": "object", "properties": [
                    "id": ["type": "string"], "label": ["type": "string"], "sub": ["type": "string", "description": "Optional second line"],
                    "shape": ["type": "string", "enum": ["box", "ellipse"]], "group": ["type": "string", "description": "Optional group id"],
                ], "required": ["id", "label"]]],
                "edges": ["type": "array", "items": ["type": "object", "properties": [
                    "from": ["type": "string"], "to": ["type": "string"], "label": ["type": "string"],
                ], "required": ["from", "to"]]],
                "groups": ["type": "array", "items": ["type": "object", "properties": [
                    "id": ["type": "string"], "label": ["type": "string"],
                ], "required": ["id", "label"]]],
             ], required: ["title", "nodes", "edges"])],
        ]
    }
}

/// stdio MCP 서버의 메시지 처리(JSON-RPC 2.0, 줄마다 한 메시지). 실행 파일은 이것으로 줄을 읽고 쓰기만 한다.
public struct MCPStdioServer: Sendable {
    public typealias ToolCall = @Sendable (_ tool: String, _ args: [String: Any]) -> (text: String, isError: Bool)
    let call: ToolCall
    public init(call: @escaping ToolCall) { self.call = call }

    /// 한 줄을 처리해 보낼 응답 줄. 알림(id 없음)이면 nil.
    public func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = msg["id"], !(id is NSNull) else { return nil }
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]
        var result: [String: Any]?
        var error: [String: Any]?
        switch method {
        case "initialize":
            result = ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                      "capabilities": ["tools": [String: Any]()],
                      "serverInfo": ["name": BoardTools.serverName, "version": "0.9.0"]]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": BoardTools.toolDefinitions]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let r = call(name, params["arguments"] as? [String: Any] ?? [:])
            result = ["content": [["type": "text", "text": r.text]], "isError": r.isError]
        default:
            error = ["code": -32601, "message": "Method not found: \(method)"]
        }
        var out: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let result { out["result"] = result } else { out["error"] = error ?? [:] }
        return Self.encode(out)
    }

    static func encode(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// 앱 소켓과 주고받는 한 줄 JSON. 요청 {"caller","tool","args"}, 응답 {"text","isError"}.
public enum BoardBridge {
    /// 소켓에 요청 한 줄을 보내고 응답 한 줄을 받는다.
    public static func request(socketPath: String, caller: String, tool: String, args: [String: Any], timeout: TimeInterval = 60) -> (text: String, isError: Bool) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return ("Symboard is not reachable (socket)", true) }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return ("Socket path too long", true) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in pathBytes.enumerated() { raw[i] = b }
            raw[pathBytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return ("Symboard is not running or board tools are off", true) }
        let body: [String: Any] = ["caller": caller, "tool": tool, "args": args]
        guard var data = try? JSONSerialization.data(withJSONObject: body) else { return ("Bad arguments", true) }
        data.append(0x0A)
        let sent = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == data.count else { return ("Could not send to Symboard", true) }
        guard let line = readLine(fd: fd),
              let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return ("No answer from Symboard", true)
        }
        return (obj["text"] as? String ?? "", obj["isError"] as? Bool ?? false)
    }

    /// 줄바꿈까지 읽는다(줄바꿈은 빼고). 연결이 끊기면 그때까지 읽은 것.
    public static func readLine(fd: Int32) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { return String(decoding: buf, as: UTF8.self) }
            buf.append(byte)
        }
        return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self)
    }

    public static func encodeReply(text: String, isError: Bool) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: ["text": text, "isError": isError])) ?? Data("{}".utf8)
        d.append(0x0A)
        return d
    }
}
