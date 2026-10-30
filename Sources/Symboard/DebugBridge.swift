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
            guard let i = c["index"] as? Int, i >= 0, i < nodes.count else { return nil }
            return nodes[i]
        }
        switch op {
        case "snapshot":
            let path = cmd["path"] as? String ?? dir.appendingPathComponent("snapshot.png").path
            log.append(snapshot(to: path) ? "snapshot \(path)" : "snapshot failed")
        case "newTerminal":
            let agent = AgentKind(rawValue: cmd["agent"] as? String ?? "shell") ?? .shell
            var profileID: UUID?
            if let pi = cmd["profile"] as? Int, pi < model.state.profiles.count { profileID = model.state.profiles[pi].id }
            let spec = TerminalSpec(agent: agent, executable: cmd["executable"] as? String,
                                    extraArgs: cmd["args"] as? [String] ?? [], cwd: cmd["cwd"] as? String ?? NSHomeDirectory(),
                                    profileID: profileID)
            var point: Point?
            if let x = cmd["x"] as? Double, let y = cmd["y"] as? Double { point = Point(x: x, y: y) }
            let n = controller.addTerminal(spec: spec, at: point)
            log.append("newTerminal \(n.id)")
        case "addNode":
            let kind = NodeKind(rawValue: cmd["kind"] as? String ?? "sticky") ?? .sticky
            controller.addNode(kind: kind, size: CGSize(width: cmd["w"] as? Double ?? 260, height: cmd["h"] as? Double ?? 200),
                               title: cmd["title"] as? String ?? kind.rawValue) { n in
                n.text = cmd["text"] as? String
                n.colorHex = cmd["color"] as? String
                if let x = cmd["x"] as? Double, let y = cmd["y"] as? Double { n.frame.x = x; n.frame.y = y }
                if kind == .checklist {
                    n.checklist = (cmd["items"] as? [String] ?? []).enumerated().map { ChecklistItem(text: $0.element, done: $0.offset == 0) }
                }
                if kind == .kanban {
                    let cards = cmd["cards"] as? [[String]] ?? [[], [], []]
                    n.kanban = ["Todo", "Doing", "Done"].enumerated().map { KanbanColumn(title: $0.element, cards: $0.offset < cards.count ? cards[$0.offset] : []) }
                }
                if kind == .image {
                    // 확인용 표시 하나(이미지 영역 기준 0~1 좌표).
                    n.strokes = (cmd["mark"] as? Bool ?? false)
                        ? [Stroke(points: [Point(x: 0.2, y: 0.3), Point(x: 0.5, y: 0.7), Point(x: 0.8, y: 0.3)])] : []
                }
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
                let t = s.view.getTerminal()
                log.append("modes mouse=\(t.mouseMode) alt=\(t.isCurrentBufferAlternate) bracketed=\(t.bracketedPasteMode) appCursor=\(t.applicationCursor) scrolledBack=\(s.view.isScrolledBack)")
                log.append("--- screen \(n.title) status=\(model.sessions.status(of: n.id)?.rawValue ?? "-")\n\(s.screenText())\n---")
            }
        case "state":
            let firstResponder = controller.window?.firstResponder
            for (i, n) in nodes.enumerated() {
                let sel = controller.currentCanvas?.selectedNodeID == n.id ? " [selected]" : ""
                let foc = (model.sessions.session(for: n.id)?.view).map { $0 === firstResponder } ?? false ? " [keyboard]" : ""
                log.append("\(i) \(n.kind.rawValue) \(n.title)\(sel)\(foc) frame=\(Int(n.frame.x)),\(Int(n.frame.y)),\(Int(n.frame.w)),\(Int(n.frame.h)) status=\(model.sessions.status(of: n.id)?.rawValue ?? "-") session=\(n.terminal?.sessionID ?? "-")")
            }
        case "drag":
            // 진짜 마우스 이벤트를 창에 넣어 노드 헤더(이동)나 손잡이(크기 조절)를 끈다. dx·dy 는 캔버스 단위.
            if let n = node(cmd), let canvas = controller.currentCanvas, let nv = canvas.nodeViews[n.id] {
                let part = cmd["part"] as? String ?? "header"
                let local = part == "resize" ? NSPoint(x: nv.frame.maxX - 6, y: nv.frame.maxY - 6)
                                             : NSPoint(x: nv.frame.minX + 60, y: nv.frame.minY + 10)
                let dx = cmd["dx"] as? Double ?? 0, dy = cmd["dy"] as? Double ?? 0
                let steps = 5
                for i in 0...(steps + 1) {
                    let t = Double(min(i, steps)) / Double(steps)
                    let p = canvas.convert(NSPoint(x: local.x + dx * t, y: local.y + dy * t), to: nil)
                    let type: NSEvent.EventType = i == 0 ? .leftMouseDown : (i == steps + 1 ? .leftMouseUp : .leftMouseDragged)
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: controller.window?.windowNumber ?? 0, context: nil,
                                                  eventNumber: 0, clickCount: 1, pressure: 1) {
                        controller.window?.sendEvent(e)
                    }
                }
                log.append("drag \(part)")
            } else { log.append("drag: no node") }
        case "team":
            let spec = TerminalSpec(agent: AgentKind(rawValue: cmd["agent"] as? String ?? "shell") ?? .shell,
                                    cwd: cmd["cwd"] as? String ?? NSHomeDirectory())
            let count = cmd["count"] as? Int ?? 4
            let t = controller.launchTeam(spec: spec, count: count, teamName: cmd["name"] as? String ?? "Team",
                                          roles: Composer.roles(from: cmd["roles"] as? String ?? "", count: count))
            log.append("team \(t.name)")
        case "loop":
            if let n = node(cmd) {
                let trigger: LoopTrigger
                switch cmd["trigger"] as? String ?? "interval" {
                case "idle": trigger = .idle(seconds: cmd["value"] as? Double ?? 5)
                case "output": trigger = .output(pattern: cmd["pattern"] as? String ?? "")
                default: trigger = .interval(seconds: cmd["value"] as? Double ?? 5)
                }
                model.loops.add(LoopRule(nodeID: n.id, message: cmd["message"] as? String ?? "", trigger: trigger,
                                         goal: cmd["goal"] as? String ?? "", maxRuns: cmd["maxRuns"] as? Int ?? 20))
                log.append("loop added")
            }
        case "loops":
            for r in model.loops.rows { log.append("loop \(r.nodeTitle) \(r.trigger) enabled=\(r.enabled) runs=\(r.runs) \(r.note)") }
        case "handoff":
            if let i = cmd["from"] as? Int, let j = cmd["to"] as? Int, i < nodes.count, j < nodes.count {
                _ = model.handoff
                model.handoff.start(source: nodes[i].id, target: nodes[j].id, note: "", autoSend: true)
                log.append("handoff started")
            }
        case "handoffResult":
            log.append("handoff \(model.handoff.lastResult)")
        case "git":
            // git 카드에서 커밋·푸시·풀을 버튼과 같은 경로로 부른다.
            if let n = node(cmd), let g = controller.currentCanvas?.nodeViews[n.id]?.content as? GitContent {
                let action = cmd["action"] as? String ?? "refresh"
                g.card.message = cmd["message"] as? String ?? ""
                Task { @MainActor in
                    switch action {
                    case "commit": await g.card.commit()
                    case "push": await g.card.perform("push", [["push"]])
                    case "pull": await g.card.perform("pull", [["pull", "--ff-only"]])
                    default: await g.card.refresh()
                    }
                }
                log.append("git \(action)")
            }
        case "gitState":
            if let n = node(cmd), let g = controller.currentCanvas?.nodeViews[n.id]?.content as? GitContent {
                let s = g.card.status
                log.append("git branch=\(s?.branch ?? "-") ahead=\(s?.ahead ?? 0) changes=\(s?.changes.count ?? -1)\n\(g.card.log)")
            }
        case "studio":
            controller.showStudio(root: (cmd["root"] as? String).map { URL(fileURLWithPath: $0) })
            if let st = controller.studio?.studio {
                if let t = cmd["tab"] as? String { st.tab = t }
                if let f = cmd["code"] as? String { st.codeSelection = URL(fileURLWithPath: f) }
                if let f = cmd["md"] as? String { st.mdSelection = URL(fileURLWithPath: f) }
                if let g = cmd["graph"] as? Bool { st.showGraph = g }
                if let t = cmd["mdText"] as? String { st.mdText = t }
            }
            log.append("studio window \(controller.studio?.window?.windowNumber ?? 0)")
        case "studioPin":
            if let f = cmd["path"] as? String { controller.pinFile(URL(fileURLWithPath: f)); log.append("pinned") }
        case "studioPDF":
            if let st = controller.studio?.studio, let md = cmd["md"] as? String, let out = cmd["out"] as? String {
                st.exportPDF(from: URL(fileURLWithPath: md), to: URL(fileURLWithPath: out)) { [weak self] ok in
                    try? "pdf \(ok)".write(to: self!.dir.appendingPathComponent("pdf.txt"), atomically: true, encoding: .utf8)
                }
                log.append("pdf started")
            }
        case "studioPNG":
            if let st = controller.studio?.studio, let out = cmd["out"] as? String {
                log.append("png \(st.exportPNG(to: URL(fileURLWithPath: out)))")
            }
        case "addProfile":
            model.profiles.add(name: cmd["name"] as? String ?? "P", agent: AgentKind(rawValue: cmd["agent"] as? String ?? "claude") ?? .claude,
                               folder: cmd["folder"] as? String ?? "/tmp/symprofile")
            log.append("profile added")
        case "memory":
            // 메모를 만들고(선택) 지정 노드를 고른 뒤 Send 버튼과 같은 경로로 보낸다.
            let mem = model.memory
            mem.scope = cmd["repo"] as? String
            if let title = cmd["title"] as? String {
                mem.add()
                if let id = mem.editingID { mem.update(id, title: title, body: cmd["body"] as? String ?? "") }
                mem.editingID = nil
            }
            if let n = node(cmd) {
                controller.currentCanvas?.select(n.id)
                if cmd["send"] as? Bool == true, let first = mem.notes.last { mem.send(first, to: n.id) }
            }
            log.append("memory \(mem.note)")
        case "nodeMenu":
            // 노드 본문 메뉴 항목을 제목으로 실행한다.
            if let n = node(cmd), let nv = controller.currentCanvas?.nodeViews[n.id],
               let item = nv.content.menuItems().first(where: { $0.title == cmd["title"] as? String }),
               let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
                log.append("nodeMenu \(item.title)")
            } else { log.append("nodeMenu: not found") }
        case "pen":
            controller.setPen(cmd["on"] as? Bool ?? true)
            log.append("pen")
        case "stroke":
            // 캔버스 좌표 점들을 따라 마우스를 끈다. 펜이 켜져 있으면 보드나 이미지 노드 위에 그려진다.
            if let canvas = controller.currentCanvas, let pts = cmd["points"] as? [[Double]], pts.count > 1 {
                for (i, q) in pts.enumerated() {
                    let p = canvas.convert(CanvasGeometry.viewPoint(Point(x: q[0], y: q[1])), to: nil)
                    let type: NSEvent.EventType = i == 0 ? .leftMouseDown : (i == pts.count - 1 ? .leftMouseUp : .leftMouseDragged)
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: controller.window?.windowNumber ?? 0, context: nil,
                                                  eventNumber: 0, clickCount: 1, pressure: 1) {
                        controller.window?.sendEvent(e)
                    }
                }
                log.append("stroke \(pts.count)")
            }
        case "windowID":
            // screencapture -l 로 이 창만 찍을 때 쓴다.
            log.append("windowID \(controller.window?.windowNumber ?? 0)")
        case "usageProbe":
            log.append("limits=\(model.usage.limits) note=\(model.usage.limitsNote)\n\(model.usage.probe.lastScreen)")
        case "hit":
            // 창 기준 포인트(위에서부터)에서 마우스를 받을 뷰 줄기.
            if let cv = controller.window?.contentView, let x = cmd["x"] as? Double, let y = cmd["y"] as? Double {
                let p = NSPoint(x: x, y: cv.bounds.height - y)
                var v = cv.hitTest(p)
                var chain: [String] = []
                while let cur = v, chain.count < 12 { chain.append(String(describing: type(of: cur)).prefix(60).description); v = cur.superview }
                log.append("hit " + chain.joined(separator: " < "))
            }
        case "windows":
            // 키 창·메인 창과 열린 창 목록(시험 도구가 "초점 창 없음" 이라고 할 때 원인 확인용).
            log.append("active=\(NSApp.isActive) key=\(NSApp.keyWindow.map { "\(type(of: $0)) \($0.windowNumber)" } ?? "nil") main=\(NSApp.mainWindow?.windowNumber ?? 0)")
            for w in NSApp.windows where w.isVisible {
                log.append("  \(type(of: w)) \(w.windowNumber) canKey=\(w.canBecomeKey) level=\(w.level.rawValue)")
            }
        case "click":
            // 창 안 한 점(창 왼쪽 위 기준 포인트)에 마우스 누르기를 바로 넣는다. 앱을 앞으로 가져오지 않아 사용자 입력과 섞이지 않는다(10차).
            let title = cmd["window"] as? String
            let wid = cmd["wid"] as? Int
            if let w = NSApp.windows.first(where: { $0.isVisible && (wid != nil ? $0.windowNumber == wid : (title == nil ? $0 === controller.window : $0.title == title)) }) {
                let x = cmd["x"] as? Double ?? 0, y = cmd["y"] as? Double ?? 0
                let p = NSPoint(x: x, y: (w.contentView?.bounds.height ?? w.frame.height) - y)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        w.sendEvent(e)
                    }
                }
                let hit = w.contentView?.hitTest(p)
                log.append("click \(w.title) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            } else { log.append("click: no window \(title ?? "main")") }
        case "pick":
            // 팝업 단추(접근성 이름)에서 항목을 고르고 동작을 보낸다(누르면 메뉴가 입력을 붙잡아서 클릭 대신).
            let label = cmd["label"] as? String ?? ""
            func find(_ v: NSView) -> NSPopUpButton? {
                if let b = v as? NSPopUpButton, b.accessibilityLabel() == label { return b }
                for sub in v.subviews { if let f = find(sub) { return f } }
                return nil
            }
            if let b = NSApp.windows.lazy.compactMap({ $0.contentView.flatMap(find) }).first {
                b.selectItem(at: cmd["index"] as? Int ?? 0)
                if let a = b.action { NSApp.sendAction(a, to: b.target, from: b) }
                log.append("pick \(label) = \(b.titleOfSelectedItem ?? "")")
            } else { log.append("pick: no popup \(label)") }
        case "theme":
            log.append("isLight=\(Theme.isLight) app=\(NSApp.effectiveAppearance.name.rawValue) set=\(NSApp.appearance?.name.rawValue ?? "nil") text=\(Theme.resolved(Theme.text))")
        case "winshot":
            // 창 번호(실제 화면 캡처용, screencapture -l).
            for w in NSApp.windows where w.isVisible { log.append("win \(w.windowNumber) \(w.title)") }
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
        case "move":
            // 끌기가 끝났을 때와 같은 모델 변경.
            if let n = node(cmd) {
                controller.model.mutateNode(n.id) { $0.frame.x += cmd["dx"] as? Double ?? 0; $0.frame.y += cmd["dy"] as? Double ?? 0 }
                controller.currentCanvas?.reloadNodes()
                log.append("move \(n.title)")
            }
        case "remove":
            // Delete 키·닫기 단추와 같은 길(확인 없이).
            if let n = node(cmd) { controller.removeNodes([n.id]); log.append("remove \(n.title)") }
        case "undo":
            // 메뉴 ⌘Z·⇧⌘Z 와 같은 길(BoardWindow.undo/redo).
            let w = controller.window as? BoardWindow
            if cmd["redo"] as? Bool ?? false { w?.redo(nil) } else { w?.undo(nil) }
            let fr = controller.window?.firstResponder
            log.append("undo canUndo=\(controller.model.canUndoBoard) canRedo=\(controller.model.canRedoBoard) responder=\(fr.map { String(describing: type(of: $0)) } ?? "nil") isText=\(fr is NSText)")
        case "perform":
            // 도구 막대 동작을 이름으로 부른다.
            if let sel = cmd["selector"] as? String { NSApp.sendAction(Selector(sel), to: controller, from: nil) }
        case "openProject":
            controller.openProject(cmd["path"] as? String ?? "/tmp")
            log.append("project \(controller.projectPath)")
        case "home":
            if cmd["on"] as? Bool ?? true { controller.goHome() } else { controller.setHome(false) }
        case "tool":
            // select / pen / eraser / text / sticky / checklist / kanban / web / agent:<id>
            let t = cmd["tool"] as? String ?? "select"
            let tool: BoardTool
            switch t {
            case "pen": tool = .pen
            case "eraser": tool = .eraser
            case "text": tool = .place(.text)
            case "sticky": tool = .place(.sticky)
            case "checklist": tool = .place(.checklist)
            case "kanban": tool = .place(.kanban)
            case "web": tool = .place(.web)
            case "orchestrator": tool = .place(.orchestrator)
            case "calendar": tool = .place(.calendar)
            case "rect", "ellipse", "diamond", "arrow": tool = .place(.shape(t))
            default: tool = t.hasPrefix("agent:") ? .place(.agent(String(t.dropFirst(6)))) : .select
            }
            controller.setTool(tool)
            log.append("tool \(t)")
        case "spawnMenu":
            controller.chrome.spawnMenuOpen = cmd["open"] as? Bool ?? true
        case "mouse":
            // 캔버스 좌표로 마우스를 옮기거나(move) 누른다(click).
            if let canvas = controller.currentCanvas {
                let p = canvas.convert(CanvasGeometry.viewPoint(Point(x: cmd["x"] as? Double ?? 0, y: cmd["y"] as? Double ?? 0)), to: nil)
                let kinds: [NSEvent.EventType] = (cmd["click"] as? Bool ?? false) ? [.leftMouseDown, .leftMouseUp] : [.mouseMoved]
                for type in kinds {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: controller.window?.windowNumber ?? 0, context: nil,
                                                  eventNumber: 0, clickCount: 1, pressure: 1) {
                        if type == .mouseMoved { canvas.mouseMoved(with: e) } else { controller.window?.sendEvent(e) }
                    }
                }
                let hit = controller.window?.contentView?.hitTest(p)
                log.append("mouse hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            }
        case "select":
            controller.currentCanvas?.select(node(cmd)?.id)
        case "command":
            controller.chrome.command = cmd["text"] as? String ?? ""
            if cmd["send"] as? Bool ?? true { controller.runCommand() }
            log.append("command toast=\(controller.chrome.toast ?? "-")")
        case "chrome":
            let ch = controller.chrome
            log.append("command=\(ch.command.debugDescription) promptEditor=\(controller.promptEditor.open)")
            log.append("chrome tool=\(ch.tool) zoom=\(ch.zoomPercent) live=\(ch.liveCount) branch=\(ch.branch ?? "-") changes=\(ch.changeCount) home=\(ch.showingHome)")
        case "link":
            // from: 노드 번호, to: 노드 번호 또는 team: 팀 번호
            if let i = cmd["from"] as? Int, i < nodes.count, let nv = controller.currentCanvas?.nodeViews[nodes[i].id] {
                if let j = cmd["to"] as? Int, j < nodes.count { nv.link(to: nodes[j].id) }
                if let t = cmd["team"] as? Int, t < model.selectedWorkspace.teams.count { nv.link(to: model.selectedWorkspace.teams[t].id) }
                log.append("linked")
            }
        case "collapse":
            if let t = cmd["team"] as? Int, t < model.selectedWorkspace.teams.count {
                controller.currentCanvas?.setGroup(model.selectedWorkspace.teams[t].id, collapsed: cmd["on"] as? Bool ?? true)
            }
        case "dragGroup":
            if let t = cmd["team"] as? Int, t < model.selectedWorkspace.teams.count, let canvas = controller.currentCanvas,
               let g = canvas.groupViews[model.selectedWorkspace.teams[t].id] {
                let local = NSPoint(x: g.frame.minX + 30, y: g.frame.minY + 14)
                let dx = cmd["dx"] as? Double ?? 0, dy = cmd["dy"] as? Double ?? 0
                for i in 0...6 {
                    let tt = Double(min(i, 5)) / 5
                    let p = canvas.convert(NSPoint(x: local.x + dx * tt, y: local.y + dy * tt), to: nil)
                    let type: NSEvent.EventType = i == 0 ? .leftMouseDown : (i == 6 ? .leftMouseUp : .leftMouseDragged)
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        controller.window?.sendEvent(e)
                    }
                }
                let hp = canvas.convert(local, to: nil)
                let hit = controller.window?.contentView?.hitTest(controller.window!.contentView!.convert(hp, from: nil))
                log.append("dragGroup hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil") frame=\(g.frame)")
            }
        case "confirm":
            if let cf = controller.chrome.confirm {
                controller.chrome.confirm = nil
                if cmd["yes"] as? Bool ?? false { cf.action() } else { cf.onCancel?() }
                log.append("confirm \(cf.message)")
            } else { log.append("confirm: none") }
        case "resumeAll":
            controller.answerResumeAll(cmd["yes"] as? Bool ?? true)
            log.append("resumeAll")
        case "pending":
            log.append("pending \(controller.model.sessions.pendingResume.count)")
        case "composer":
            // open, count, tiles(배열), role(이름), name, spawn
            let cs = controller.composer
            if cmd["open"] as? Bool ?? true { if !cs.open { controller.openComposer(nil) } }
            if let n = cmd["count"] as? Int { cs.setCount(n) }
            if let t = cmd["tiles"] as? [String] { cs.tiles = t }
            if let r = cmd["role"] as? String, let role = ComposerState.roles.first(where: { $0.name == r }) { cs.pick(role: role) }
            if let name = cmd["name"] as? String { cs.teamName = name }
            if cmd["spawn"] as? Bool ?? false { controller.spawnComposer() }
            log.append("composer \(cs.teamName) \(cs.tiles)")
        case "wire":
            // orch: 노드 번호, team: 팀 번호 또는 to: 노드 번호
            if let o = cmd["orch"] as? Int, o < nodes.count {
                if let t = cmd["team"] as? Int, t < model.selectedWorkspace.teams.count { controller.toggleWire(nodes[o].id, to: model.selectedWorkspace.teams[t].id) }
                if let j = cmd["to"] as? Int, j < nodes.count { controller.toggleWire(nodes[o].id, to: nodes[j].id) }
                if let on = cmd["connect"] as? Bool { controller.chrome.connectingOrchestrator = on ? nodes[o].id : nil }
                log.append("wire")
            }
        case "orchSend":
            if let o = cmd["orch"] as? Int, o < nodes.count {
                log.append("orchSend \(controller.orchestratorSend(nodes[o].id, text: cmd["text"] as? String ?? ""))")
            }
        case "mission":
            controller.chrome.missionOpen = cmd["open"] as? Bool ?? true
            if let n = node(cmd) { controller.chrome.missionSelected = n.id }
            if let t = cmd["team"] as? Int, t < model.selectedWorkspace.teams.count { controller.chrome.missionSelected = model.selectedWorkspace.teams[t].id }
        case "loopsPage":
            controller.chrome.loopsPage = cmd["page"] as? String
        case "loopForm":
            // 틀 이름, 대상(all 또는 노드 번호 목록), 멈춤 설정을 채우고 save 면 저장한다.
            let d = controller.loopDraft
            if let t = cmd["template"] as? String, let tpl = LoopTemplate.all.first(where: { $0.name == t }) { d.apply(tpl) }
            if let m = cmd["message"] as? String { d.message = m }
            if let n = cmd["name"] as? String { d.name = n }
            if let w = cmd["when"] as? String { d.when = w }
            if let v = cmd["minutes"] as? Double { d.intervalMinutes = v }
            if let v = cmd["idle"] as? Double { d.idleSeconds = v }
            if let p = cmd["pattern"] as? String { d.pattern = p }
            if let idx = cmd["targets"] as? [Int] { d.targetAll = false; d.picked = Set(idx.compactMap { $0 < nodes.count ? nodes[$0].id : nil }) }
            if cmd["all"] as? Bool == true { d.targetAll = true }
            if let r = cmd["runs"] as? Int { d.useRuns = true; d.runs = r }
            if let g = cmd["goalMode"] as? String { d.useGoal = true; d.goalMode = g }
            if let g = cmd["goal"] as? String { d.goal = g }
            if let g = cmd["goalCommand"] as? String { d.goalCommand = g }
            if let b = cmd["background"] as? Bool { d.background = b }
            controller.chrome.loopsPage = "form"
            if cmd["save"] as? Bool == true { controller.saveLoop() }
            log.append("loopForm valid=\(d.isValid)")
        case "kanbanAdd":
            // index: 칸반 노드, column, title, due(오늘부터 날 수), priority
            if let n = node(cmd), let ci = cmd["column"] as? Int {
                var card = KanbanCard(title: cmd["title"] as? String ?? "Card")
                if let d = cmd["due"] as? Int { card.due = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(d) * 86400)) }
                card.priority = cmd["priority"] as? String
                card.done = cmd["done"] as? Bool ?? false
                model.mutateNode(n.id) { node in
                    guard var cols = node.kanban, ci < cols.count else { return }
                    for i in cols.indices where cols[i].items == nil { cols[i].items = cols[i].allCards; cols[i].cards = [] }
                    cols[ci].items!.append(card)
                    node.kanban = cols
                }
                controller.currentCanvas?.nodeViews[n.id]?.syncFromModel()
                log.append("kanbanAdd")
            }
        case "kanbanMove":
            if let n = node(cmd), let from = cmd["from"] as? Int, let to = cmd["to"] as? Int {
                model.mutateNode(n.id) { node in
                    guard var cols = node.kanban, from < cols.count, to < cols.count, let card = cols[from].allCards.first else { return }
                    if cols[from].items == nil { cols[from].items = cols[from].allCards; cols[from].cards = [] }
                    Board.move(card: cols[from].items![0].id, to: cols[to].id, at: nil, in: &cols)
                    _ = card
                    node.kanban = cols
                }
                controller.currentCanvas?.nodeViews[n.id]?.syncFromModel()
                log.append("kanbanMove")
            }
        case "cardEditor":
            if let n = node(cmd) { NotificationCenter.default.post(name: .openCardEditor, object: n.id, userInfo: ["column": cmd["column"] as? Int ?? 0]) }
        case "event":
            if let n = node(cmd) {
                let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(cmd["day"] as? Int ?? 0) * 86400))
                if cmd["editor"] as? Bool == true {
                    NotificationCenter.default.post(name: .openEventEditor, object: n.id, userInfo: ["day": day])
                } else {
                    model.mutateNode(n.id) { $0.events = ($0.events ?? []) + [CalendarEvent(title: cmd["title"] as? String ?? "Event", day: day, colorHex: cmd["color"] as? String ?? "#56A8F5")] }
                    controller.currentCanvas?.nodeViews[n.id]?.syncFromModel()
                }
                log.append("event")
            }
        case "insertMenu":
            controller.chrome.insertOpen = cmd["open"] as? Bool ?? true
        case "shapeStyle":
            if let n = node(cmd) {
                model.mutateNode(n.id) { node in
                    var sp = node.shape ?? ShapeSpec()
                    if let v = cmd["stroke"] as? String { sp.strokeHex = v }
                    if let v = cmd["fill"] as? String { sp.fillHex = v.isEmpty ? nil : v }
                    if let v = cmd["width"] as? Double { sp.strokeWidth = v }
                    if let v = cmd["dash"] as? String { sp.dash = v }
                    if let v = cmd["rough"] as? Double { sp.roughness = v }
                    node.shape = sp
                }
                controller.currentCanvas?.nodeViews[n.id]?.syncFromModel()
            }
        case "image":
            controller.addImage(url: URL(fileURLWithPath: cmd["path"] as? String ?? ""), at: Point(x: cmd["x"] as? Double ?? 0, y: cmd["y"] as? Double ?? 0))
            log.append("image")
        case "pen2":
            if let c = cmd["color"] as? String { controller.chrome.penColor = c }
            if let w = cmd["width"] as? Double { controller.chrome.penWidth = w }
        case "projectGit":
            // 브랜치 칩 카드: open, exclude(경로 목록), message, commit
            if let card = controller.chrome.gitCard {
                if let o = cmd["open"] as? Bool { controller.chrome.gitOpen = o }
                if let ex = cmd["exclude"] as? [String] { card.excluded = Set(ex) }
                if let m = cmd["message"] as? String { card.message = m }
                if let h = cmd["history"] as? Bool { card.showHistory = h }
                if cmd["commit"] as? Bool == true { Task { await card.commit() } }
                if cmd["refresh"] as? Bool == true { Task { await card.refresh() } }
                log.append("projectGit \(card.status?.changes.count ?? -1) changes, result=\(card.resultLine ?? "-")\n\(card.log)")
            } else { log.append("projectGit: none") }
        case "web":
            // index: 웹 노드. url, device, newTab, inspector, select
            if let n = node(cmd), let w = controller.currentCanvas?.nodeViews[n.id]?.content as? WebContent {
                if cmd["newTab"] as? Bool == true { w.newTab() }
                if let u = cmd["url"] as? String { w.navigate(u) }
                if cmd.keys.contains("device") { w.setDevice(cmd["device"] as? String) }
                if let t = cmd["tab"] as? Int { w.select(t) }
                if cmd["inspector"] as? Bool == true { w.openInspector() }
                log.append("web tabs=\(w.state.tabs) device=\(w.state.device ?? "-") console=\(w.state.console.map(\.text))")
            }
        case "inspect":
            // index: 인스펙터 노드, path(배열) 고르기, tab
            if let n = node(cmd), let ic = controller.currentCanvas?.nodeViews[n.id]?.content as? InspectorContent {
                let m = ic.inspector
                if let t = cmd["tab"] as? String { m.tab = t }
                if cmd["refresh"] as? Bool == true { m.refresh() }
                if let p = cmd["path"] as? [Int] { m.expanded.formUnion((0...p.count).map { p.prefix($0).map(String.init).joined(separator: ".") }); m.expanded.remove("0"); m.select(p) }
                if let e = cmd["eval"] as? String { m.expr = e; m.evaluate() }
                log.append("inspect root=\(m.root?.tag ?? "-") box=\(m.box)")
            }
        case "usage":
            controller.chrome.usageOpen = cmd["open"] as? Bool ?? true
            if cmd["refresh"] as? Bool == true { model.usage.refresh() }
            if let pg = cmd["page"] as? String { NotificationCenter.default.post(name: .usagePage, object: pg) }
            let st = model.usage.stats
            log.append("usage scanning=\(model.usage.scanning) \(model.usage.note) " + st.map { "\($0.key.rawValue): total=\($0.value.totalTokens) sessions=\($0.value.sessions) block=\(String(describing: $0.value.blockEnd))" }.joined(separator: "; "))
        case "studio2":
            // kind(Code/Markdown/Docs), file, mode, text, close, insert, expand(폴더 경로들)
            let st = controller.studioState
            if let k = cmd["kind"] as? String { if st.kind != (k == "Docs" ? "Documents" : k) { controller.openStudio(tab: k) } }
            if let ex = cmd["expand"] as? [String] { for e in ex { st.expanded.insert(StudioState.key(URL(fileURLWithPath: e))) } }
            if let f = cmd["file"] as? String { st.open(URL(fileURLWithPath: f)) }
            if let m = cmd["mode"] as? String { st.mdMode = m }
            if let t = cmd["text"] as? String { st.text = t }
            if let q = cmd["query"] as? String { st.query = q }
            if cmd["save"] as? Bool == true { st.save() }
            if cmd["insert"] as? Bool == true { controller.studioInsert() }
            if cmd["close"] as? Bool == true { controller.closeStudio() }
            if let out = cmd["pdf"] as? String, let f = st.selected { controller.exportPDF(markdown: f, to: URL(fileURLWithPath: out)) }
            log.append("studio2 kind=\(st.kind ?? "-") file=\(st.selected?.lastPathComponent ?? "-") dirty=\(st.dirty) lines=\(st.lineCount)")
        case "memory2":
            // page, agent, scan(실제 CLI 호출), accept, card
            let h = controller.memoryHub
            if let p = cmd["page"] as? String { h.page = p }
            if let e = cmd["edit"] as? Int, e < h.notes.count { h.editing = h.notes[e]; h.page = "edit" }
            if let a = cmd["agent"] as? String { h.agent = a }
            if cmd["scan"] as? Bool == true { h.startScan() }
            if cmd["accept"] as? Bool == true { h.acceptProposals() }
            if cmd["card"] as? Bool == true { controller.placeMemoryCard() }
            if let fake = cmd["fake"] as? Int {
                h.page = "scan"; h.phase = 2
                for i in 0..<fake { h.proposals.append(MemoryHub.Proposal(fact: FactStream.Fact(category: FactStream.categories[i % 6], title: "Fact \(i)", body: "Body of fact \(i) with src/hello.py."))) }
            }
            if let t = cmd["add"] as? String { h.save(MemoryNote(repoPath: h.repo, title: t, body: cmd["body"] as? String ?? "", category: cmd["category"] as? String)) }
            log.append("memory2 page=\(h.page ?? "-") phase=\(h.phase) proposals=\(h.proposals.count) notes=\(h.notes.count) error=\(h.scanError ?? "-")")
        case "docs":
            // generate(종류 id, 실제 CLI), depth, agent, select, card, pdf
            let d = controller.docStudio
            if controller.studioState.kind != "Documents" && cmd["open"] as? Bool != false { controller.openStudio(tab: "Docs") }
            if let a = cmd["agent"] as? String { d.agent = a }
            if let dp = cmd["depth"] as? String { d.depth = dp }
            if let s = cmd["select"] as? String { d.selected = s }
            if let v = cmd["view"] as? String { d.view = v }
            if let g = cmd["generate"] as? String { d.generate(kind: g) }
            if let fake = cmd["fakeLive"] as? String { d.selected = "overview"; d.generating = "overview"; d.startedAt = Date().addingTimeInterval(-13); d.live = fake; d.activity = "Writing" }
            if cmd["stopFake"] as? Bool == true { d.generating = nil; d.live = "" }
            if cmd["card"] as? Bool == true { controller.placeDocumentCard(d.selected) }
            if let out = cmd["pdf"] as? String { controller.exportPDF(markdown: d.url(for: d.selected), to: URL(fileURLWithPath: out)) }
            d.reload()
            log.append("docs selected=\(d.selected) generating=\(d.generating ?? "-") live=\(d.live.count) library=\(d.library.keys.sorted()) error=\(d.error ?? "-") activity=\(d.activity)")
        case "diagram":
            // open, agent, style, generate(종류 id, 실제 CLI), starter, json(가짜 결과로 그리기)
            let d = controller.diagrams
            if let o = cmd["open"] as? Bool { d.open = o }
            if let a = cmd["agent"] as? String { d.agent = a }
            if let s = cmd["style"] as? String { d.style = s }
            if let g = cmd["generate"] as? String { d.generate(kind: g) }
            if let s = cmd["starter"] as? String { d.placeStarter(s, at: controller.scrollView.visibleCenter) }
            if let j = cmd["json"] as? String, let spec = DiagramSpec.parse(j) { d.draw(spec, center: controller.scrollView.visibleCenter) }
            if cmd["fakeDrawing"] as? Bool == true { d.drawing = "Claude Code"; _ = d.placeStarter("Flow", at: controller.scrollView.visibleCenter, empty: true) }
            log.append("diagram drawing=\(d.drawing ?? "-") error=\(d.error ?? "-") nodes=\(model.selectedWorkspace.nodes.count) links=\(model.selectedWorkspace.links?.count ?? 0)")
        case "accounts":
            if let o = cmd["open"] as? Bool { controller.chrome.accountsOpen = o }
            if let n = cmd["connect"] as? String { let p = model.profiles.connect(name: n, agent: .claude); if cmd["console"] as? Bool == true { controller.openProfileConsole(p, agent: .claude) } }
            if let i = cmd["use"] as? Int, i < model.state.profiles.count { model.profiles.setActive(model.state.profiles[i].id, for: model.state.profiles[i].agent) }
            log.append("accounts profiles=\(model.state.profiles.map(\.name)) active=\(model.state.activeProfiles ?? [:])")
        case "setText":
            if let n = node(cmd) {
                model.mutateNode(n.id) { $0.text = cmd["text"] as? String ?? "" }
                controller.currentCanvas?.nodeViews[n.id]?.syncFromModel()
                log.append("setText")
            }
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
