import AppKit
import Network
import SymboardCore

/// 보기 전용 공유(14차). 이 맥에 HTTP 서버를 띄우고, 링크를 아는 사람이 브라우저로 공유한 작업공간의 콘솔을 본다.
/// 링크는 둘이다. 보기 링크(`/v/<토큰>`)는 보기만 하고, 조작 링크(`/c/<조작 토큰>`)는 내가 허용한 콘솔에 입력할 수 있다.
/// 입력(`/c/<조작 토큰>/input`, POST)은 허용한 콘솔에만 내가 친 것처럼 들어간다. 허용은 공유를 켤 때마다 비어 있다.
/// 공유는 시작할 때 보던 작업공간의 프로젝트 단위다: 그 프로젝트의 작업공간·콘솔은 나중에 만든 것까지 보이고, 다른 프로젝트는 보이지 않는다.
/// claude 콘솔은 전체 화면이라 터미널에 지난 줄이 없으므로, 세션 기록(JSONL)을 따라 읽어 스크롤되는 대화 보기도 보낸다.
/// 모든 일은 메인 큐에서 한다(콘솔 세션이 메인 액터에 있고, 오가는 양이 적다).
@MainActor
final class ShareServer {
    unowned let model: AppModel
    private(set) var token: String?
    /// 조작 링크 토큰. 보기 토큰과 따로 만든다.
    private(set) var controlToken: String?
    /// 조작 링크로 입력을 받는 콘솔. 기본은 비어 있다(아무 콘솔도 받지 않음).
    private(set) var inputAllowed: Set<UUID> = []
    /// 원격 입력이 들어왔을 때(콘솔 이름). 화면에 잠깐 알린다.
    var onRemoteInput: ((String) -> Void)?
    private var lastNotice: [UUID: Date] = [:]
    private var lastConsoleIDs: [UUID] = []
    /// 공유를 시작한 작업공간. 프로젝트 폴더가 없는 작업공간이면 이것 하나만 공유한다.
    private(set) var workspaceID: UUID?
    /// 공유하는 프로젝트 폴더.
    private(set) var projectPath: String?
    /// 콘솔별 대화 기록 따라 읽기.
    private var chats: [UUID: ChatTail] = [:]
    /// 작업공간별 마지막으로 보낸 보드 JSON. 바뀌었을 때만 다시 보낸다.
    private var boards: [UUID: String] = [:]
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private var viewers: [ObjectIdentifier: Viewer] = [:]
    /// 콘솔별로 아직 보내지 않은 출력. 짧은 간격으로 모아 보낸다.
    private var pending: [UUID: [UInt8]] = [:]
    private var hooked: Set<UUID> = []
    private let listenerKey = UUID()
    private var flushTimer: Timer?
    private var tickObserver: NSObjectProtocol?
    private var pingTimer: Timer?

    /// 시작·멈춤·보는 사람 수가 바뀌면 불린다.
    var onChange: (() -> Void)?

    init(model: AppModel) { self.model = model }

    var isActive: Bool { token != nil && listener != nil }
    var viewerCount: Int { viewers.count }

    /// 링크 목록(가장 쓸 만한 주소부터).
    var links: [String] {
        guard let token, port > 0 else { return [] }
        return ShareLink.rankedAddresses(Self.localIPv4()).map { ShareLink.url(host: $0, port: port, token: token) }
    }

    /// 조작 링크(첫 주소만).
    var controlLink: String? {
        guard let controlToken, port > 0, let host = ShareLink.rankedAddresses(Self.localIPv4()).first else { return nil }
        return "http://\(host):\(port)/c/\(controlToken)"
    }

    /// 공유하는 콘솔(팝오버의 입력 허용 목록).
    var sharedConsoles: [(id: UUID, name: String, workspace: String)] {
        sharedNodes.map { ($0.node.id, $0.node.displayTitle, $0.ws.name) }
    }

    func setInput(_ id: UUID, allowed: Bool) {
        if allowed { inputAllowed.insert(id) } else { inputAllowed.remove(id) }
        sendMeta(to: Array(viewers.values))
        onChange?()
    }

    /// 팝오버에 보이는 공유 범위 이름(프로젝트 폴더 이름, 없으면 작업공간 이름).
    var scopeName: String? {
        if let p = projectPath { return (p as NSString).lastPathComponent }
        return workspaceID.flatMap { model.workspace($0)?.name }
    }

    // MARK: 시작·멈춤

    func start(workspace: UUID) {
        stop()
        token = ShareLink.makeToken()
        controlToken = ShareLink.makeToken()
        inputAllowed = []
        workspaceID = workspace
        projectPath = model.workspace(workspace)?.projectPath
        if !listen(on: ShareLink.preferredPort) { _ = listen(on: nil) }
        tickObserver = NotificationCenter.default.addObserver(forName: .statusTick, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        // 오래 조용하면 중간 장비가 연결을 끊을 수 있어 가끔 빈 줄을 보낸다.
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewers.values.forEach { $0.send(Data(": ping\n\n".utf8)) } }
        }
        onChange?()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for v in viewers.values { v.connection.cancel() }
        viewers.removeAll()
        for id in hooked { model.sessions.session(for: id)?.rawListeners[listenerKey] = nil }
        hooked.removeAll()
        pending.removeAll()
        flushTimer?.invalidate(); flushTimer = nil
        pingTimer?.invalidate(); pingTimer = nil
        if let o = tickObserver { NotificationCenter.default.removeObserver(o) }
        tickObserver = nil
        let was = token != nil
        token = nil
        controlToken = nil
        inputAllowed = []
        lastNotice = [:]
        workspaceID = nil
        projectPath = nil
        chats.removeAll()
        boards.removeAll()
        port = 0
        if was { onChange?() }
    }

    private func listen(on preferred: UInt16?) -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l: NWListener
        do {
            if let p = preferred, let port = NWEndpoint.Port(rawValue: p) { l = try NWListener(using: params, on: port) }
            else { l = try NWListener(using: params) }
        } catch { return false }
        l.stateUpdateHandler = { [weak self, weak l] state in
            MainActor.assumeIsolated {
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready:
                    self.port = l.port?.rawValue ?? 0
                    self.onChange?()
                case .failed:
                    // 처음 포트가 막 쓰이고 있으면 아무 빈 포트로 다시.
                    l.cancel()
                    self.listener = nil
                    if preferred != nil, self.token != nil { _ = self.listen(on: nil) } else { self.onChange?() }
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        listener = l
        l.start(queue: .main)
        return true
    }

    // MARK: 연결

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { conn.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }
                if let head = ShareLink.requestHead(buf) {
                    // 몸통이 있으면(입력) 다 올 때까지 더 읽는다.
                    let have = buf.count - head.bodyStart
                    if head.contentLength < 0 || head.contentLength > ShareLink.maxInputBytes { conn.cancel(); return }
                    if have < head.contentLength {
                        if error != nil || done { conn.cancel() } else { self.readRequest(conn, buffer: buf) }
                        return
                    }
                    let body = buf.subdata(in: (buf.startIndex + head.bodyStart)..<(buf.startIndex + head.bodyStart + head.contentLength))
                    self.respond(conn, method: head.method, path: head.path, body: body)
                } else if error != nil || done || buf.count > ShareLink.maxRequestBytes {
                    conn.cancel()
                } else {
                    self.readRequest(conn, buffer: buf)
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, method: String, path: String, body: Data) {
        guard let token, isActive else { conn.cancel(); return }
        switch ShareLink.route(method: method, path: path, token: token, controlToken: controlToken) {
        case .input:
            let ok = handleInput(body)
            let out = ShareLink.httpHead(status: ok ? "204 No Content" : "403 Forbidden", contentType: "text/plain; charset=utf-8",
                                         extra: ["Content-Length: 0", "Connection: close"])
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        case .page:
            let body = Data(ShareViewerPage.html.utf8)
            var out = ShareLink.httpHead(status: "200 OK", contentType: "text/html; charset=utf-8",
                                         extra: ["Content-Length: \(body.count)", "Connection: close",
                                                 "Content-Security-Policy: \(ShareViewerPage.csp)"])
            out.append(body)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        case .events(let control):
            let head = ShareLink.httpHead(status: "200 OK", contentType: "text/event-stream; charset=utf-8",
                                          extra: ["Connection: keep-alive"])
            let v = Viewer(connection: conn)
            v.control = control
            let key = ObjectIdentifier(conn)
            viewers[key] = v
            conn.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .failed, .cancelled:
                        if self?.viewers.removeValue(forKey: key) != nil { self?.onChange?() }
                    default: break
                    }
                }
            }
            // 보는 쪽이 끊으면 읽기가 끝난다. 그때 정리한다.
            watchClose(conn)
            v.send(head)
            sendMeta(to: [v])
            onChange?()
        case .image(let raw):
            serveImage(conn, nodeID: UUID(uuidString: raw))
        case .notFound:
            let body = Data("Not found\n".utf8)
            var out = ShareLink.httpHead(status: "404 Not Found", contentType: "text/plain; charset=utf-8",
                                         extra: ["Content-Length: \(body.count)", "Connection: close"])
            out.append(body)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    /// 조작 링크의 입력. 허용한 콘솔이고 공유 범위 안이면 내가 친 것처럼 넣는다.
    private func handleInput(_ body: Data) -> Bool {
        let shared = Set(sharedNodes.map(\.node.id))
        guard let action = ShareLink.inputAction(body, allowed: inputAllowed.intersection(shared)) else { return false }
        let id: UUID
        switch action {
        case .keys(let nid, let bytes):
            guard let s = model.sessions.session(for: nid), s.running else { return false }
            s.view.send(data: bytes[...])
            id = nid
        case .text(let nid, let text, let submit):
            guard let s = model.sessions.session(for: nid), s.running else { return false }
            s.sendText(text, submit: submit)
            id = nid
        }
        // 같은 콘솔은 몇 초에 한 번만 알린다(글자마다 뜨지 않게).
        if Date().timeIntervalSince(lastNotice[id] ?? .distantPast) > 4 {
            lastNotice[id] = Date()
            onRemoteInput?(model.node(id)?.displayTitle ?? "")
        }
        return true
    }

    /// 공유한 작업공간의 이미지 노드 그림만 보낸다. 그 밖은 404.
    private func serveImage(_ conn: NWConnection, nodeID: UUID?) {
        let node = nodeID.flatMap { id in sharedWorkspaces.lazy.flatMap(\.nodes).first { $0.id == id && $0.kind == .image } }
        let path = node?.text ?? ""
        let ext = (path as NSString).pathExtension.lowercased()
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "heic": "image/heic"]
        guard let type = types[ext], let body = FileManager.default.contents(atPath: path), body.count < 30_000_000 else {
            var out = ShareLink.httpHead(status: "404 Not Found", contentType: "text/plain; charset=utf-8", extra: ["Content-Length: 0", "Connection: close"])
            out.append(Data())
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        var out = ShareLink.httpHead(status: "200 OK", contentType: type, extra: ["Content-Length: \(body.count)", "Connection: close"])
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func watchClose(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, done, error in
            MainActor.assumeIsolated {
                if done || error != nil { conn.cancel() } else { self?.watchClose(conn) }
            }
        }
    }

    // MARK: 내용

    /// 공유하는 작업공간(프로젝트의 모든 작업공간, 나중에 만든 것 포함).
    private var sharedWorkspaces: [Workspace] {
        if let p = projectPath { return model.state.workspaces.filter { $0.projectPath == p } }
        return workspaceID.flatMap { model.workspace($0) }.map { [$0] } ?? []
    }

    /// 공유하는 콘솔 노드와 그 작업공간.
    private var sharedNodes: [(ws: Workspace, node: BoardNode)] {
        sharedWorkspaces.flatMap { ws in ws.nodes.filter { $0.kind == .terminal }.map { (ws, $0) } }
    }

    private func snapshot() -> ShareLink.Snapshot {
        let wss = sharedWorkspaces
        let consoles = sharedNodes.map { pair -> ShareLink.ConsoleInfo in
            let node = pair.node
            let term = model.sessions.session(for: node.id)?.view.getTerminal()
            let st = model.sessions.status(of: node.id) ?? .starting
            var info = ShareLink.ConsoleInfo(id: node.id.uuidString, name: node.displayTitle,
                                             agent: node.terminal?.agent.displayName ?? "",
                                             status: st.rawValue, cols: term?.cols ?? 80, rows: term?.rows ?? 24,
                                             workspace: pair.ws.id.uuidString, chat: node.terminal?.agent == .claude)
            // NodeHeaderView.setStatus 와 같은 글·색.
            let paused = model.sessions.session(for: node.id)?.paused ?? false
            let onHold = model.sessions.pendingResume.contains(node.id)
            info.pill = L(onHold ? "ON HOLD" : (paused ? "PAUSED" : st.pillText))
            info.pillHex = (paused || onHold) ? Self.statusHex(nil) : Self.statusHex(st)
            return info
        }
        let current = model.selectedWorkspace.id
        return ShareLink.Snapshot(project: projectPath.map { ($0 as NSString).lastPathComponent },
                                  workspaces: wss.map { ShareLink.WorkspaceInfo(id: $0.id.uuidString, name: $0.name) },
                                  current: wss.contains { $0.id == current } ? current.uuidString : nil,
                                  consoles: consoles, theme: Theme.isLight ? "light" : "dark",
                                  live: model.sessions.liveCount, working: model.sessions.workingCount)
    }

    /// 콘솔 목록·상태를 보내고, 처음 보는 콘솔은 지난 출력·대화를 먼저 보낸다.
    private func sendMeta(to targets: [Viewer]) {
        guard !targets.isEmpty else { return }
        hookSessions()
        let snap = snapshot()
        var ctl = snap
        ctl.control = true
        for i in ctl.consoles.indices { ctl.consoles[i].input = UUID(uuidString: ctl.consoles[i].id).map { inputAllowed.contains($0) } ?? false }
        guard let json = try? JSONEncoder().encode(snap), let cjson = try? JSONEncoder().encode(ctl) else { return }
        let viewMeta = ShareLink.sseEvent("meta", String(decoding: json, as: UTF8.self))
        let controlMeta = ShareLink.sseEvent("meta", String(decoding: cjson, as: UTF8.self))
        // 보드(노드 배치·그룹·선·획). 바뀐 작업공간만 모두에게, 처음 온 사람에게는 전부.
        var boardEvents: [(UUID, Data, Bool)] = []
        for ws in sharedWorkspaces {
            let b = ShareBoard.make(ws, lang: L10n.current) { spec in
                let c = AgentCatalog.choice(for: spec)
                return (c.glyph, c.colorHex)
            }.json()
            let changed = boards[ws.id] != b
            boards[ws.id] = b
            boardEvents.append((ws.id, ShareLink.sseEvent("board", b), changed))
        }
        // 바뀐 보드는 이번 대상이 아니어도 모두에게 보낸다(다음 틱에는 바뀐 것으로 안 잡힌다).
        for (id, ev, changed) in boardEvents where changed {
            for v in viewers.values { v.send(ev); v.boards.insert(id) }
        }
        for v in targets {
            for (id, ev, _) in boardEvents where !v.boards.contains(id) {
                v.send(ev)
                v.boards.insert(id)
            }
            v.send(v.control ? controlMeta : viewMeta)
            for c in snap.consoles where !v.seen.contains(c.id) {
                v.seen.insert(c.id)
                guard let id = UUID(uuidString: c.id) else { continue }
                if let s = model.sessions.session(for: id) {
                    // 이 사람에게 아직 안 간 모아 둔 출력은 지난 출력에 이미 들어 있다.
                    v.send(Self.outEvent(id: c.id, bytes: s.rawTail, reset: true))
                    v.skipPending.insert(id)
                }
                if let tail = chats[id] { v.send(Self.chatEvent(id: c.id, entries: tail.entries, reset: true)) }
            }
        }
    }

    private func hookSessions() {
        for pair in sharedNodes where !hooked.contains(pair.node.id) {
            guard let s = model.sessions.session(for: pair.node.id) else { continue }
            hooked.insert(pair.node.id)
            let id = pair.node.id
            s.rawListeners[listenerKey] = { [weak self] slice in
                guard let self, !self.viewers.isEmpty else { return }
                self.pending[id, default: []].append(contentsOf: slice)
            }
        }
    }

    private func tick() {
        guard isActive else { return }
        if sharedWorkspaces.isEmpty { stop(); return }
        // 콘솔이 늘거나 줄면 팝오버의 입력 허용 목록을 맞춘다. 없어진 콘솔의 허용은 지운다.
        let ids = sharedNodes.map(\.node.id)
        if ids != lastConsoleIDs {
            lastConsoleIDs = ids
            inputAllowed.formIntersection(ids)
            onChange?()
        }
        guard !viewers.isEmpty else { return }
        readChats()
        sendMeta(to: Array(viewers.values))
    }

    /// claude 콘솔의 세션 기록에서 새로 붙은 줄을 읽어, 이미 그 콘솔을 받은 사람에게 보낸다.
    private func readChats() {
        var live = Set<UUID>()
        for pair in sharedNodes {
            guard let spec = pair.node.terminal, spec.agent == .claude, let sid = spec.sessionID else { continue }
            let id = pair.node.id
            live.insert(id)
            let profile = spec.profileID.flatMap { pid in model.state.profiles.first { $0.id == pid } }
            let base = (profile?.agent == .claude ? profile?.configDir : nil) ?? (NSHomeDirectory() + "/.claude")
            let path = "\(base)/projects/\(LaunchPlanner.claudeProjectDirName(for: LaunchPlanner.resolvedPath(spec.cwd)))/\(sid).jsonl"
            var tail = chats[id] ?? ChatTail(path: path)
            var reset = false
            if tail.path != path { tail = ChatTail(path: path); reset = true }
            let fresh = tail.readNew()
            let firstRead = chats[id] == nil
            chats[id] = tail
            guard !fresh.isEmpty || reset else { continue }
            // 처음 읽은 것은 이미 콘솔을 받은 사람에게 통째로, 그 뒤로는 새 줄만.
            let event = (reset || firstRead) ? Self.chatEvent(id: id.uuidString, entries: tail.entries, reset: true)
                                             : Self.chatEvent(id: id.uuidString, entries: fresh, reset: false)
            for v in viewers.values where v.seen.contains(id.uuidString) { v.send(event) }
        }
        for id in chats.keys where !live.contains(id) { chats[id] = nil }
    }

    private func flush() {
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        for v in viewers.values {
            for (id, bytes) in batch where !v.skipPending.contains(id) {
                v.send(Self.outEvent(id: id.uuidString, bytes: bytes, reset: false))
            }
            v.skipPending.removeAll()
        }
    }

    private static func outEvent(id: String, bytes: [UInt8], reset: Bool) -> Data {
        let b64 = Data(bytes).base64EncodedString()
        return ShareLink.sseEvent("out", "{\"id\":\"\(id)\",\"reset\":\(reset),\"b64\":\"\(b64)\"}")
    }

    private struct ChatPayload: Encodable {
        var id: String
        var reset: Bool
        var entries: [ShareLink.ChatEntry]
    }

    private static func chatEvent(id: String, entries: [ShareLink.ChatEntry], reset: Bool) -> Data {
        let data = (try? JSONEncoder().encode(ChatPayload(id: id, reset: reset, entries: entries))) ?? Data("{}".utf8)
        return ShareLink.sseEvent("chat", String(decoding: data, as: UTF8.self))
    }

    /// NodeStatus.color 와 같은 색. nil 은 흐린 글자색.
    static func statusHex(_ st: NodeStatus?) -> String {
        switch st {
        case .working: return Theme.accentHex
        case .idle: return "#6FCF97"
        case .waiting: return "#E9C46A"
        case .done: return "#7AA7E8"
        case .exited: return "#B5524A"
        case .starting, nil: return Theme.isLight ? "#77706A" : "#8F8882"
        }
    }

    // MARK: 주소

    static func localIPv4() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return out }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (Int32(ifa.ifa_flags) & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append(String(cString: host))
            }
        }
        return out
    }
}

/// 실시간 흐름으로 붙은 보는 사람 한 명.
@MainActor
private final class Viewer {
    let connection: NWConnection
    /// 지난 출력을 이미 보낸 콘솔.
    var seen: Set<String> = []
    /// 보드를 이미 보낸 작업공간.
    var boards: Set<UUID> = []
    /// 조작 링크로 들어왔는지.
    var control = false
    /// 이번 묶음에서 빼야 하는 콘솔(방금 지난 출력을 통째로 보냄).
    var skipPending: Set<UUID> = []
    init(connection: NWConnection) { self.connection = connection }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [connection] error in
            if error != nil { connection.cancel() }
        })
    }
}

/// claude 세션 기록 파일 하나를 끝에서부터 따라 읽는다. 읽은 자리를 기억하고, 덜 쓴 마지막 줄은 다음에 잇는다.
private struct ChatTail {
    let path: String
    var offset: UInt64 = 0
    var carry = Data()
    /// 지금까지의 대화(마지막 ShareLink.chatHistoryLimit 줄).
    var entries: [ShareLink.ChatEntry] = []

    init(path: String) { self.path = path }

    /// 새로 붙은 줄을 읽어 대화 줄로 돌려준다. 파일이 줄었으면(새로 씀) 처음부터.
    mutating func readNew() -> [ShareLink.ChatEntry] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset { offset = 0; carry = Data(); entries = [] }
        guard size > offset else { return [] }
        try? h.seek(toOffset: offset)
        guard let data = try? h.readToEnd() else { return [] }
        offset += UInt64(data.count)
        var buf = carry + data
        guard let lastNL = buf.lastIndex(of: 0x0A) else { carry = buf; return [] }
        carry = buf[(lastNL + 1)...]
        buf = buf[..<lastNL]
        let text = String(decoding: buf, as: UTF8.self)
        let fresh = ShareLink.chatEntries(fromJSONL: text.split(separator: "\n"))
        entries.append(contentsOf: fresh)
        if entries.count > ShareLink.chatHistoryLimit { entries.removeFirst(entries.count - ShareLink.chatHistoryLimit) }
        return fresh
    }
}
