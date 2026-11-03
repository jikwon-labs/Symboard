import Foundation
import Testing
@testable import SymboardCore

@Suite struct ShareTests {
    @Test func tokenIsRandomHex() {
        let a = ShareLink.makeToken(), b = ShareLink.makeToken()
        #expect(a.count == 32)
        #expect(a.allSatisfy { $0.isHexDigit })
        #expect(a != b)
    }

    @Test func routesOnlyWithRightToken() {
        let t = "0123456789abcdef0123456789abcdef"
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)", token: t) == .page(control: false))
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/", token: t) == .page(control: false))
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)?x=1", token: t) == .page(control: false))
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/events", token: t) == .events(control: false))
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/input", token: t) == .notFound)
        #expect(ShareLink.route(method: "POST", path: "/v/\(t)/events", token: t) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/v/0123456789abcdef0123456789abcdee", token: t) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/v/", token: t) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/", token: t) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/events/x", token: t) == .notFound)
        #expect(!ShareLink.constantTimeEqual("", ""))
    }

    @Test func parsesRequestLineOnlyWhenHeadIsComplete() {
        #expect(ShareLink.requestLine(Data("GET /v/abc HTTP/1.1\r\nHost: x\r\n".utf8)) == nil)
        let line = ShareLink.requestLine(Data("GET /v/abc HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        #expect(line?.method == "GET")
        #expect(line?.path == "/v/abc")
        #expect(ShareLink.requestLine(Data("garbage\r\n\r\n".utf8)) == nil)
    }

    @Test func ranksLanBeforeTailscaleAndDropsLoopback() {
        let r = ShareLink.rankedAddresses(["127.0.0.1", "100.101.1.2", "203.0.113.5", "169.254.3.4", "192.168.0.12", "10.0.0.3", "192.168.0.12"])
        #expect(r == ["192.168.0.12", "10.0.0.3", "100.101.1.2", "203.0.113.5"])
        #expect(ShareLink.url(host: "10.0.0.3", port: 47800, token: "ab") == "http://10.0.0.3:47800/v/ab")
    }

    @Test func tailTrimsAtLineBoundary() {
        let small: [UInt8] = Array("abc".utf8)
        #expect(ShareLink.trimmedTail(small, limit: 10) == small)
        let bytes: [UInt8] = Array("aaaaaaaa\nbbbb\ncc".utf8)  // 16
        let t = ShareLink.trimmedTail(bytes, limit: 12)        // 뒤 6바이트 "bb\ncc" 근처에서 줄 시작
        #expect(t == Array("cc".utf8))
        #expect(t.count <= 12)
    }

    @Test func sseEventShape() {
        #expect(String(decoding: ShareLink.sseEvent("meta", "{}"), as: UTF8.self) == "event: meta\ndata: {}\n\n")
        let head = String(decoding: ShareLink.httpHead(status: "200 OK", contentType: "text/html"), as: UTF8.self)
        #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(head.contains("Cache-Control: no-store"))
        #expect(head.hasSuffix("\r\n\r\n"))
    }

    @Test func chatKeepsPeopleRepliesAndToolLinesOnly() {
        let lines: [Substring] = [
            #"{"type":"user","message":{"role":"user","content":"짧게 말해"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<system-reminder>x</system-reminder>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<system-reminder>hidden</system-reminder>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name><command-args></command-args>"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"  네, 됩니다.  "}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test\nmore","description":"Run tests"}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.swift"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"attachment"}"#,
            #"not json"#,
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"sub agent"}]}}"#,
        ]
        let e = ShareLink.chatEntries(fromJSONL: lines)
        #expect(e == [
            .init(role: "user", text: "짧게 말해"),
            .init(role: "user", text: "/clear"),
            .init(role: "assistant", text: "네, 됩니다."),
            .init(role: "tool", text: "Bash · Run tests"),
            .init(role: "tool", text: "Read · /a/b.swift"),
        ])
    }

    @Test func imageRouteNeedsUUID() {
        let t = "0123456789abcdef0123456789abcdef"
        let id = UUID().uuidString
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/img/\(id)", token: t) == .image(id))
        #expect(ShareLink.route(method: "GET", path: "/v/\(t)/img/../../etc", token: t) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/v/wrong/img/\(id)", token: t) == .notFound)
    }

    @Test func boardHidesPrivateFieldsAndMatchesGroupFrame() {
        let team = Team(name: "Builders")
        var a = BoardNode(kind: .terminal, frame: Rect(x: 0, y: 0, w: 600, h: 400), title: "Ada")
        a.terminal = TerminalSpec(agent: .claude, cwd: "/secret/path")
        a.terminal?.sessionID = "sid-123"
        a.teamID = team.id
        var b = BoardNode(kind: .sticky, frame: Rect(x: 700, y: 100, w: 240, h: 220), title: "Note")
        b.text = "hello"
        b.teamID = team.id
        var img = BoardNode(kind: .image, frame: Rect(x: 0, y: 600, w: 100, h: 100), title: "Pic")
        img.text = "/Users/me/Desktop/private.png"
        var ws = Workspace(name: "WS", nodes: [a, b, img])
        ws.teams = [team]
        ws.links = [NodeLink(from: a.id, to: b.id)]
        let board = ShareBoard.make(ws, lang: .en) { _ in ("C", "#E8704A") }
        let json = board.json()
        #expect(!json.contains("/secret/path"))
        #expect(!json.contains("sid-123"))
        #expect(!json.contains("private.png"))
        #expect(json.contains("hello"))
        let g = try! #require(board.groups.first)
        #expect(g.x == -14 && g.y == -44 && g.w == 968 && g.h == 458)
        #expect(g.members == [a.id.uuidString])
        #expect(board.links.count == 1)
        #expect(board.nodes.first?.glyph == "C")
    }

    @Test func controlLinkRoutesAndInputNeedsPOST() {
        let t = "0123456789abcdef0123456789abcdef", c = "fedcba9876543210fedcba9876543210"
        #expect(ShareLink.route(method: "GET", path: "/c/\(c)", token: t, controlToken: c) == .page(control: true))
        #expect(ShareLink.route(method: "GET", path: "/c/\(c)/events", token: t, controlToken: c) == .events(control: true))
        #expect(ShareLink.route(method: "POST", path: "/c/\(c)/input", token: t, controlToken: c) == .input)
        #expect(ShareLink.route(method: "GET", path: "/c/\(c)/input", token: t, controlToken: c) == .notFound)
        // 보기 토큰으로는 입력할 수 없고, 조작 토큰을 /v/ 에 써도 안 된다.
        #expect(ShareLink.route(method: "POST", path: "/v/\(t)/input", token: t, controlToken: c) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/v/\(c)", token: t, controlToken: c) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/c/\(t)", token: t, controlToken: c) == .notFound)
        #expect(ShareLink.route(method: "GET", path: "/c/\(c)", token: t, controlToken: nil) == .notFound)
    }

    @Test func inputOnlyForAllowedConsoles() {
        let a = UUID(), b = UUID()
        func body(_ r: ShareLink.InputRequest) -> Data { try! JSONEncoder().encode(r) }
        #expect(ShareLink.inputAction(body(.init(id: a.uuidString, keys: "ls\r")), allowed: [a]) == .keys(a, Array("ls\r".utf8)))
        #expect(ShareLink.inputAction(body(.init(id: a.uuidString, text: "안녕", submit: true)), allowed: [a]) == .text(a, "안녕", submit: true))
        #expect(ShareLink.inputAction(body(.init(id: b.uuidString, keys: "rm -rf ~\r")), allowed: [a]) == nil)
        #expect(ShareLink.inputAction(body(.init(id: a.uuidString, text: "   ")), allowed: [a]) == nil)
        #expect(ShareLink.inputAction(Data("not json".utf8), allowed: [a]) == nil)
        #expect(ShareLink.inputAction(body(.init(id: a.uuidString, keys: String(repeating: "x", count: 9000))), allowed: [a]) == nil)
    }

    @Test func requestHeadReadsContentLength() {
        let raw = Data("POST /c/x/input HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhello".utf8)
        let h = try! #require(ShareLink.requestHead(raw))
        #expect(h.method == "POST" && h.path == "/c/x/input" && h.contentLength == 5)
        #expect(String(decoding: raw[h.bodyStart...], as: UTF8.self) == "hello")
    }

    @Test func boardJSONIsStable() {
        var n = BoardNode(kind: .sticky, frame: Rect(x: 1, y: 2, w: 3, h: 4), title: "N")
        n.text = "t"
        let ws = Workspace(name: "W", nodes: [n])
        let a = ShareBoard.make(ws, lang: .en) { _ in ("C", "#fff") }.json()
        for _ in 0..<20 { #expect(ShareBoard.make(ws, lang: .en) { _ in ("C", "#fff") }.json() == a) }
    }
}
