import AppKit
import SymboardCore

/// 자동 확인용 통로. `<상태 폴더>/debug/` 가 있을 때만 동작한다.
/// `cmd.json` 에 명령 배열을 쓰면 앱이 읽고 지운 뒤 차례로 실행하고 `result.txt` 에 결과를 남긴다.
/// screencapture 가 화면 기록 권한 없이 실패하는 환경에서 앱이 스스로 창을 PNG 로 남기기 위해 둔다.
@MainActor
final class DebugBridge {
    unowned let controller: MainWindowController
    let dir: URL
    private var timer: Timer?

    init(controller: MainWindowController, home: URL) {
        self.controller = controller
        self.dir = home.appendingPathComponent("debug", isDirectory: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let cmdURL = dir.appendingPathComponent("cmd.json")
        guard FileManager.default.fileExists(atPath: cmdURL.path),
              let data = try? Data(contentsOf: cmdURL) else { return }
        try? FileManager.default.removeItem(at: cmdURL)
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            write("error: bad json")
            return
        }
        run(list, index: 0, log: [])
    }

    private func run(_ list: [[String: Any]], index: Int, log: [String]) {
        guard index < list.count else {
            write(log.joined(separator: "\n"))
            return
        }
        let cmd = list[index]
        var log = log
        var delay = 0.0
        let op = cmd["op"] as? String ?? ""
        let model = controller.model
        let nodes = model.selectedWorkspace.nodes
        func node(_ c: [String: Any]) -> BoardNode? {
            guard let i = c["index"] as? Int, i < nodes.count else { return nil }
            return nodes[i]
        }
        switch op {
        case "snapshot":
            let path = cmd["path"] as? String ?? dir.appendingPathComponent("snapshot.png").path
            log.append(snapshot(to: path) ? "snapshot \(path)" : "snapshot failed")
        case "newTerminal":
            let agent = AgentKind(rawValue: cmd["agent"] as? String ?? "shell") ?? .shell
            let spec = TerminalSpec(agent: agent, executable: cmd["executable"] as? String,
                                    extraArgs: cmd["args"] as? [String] ?? [], cwd: cmd["cwd"] as? String ?? NSHomeDirectory())
            var point: Point?
            if let x = cmd["x"] as? Double, let y = cmd["y"] as? Double { point = Point(x: x, y: y) }
            let n = controller.addTerminal(spec: spec, at: point)
            log.append("newTerminal \(n.id)")
        case "addNode":
            let kind = NodeKind(rawValue: cmd["kind"] as? String ?? "sticky") ?? .sticky
            controller.addNode(kind: kind, size: CGSize(width: cmd["w"] as? Double ?? 260, height: cmd["h"] as? Double ?? 200),
                               title: cmd["title"] as? String ?? kind.rawValue) { n in
                n.text = cmd["text"] as? String
                if kind == .checklist { n.checklist = [] }
                if kind == .kanban { n.kanban = [KanbanColumn(title: "Todo"), KanbanColumn(title: "Doing"), KanbanColumn(title: "Done")] }
            }
            log.append("addNode \(kind.rawValue)")
        case "send":
            if let n = node(cmd), let s = model.sessions.session(for: n.id) {
                s.view.send(txt: (cmd["text"] as? String ?? "").replacingOccurrences(of: "\\r", with: "\r"))
                log.append("send \(n.title)")
            } else { log.append("send: no node") }
        case "sendKey":
            if let n = node(cmd), let s = model.sessions.session(for: n.id), let code = cmd["byte"] as? Int {
                s.view.send([UInt8(code)])
                log.append("sendKey \(code)")
            }
        case "screen":
            if let n = node(cmd), let s = model.sessions.session(for: n.id) {
                log.append("--- screen \(n.title) status=\(s.currentStatus().rawValue)\n\(s.screenText())\n---")
            }
        case "state":
            for (i, n) in nodes.enumerated() {
                log.append("\(i) \(n.kind.rawValue) \(n.title) frame=\(Int(n.frame.x)),\(Int(n.frame.y)),\(Int(n.frame.w)),\(Int(n.frame.h)) status=\(model.sessions.status(of: n.id)?.rawValue ?? "-") session=\(n.terminal?.sessionID ?? "-")")
            }
        case "wait":
            delay = cmd["seconds"] as? Double ?? 1
        case "zoom":
            controller.scrollView.center(on: Point(x: cmd["x"] as? Double ?? 0, y: cmd["y"] as? Double ?? 0), zoom: cmd["zoom"] as? Double ?? 1)
        case "fit":
            controller.zoomToFit(nil)
        case "selectWorkspace":
            if let i = cmd["index"] as? Int, i < model.state.workspaces.count { model.selectWorkspace(model.state.workspaces[i].id) }
        case "addWorkspace":
            model.addWorkspace(name: cmd["name"] as? String ?? "Workspace")
        case "panelTab":
            controller.showPanel(tab: cmd["tab"] as? String ?? "Mission")
        case "perform":
            // 도구 막대 동작을 이름으로 부른다.
            if let sel = cmd["selector"] as? String { NSApp.sendAction(Selector(sel), to: controller, from: nil) }
        case "quit":
            write((log + ["quit"]).joined(separator: "\n"))
            NSApp.terminate(nil)
            return
        default:
            log.append("unknown op \(op)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.run(list, index: index + 1, log: log)
        }
    }

    private func write(_ s: String) {
        try? s.write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    /// 창 내용을 PNG 로. 레이어 트리를 그대로 그려서 화면 기록 권한이 필요 없다.
    func snapshot(to path: String) -> Bool {
        guard let window = controller.window, let view = window.contentView?.superview ?? window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
