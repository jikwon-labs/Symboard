import Foundation

/// 보기 전용 공유 링크(14차). 이 맥에 작은 HTTP 서버를 띄우고, 링크(토큰)를 아는 사람만 브라우저로
/// 공유한 작업공간의 콘솔 출력과 상태를 본다. 입력·조작 경로는 아예 없다.
public enum ShareLink {
    /// 먼저 써 보는 포트. 쓰이고 있으면 아무 빈 포트.
    public static let preferredPort: UInt16 = 47_800
    /// 콘솔마다 새로 들어온 사람에게 다시 보여 줄 지난 출력(바이트).
    public static let tailLimit = 256_000
    /// 요청 머리가 이보다 크면 끊는다.
    public static let maxRequestBytes = 8_192

    /// 추측할 수 없는 토큰(128비트, 16진수 32자). 공유를 시작할 때마다 새로 만든다.
    public static func makeToken() -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &g)) }.joined()
    }

    public enum Route: Equatable, Sendable {
        /// 보드 화면. control 이면 조작 링크(허용한 콘솔에 입력할 수 있다).
        case page(control: Bool)
        case events(control: Bool)
        /// 보드의 이미지 노드 그림(노드 id).
        case image(String)
        /// 웹 타일을 맥에서 찍은 화면(노드 id). 보드 JSON 에는 주소만 있고 페이지 내용은 이 그림으로만 간다.
        case web(String)
        /// 웹 타일 페이지를 다시 그리는 재생 스크립트(rrweb). 앱에 함께 든 파일을 보낸다.
        case replayScript
        /// 조작 링크에서 콘솔로 보내는 입력(POST).
        case input
        case notFound
    }

    /// 요청 머리. bodyStart 는 data 안에서 몸통이 시작하는 자리.
    public struct RequestHead: Equatable, Sendable {
        public var method: String
        public var path: String
        public var contentLength: Int
        public var bodyStart: Int
    }

    /// 요청 머리를 읽는다. 머리가 아직 덜 왔거나 첫 줄이 이상하면 nil.
    public static func requestHead(_ data: Data) -> RequestHead? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var length = 0
        for l in lines.dropFirst() {
            let kv = l.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? -1
            }
        }
        return RequestHead(method: String(parts[0]), path: String(parts[1]), contentLength: length,
                           bodyStart: end.upperBound - data.startIndex)
    }

    /// 요청 머리 첫 줄에서 메서드와 경로를 꺼낸다. 머리가 아직 덜 왔으면 nil.
    public static func requestLine(_ data: Data) -> (method: String, path: String)? {
        requestHead(data).map { ($0.method, $0.path) }
    }

    /// 입력 몸통 최대 크기.
    public static let maxInputBytes = 64_000

    /// `/v/<보기 토큰>` 은 보기, `/c/<조작 토큰>` 은 조작. 그 아래 `events`, `img/<id>`, `web/<id>`, `rrweb.js`, 조작만 `input`(POST).
    /// 그 밖이나 토큰이 틀리면 notFound.
    public static func route(method: String, path: String, token: String, controlToken: String? = nil) -> Route {
        let clean = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let parts = clean.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts.count <= 4 else { return .notFound }
        let control: Bool
        if parts[0] == "v", constantTimeEqual(parts[1], token) { control = false }
        else if parts[0] == "c", let ct = controlToken, constantTimeEqual(parts[1], ct) { control = true }
        else { return .notFound }
        if parts.count == 3, parts[2] == "input" { return control && method == "POST" ? .input : .notFound }
        guard method == "GET" else { return .notFound }
        if parts.count == 2 { return .page(control: control) }
        if parts.count == 4 {
            guard UUID(uuidString: parts[3]) != nil else { return .notFound }
            switch parts[2] {
            case "img": return .image(parts[3])
            case "web": return .web(parts[3])
            default: return .notFound
            }
        }
        switch parts[2] {
        case "events": return .events(control: control)
        case "rrweb.js": return .replayScript
        default: return .notFound
        }
    }

    /// 조작 링크에서 온 입력 한 번. keys 는 터미널에 친 그대로의 글자(xterm onData), text 는 대화 보기 입력칸의 글,
    /// web 은 웹 타일에 넣을 마우스·키 동작.
    public struct InputRequest: Codable, Equatable, Sendable {
        public var id: String
        public var keys: String?
        public var text: String?
        public var submit: Bool?
        public var web: WebInput?
        public init(id: String, keys: String? = nil, text: String? = nil, submit: Bool? = nil, web: WebInput? = nil) {
            self.id = id; self.keys = keys; self.text = text; self.submit = submit; self.web = web
        }
    }

    /// 웹 타일 원격 조작 한 번. 좌표는 페이지 화면(뷰포트) 왼쪽 위 기준 CSS 픽셀이다.
    /// down·up·drag 는 왼쪽 단추, wheel 은 dx·dy 만큼 스크롤, key 는 특수 키 하나, text 는 글자 넣기.
    public struct WebInput: Codable, Equatable, Sendable {
        public var type: String
        public var x: Double?
        public var y: Double?
        public var dx: Double?
        public var dy: Double?
        public var key: String?
        public var text: String?
        public var clicks: Int?
        public var shift: Bool?
        public var alt: Bool?
        public var meta: Bool?
        public var ctrl: Bool?
        public init(type: String, x: Double? = nil, y: Double? = nil, dx: Double? = nil, dy: Double? = nil, key: String? = nil,
                    text: String? = nil, clicks: Int? = nil, shift: Bool? = nil, alt: Bool? = nil, meta: Bool? = nil, ctrl: Bool? = nil) {
            self.type = type; self.x = x; self.y = y; self.dx = dx; self.dy = dy; self.key = key; self.text = text
            self.clicks = clicks; self.shift = shift; self.alt = alt; self.meta = meta; self.ctrl = ctrl
        }

        public static let pointerTypes: Set<String> = ["down", "up", "drag"]
        /// 원격으로 받는 특수 키(브라우저 KeyboardEvent.key 이름). 글자 키는 text 로 온다.
        public static let keys: Set<String> = ["Enter", "Backspace", "Tab", "Escape", "Delete", "ArrowLeft", "ArrowRight",
                                               "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown", "a"]
        /// 페이지 좌표·스크롤 양의 허용 범위(이상한 값으로 화면 밖을 누르지 않게).
        static let coordRange = -100.0...40_000.0
        static let deltaRange = -20_000.0...20_000.0
    }

    public enum InputAction: Equatable, Sendable {
        case keys(UUID, [UInt8])
        case text(UUID, String, submit: Bool)
        case web(UUID, WebInput)
    }

    /// 웹 동작이 받을 만한 모양인지. 종류마다 필요한 값이 있고, 좌표는 범위 안이어야 한다.
    /// a 키는 Cmd/Ctrl 과 함께일 때만(전체 선택) 받는다. 되돌리기(Cmd+Z)는 맥에서 보드 되돌리기로 갈 수 있어 받지 않는다.
    static func validWebInput(_ w: WebInput) -> Bool {
        func inRange(_ v: Double?, _ r: ClosedRange<Double>) -> Bool { v.map { $0.isFinite && r.contains($0) } ?? false }
        switch w.type {
        case _ where WebInput.pointerTypes.contains(w.type):
            return inRange(w.x, WebInput.coordRange) && inRange(w.y, WebInput.coordRange) && (w.clicks ?? 1) >= 1 && (w.clicks ?? 1) <= 3
        case "wheel":
            return inRange(w.x, WebInput.coordRange) && inRange(w.y, WebInput.coordRange)
                && inRange(w.dx ?? 0, WebInput.deltaRange) && inRange(w.dy ?? 0, WebInput.deltaRange)
        case "key":
            guard let k = w.key, WebInput.keys.contains(k) else { return false }
            if k == "a" { return w.meta == true || w.ctrl == true }
            return true
        case "text":
            guard let t = w.text else { return false }
            return !t.isEmpty && t.utf8.count <= 8_192
        default:
            return false
        }
    }

    /// 입력 몸통을 읽고, 허용한 콘솔이면 할 일을 돌려준다. 허용하지 않았거나 비었거나 너무 크면 nil.
    public static func inputAction(_ body: Data, allowed: Set<UUID>) -> InputAction? {
        guard body.count <= maxInputBytes,
              let req = try? JSONDecoder().decode(InputRequest.self, from: body),
              let id = UUID(uuidString: req.id), allowed.contains(id) else { return nil }
        if let web = req.web { return validWebInput(web) ? .web(id, web) : nil }
        if let keys = req.keys, !keys.isEmpty {
            let bytes = Array(keys.utf8)
            return bytes.count <= 8_192 ? .keys(id, bytes) : nil
        }
        if let text = req.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(id, text, submit: req.submit ?? true)
        }
        return nil
    }

    /// 길이가 같으면 끝까지 비교한다(어디서 틀렸는지 시간으로 새지 않게).
    public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !x.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    /// 링크에 쓸 주소 순서: 집·사무실 네트워크(192.168, 10, 172.16–31) → Tailscale(100.64/10) → 그 밖. 루프백·링크 로컬은 뺀다.
    public static func rankedAddresses(_ ips: [String]) -> [String] {
        func rank(_ ip: String) -> Int? {
            let o = ip.split(separator: ".").compactMap { Int($0) }
            guard o.count == 4 else { return nil }
            if o[0] == 127 || (o[0] == 169 && o[1] == 254) || o[0] == 0 { return nil }
            if o[0] == 192 && o[1] == 168 { return 0 }
            if o[0] == 10 { return 0 }
            if o[0] == 172 && (16...31).contains(o[1]) { return 0 }
            if o[0] == 100 && (64...127).contains(o[1]) { return 1 }
            return 2
        }
        var seen = Set<String>()
        return ips.compactMap { ip in rank(ip).map { (ip, $0) } }
            .filter { seen.insert($0.0).inserted }
            .enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }

    public static func url(host: String, port: UInt16, token: String) -> String {
        "http://\(host):\(port)/v/\(token)"
    }

    /// 지난 출력을 한도 안으로 줄인다. 줄 중간(이스케이프 문자 중간)에서 시작하지 않게 잘린 자리 뒤 첫 줄바꿈부터 남긴다.
    public static func trimmedTail(_ bytes: [UInt8], limit: Int = tailLimit) -> [UInt8] {
        guard bytes.count > limit else { return bytes }
        let start = bytes.count - limit / 2
        if let nl = bytes[start...].firstIndex(of: 0x0A) { return Array(bytes[(nl + 1)...]) }
        return Array(bytes[start...])
    }

    /// 보는 사람에게 보내는 콘솔 한 개의 정보.
    public struct ConsoleInfo: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var agent: String
        public var status: String
        public var cols: Int
        public var rows: Int
        public var workspace: String
        /// 머리의 상태 알약 글과 색(앱과 같은 말·색, 일시정지·이어하기 대기 포함).
        public var pill: String = ""
        public var pillHex: String = "#8F8882"
        /// 이 사람이 이 콘솔에 입력할 수 있는지(조작 링크이고 콘솔을 허용했을 때만).
        public var input: Bool = false
        /// 대화 기록을 따로 보여 줄 수 있는지(claude). 전체 화면 CLI 는 터미널에 지난 줄이 없어 이것으로 스크롤해 본다.
        public var chat: Bool
        public init(id: String, name: String, agent: String, status: String, cols: Int, rows: Int, workspace: String, chat: Bool) {
            self.id = id; self.name = name; self.agent = agent; self.status = status; self.cols = cols; self.rows = rows
            self.workspace = workspace; self.chat = chat
        }
    }

    public struct WorkspaceInfo: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    /// 공유는 프로젝트 단위다: 그 프로젝트의 모든 작업공간(나중에 만든 것 포함)과 콘솔.
    /// current 는 맥에서 지금 보고 있는 작업공간(이 프로젝트 안일 때만).
    public struct Snapshot: Codable, Equatable, Sendable {
        public var project: String?
        public var workspaces: [WorkspaceInfo]
        public var current: String?
        public var consoles: [ConsoleInfo]
        /// 맥의 화면 모드("dark", "light"). 브라우저도 같은 색으로 그린다.
        public var theme: String
        /// 살아 있는 콘솔 수와 일하는 콘솔 수(앱 위쪽 "N live").
        public var live: Int
        public var working: Int
        /// 조작 링크로 들어온 사람인지.
        public var control: Bool = false
        /// 조작 링크에서 클릭·입력을 받는 웹 타일 id(맥에서 허용한 것). 보기 링크에는 넣지 않는다.
        public var webInput: [String]?
        public init(project: String?, workspaces: [WorkspaceInfo], current: String?, consoles: [ConsoleInfo],
                    theme: String = "dark", live: Int = 0, working: Int = 0) {
            self.project = project; self.workspaces = workspaces; self.current = current; self.consoles = consoles
            self.theme = theme; self.live = live; self.working = working
        }
    }

    /// Server-Sent Events 한 덩어리. data 는 한 줄 JSON 이어야 한다.
    public static func sseEvent(_ name: String, _ json: String) -> Data {
        Data("event: \(name)\ndata: \(json)\n\n".utf8)
    }

    public static func httpHead(status: String, contentType: String, extra: [String] = []) -> Data {
        var lines = ["HTTP/1.1 \(status)", "Content-Type: \(contentType)", "Cache-Control: no-store",
                     "Referrer-Policy: no-referrer", "X-Content-Type-Options: nosniff", "X-Frame-Options: DENY"]
        lines += extra
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// 대화 보기 한 줄.
    public struct ChatEntry: Codable, Equatable, Sendable {
        /// "user", "assistant", "tool".
        public var role: String
        public var text: String
        public init(role: String, text: String) { self.role = role; self.text = text }
    }

    /// 처음 들어온 사람에게 보내는 대화 줄 수(그 앞은 생략).
    public static let chatHistoryLimit = 400

    /// claude 세션 기록(JSONL) 몇 줄을 대화 보기 줄로 바꾼다. 사람 말·답·도구 호출 한 줄 요약만 남기고,
    /// 생각·도구 결과·시스템 안내는 뺀다. 깨진 줄은 건너뛴다.
    public static func chatEntries(fromJSONL lines: [Substring]) -> [ChatEntry] {
        var out: [ChatEntry] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant",
                  obj["isMeta"] as? Bool != true, obj["isSidechain"] as? Bool != true,
                  let msg = obj["message"] as? [String: Any] else { continue }
            if let text = msg["content"] as? String {
                if type == "user", let t = userText(text) { out.append(ChatEntry(role: "user", text: t)) }
                continue
            }
            guard let blocks = msg["content"] as? [[String: Any]] else { continue }
            for b in blocks {
                switch b["type"] as? String {
                case "text":
                    guard let t = b["text"] as? String else { continue }
                    if type == "user" {
                        if let u = userText(t) { out.append(ChatEntry(role: "user", text: u)) }
                    } else if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        out.append(ChatEntry(role: "assistant", text: t.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                case "tool_use":
                    guard type == "assistant", let name = b["name"] as? String else { continue }
                    out.append(ChatEntry(role: "tool", text: toolSummary(name: name, input: b["input"] as? [String: Any] ?? [:])))
                default: continue
                }
            }
        }
        return out
    }

    /// 사람이 친 글. 시스템이 끼워 넣은 글은 nil, 슬래시 명령은 명령 이름만.
    static func userText(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("<command-name>") || t.contains("<command-name>") {
            if let r = t.range(of: "<command-name>"), let e = t.range(of: "</command-name>", range: r.upperBound..<t.endIndex) {
                return String(t[r.upperBound..<e.lowerBound])
            }
            return nil
        }
        for p in ["<system-reminder>", "<local-command", "<command-", "<task-notification>", "[Request interrupted"] where t.hasPrefix(p) { return nil }
        return t
    }

    /// 도구 호출 한 줄: 이름과 가장 알아보기 쉬운 인자 하나(명령·파일·패턴·설명).
    static func toolSummary(name: String, input: [String: Any]) -> String {
        for key in ["description", "command", "file_path", "pattern", "path", "url", "query", "prompt"] {
            if let v = input[key] as? String, !v.isEmpty {
                let one = v.split(whereSeparator: \.isNewline).first.map(String.init) ?? v
                return "\(name) · " + (one.count > 160 ? String(one.prefix(160)) + "..." : one)
            }
        }
        return name
    }
}
