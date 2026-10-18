import AppKit
import SymboardCore

/// 캔버스 크기와 원점. 캔버스 좌표 (0,0) 이 문서 뷰 한가운데에 온다.
enum CanvasGeometry {
    static let size: CGFloat = 60_000
    static let origin: CGFloat = size / 2
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 3

    static func viewRect(_ r: Rect) -> NSRect {
        NSRect(x: r.x + origin, y: r.y + origin, width: r.w, height: r.h)
    }

    static func modelRect(_ r: NSRect) -> Rect {
        Rect(x: r.minX - origin, y: r.minY - origin, w: r.width, h: r.height)
    }

    static func modelPoint(_ p: NSPoint) -> Point { Point(x: p.x - origin, y: p.y - origin) }
    static func viewPoint(_ p: Point) -> NSPoint { NSPoint(x: p.x + origin, y: p.y + origin) }
}

/// 이동·확대/축소가 되는 보드. 확대/축소는 NSScrollView 의 magnification 을 쓴다.
final class BoardScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMagnification = true
        minMagnification = CanvasGeometry.minZoom
        maxMagnification = CanvasGeometry.maxZoom
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        drawsBackground = true
        backgroundColor = Theme.canvas
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Cmd + 스크롤은 확대/축소.
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor = 1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            let p = contentView.convert(event.locationInWindow, from: nil)
            setMagnification(max(minMagnification, min(maxMagnification, magnification * factor)), centeredAt: p)
            return
        }
        super.scrollWheel(with: event)
    }

    /// 화면 중앙의 캔버스 좌표.
    var visibleCenter: Point {
        let r = contentView.bounds
        return CanvasGeometry.modelPoint(NSPoint(x: r.midX, y: r.midY))
    }

    func center(on p: Point, zoom: CGFloat? = nil) {
        if let zoom { magnification = max(minMagnification, min(maxMagnification, zoom)) }
        let vp = CanvasGeometry.viewPoint(p)
        let size = contentView.bounds.size
        contentView.scroll(to: NSPoint(x: vp.x - size.width / 2, y: vp.y - size.height / 2))
        reflectScrolledClipView(contentView)
    }

    func zoom(by factor: CGFloat) {
        let r = contentView.bounds
        setMagnification(max(minMagnification, min(maxMagnification, magnification * factor)),
                         centeredAt: NSPoint(x: r.midX, y: r.midY))
    }
}

/// 작업공간 하나의 문서 뷰. 노드 뷰와 펜 획을 담는다.
final class CanvasView: NSView {
    let workspaceID: UUID
    unowned let model: AppModel
    var tool: BoardTool = .select {
        didSet {
            window?.invalidateCursorRects(for: self)
            if case .place = tool {} else { hoverPoint = nil }
            needsDisplay = true
        }
    }
    weak var controller: MainWindowController?
    /// 놓기 도구일 때 마우스 위치(뷰 좌표). 점선 자리표시를 그린다.
    private var hoverPoint: NSPoint?
    private(set) var nodeViews: [UUID: NodeView] = [:]
    private(set) var groupViews: [UUID: GroupFrameView] = [:]
    private lazy var linksView: LinksView = {
        let v = LinksView(frame: bounds)
        addSubview(v, positioned: .below, relativeTo: nil)
        return v
    }()
    private var panStart: (NSPoint, NSPoint)?
    private var currentStroke: [Point]?
    var penColor = "#FF3B30"
    var onSelect: ((UUID?) -> Void)?
    private(set) var selectedNodeID: UUID?

    init(workspaceID: UUID, model: AppModel) {
        self.workspaceID = workspaceID
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: CanvasGeometry.size, height: CanvasGeometry.size))
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        reloadNodes()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var workspace: Workspace? { model.workspace(workspaceID) }

    /// 모델과 노드 뷰를 맞춘다. 새로 생긴 노드는 뷰를 만들고, 사라진 노드는 뷰를 뗀다.
    func reloadNodes() {
        guard let ws = workspace else { return }
        let ids = Set(ws.nodes.map(\.id))
        for (id, v) in nodeViews where !ids.contains(id) {
            v.removeFromSuperview()
            nodeViews[id] = nil
        }
        for node in ws.nodes where nodeViews[node.id] == nil {
            let v = NodeView.make(node: node, model: model)
            v.canvas = self
            addSubview(v)
            nodeViews[node.id] = v
        }
        for node in ws.nodes { nodeViews[node.id]?.syncFromModel() }
        applyOrder(ws)
        layoutGroups()
        needsDisplay = true
    }

    // MARK: 그룹 프레임·연결선

    /// 팀마다 멤버 노드를 감싸는 프레임을 맞추고 연결선을 다시 그린다.
    func layoutGroups() {
        guard let ws = workspace else { return }
        var live: Set<UUID> = []
        for team in ws.teams {
            let members = ws.nodes.filter { $0.teamID == team.id }
            guard !members.isEmpty else { continue }
            live.insert(team.id)
            let v: GroupFrameView
            if let existing = groupViews[team.id] { v = existing } else {
                v = GroupFrameView(team: team)
                v.canvas = self
                addSubview(v, positioned: .above, relativeTo: linksView)
                groupViews[team.id] = v
            }
            v.team = team
            v.memberCount = members.count
            let statuses = members.compactMap { model.sessions.status(of: $0.id) }
            let running = statuses.filter { $0 == .working }.count
            let waiting = statuses.filter { $0 == .waiting }.count
            v.summary = running > 0 ? "\(running) running" : (waiting > 0 ? "\(waiting) need you" : "idle")
            var box = NSRect.null
            for m in members {
                let r = nodeViews[m.id]?.frame ?? CanvasGeometry.viewRect(m.frame)
                box = box.union(r)
                nodeViews[m.id]?.isHidden = v.collapsed
            }
            let pad = GroupFrameView.pad, head = GroupFrameView.headerHeight
            let target = v.collapsed
                ? NSRect(x: box.minX - pad, y: box.minY - pad - head, width: 320, height: head + 52)
                : NSRect(x: box.minX - pad, y: box.minY - pad - head, width: box.width + pad * 2, height: box.height + pad * 2 + head)
            if v.frame != target { v.frame = target }
            v.needsDisplay = true
        }
        for (id, v) in groupViews where !live.contains(id) {
            v.removeFromSuperview()
            groupViews[id] = nil
        }
        // 팀이 없어진 노드는 다시 보이게.
        for n in ws.nodes where n.teamID == nil || !live.contains(n.teamID!) { nodeViews[n.id]?.isHidden = false }
        layoutLinks()
    }

    /// 연결선 끝점: 노드면 노드 사각형, 팀이면 그룹 프레임 몸통.
    func layoutLinks() {
        guard let ws = workspace else { return }
        func rect(_ id: UUID) -> NSRect? {
            if let g = groupViews[id] { return g.collapsed ? g.frame : g.bodyRect }
            guard let v = nodeViews[id], !v.isHidden else { return nil }
            return v.frame
        }
        let segs = (ws.links ?? []).compactMap { l -> (UUID, NSRect, NSRect)? in
            guard let a = rect(l.from), let b = rect(l.to) else { return nil }
            return (l.id, a, b)
        }
        if segs.isEmpty && linksView.layer?.sublayers?.isEmpty ?? true { return }
        linksView.update(segs)
    }

    func setGroup(_ teamID: UUID, collapsed: Bool) {
        model.mutateWorkspace(workspaceID) { ws in
            if let i = ws.teams.firstIndex(where: { $0.id == teamID }) { ws.teams[i].collapsed = collapsed }
        }
        layoutGroups()
    }

    /// 모델 배열 순서대로 겹침 순서를 맞춘다(뒤에 있을수록 위).
    private func applyOrder(_ ws: Workspace) {
        var rank: [ObjectIdentifier: Int] = [:]
        for (i, n) in ws.nodes.enumerated() { if let v = nodeViews[n.id] { rank[ObjectIdentifier(v)] = i } }
        let current = subviews.compactMap { rank[ObjectIdentifier($0)] }
        guard current != current.sorted() else { return }
        let box = Unmanaged.passRetained(RankBox(rank))
        sortSubviews({ a, b, ctx in
            let r = Unmanaged<RankBox>.fromOpaque(ctx!).takeUnretainedValue().rank
            let ra = r[ObjectIdentifier(a)] ?? -1, rb = r[ObjectIdentifier(b)] ?? -1
            return ra < rb ? .orderedAscending : (ra > rb ? .orderedDescending : .orderedSame)
        }, context: box.toOpaque())
        box.release()
    }

    func bringToFront(_ v: NodeView) {
        guard subviews.last !== v else { return }
        // 터미널 뷰가 창에서 떨어지지 않도록 removeFromSuperview 대신 순서만 바꾼다.
        sortSubviews({ a, b, ctx in
            let front = Unmanaged<NSView>.fromOpaque(ctx!).takeUnretainedValue()
            if a === front { return .orderedDescending }
            if b === front { return .orderedAscending }
            return .orderedSame
        }, context: Unmanaged.passUnretained(v).toOpaque())
    }

    func select(_ id: UUID?) {
        // 오케스트레이터 Connect 중에 콘솔을 누르면 선택 대신 연결/해제.
        if let id, let orch = controller?.chrome.connectingOrchestrator, id != orch, model.node(id)?.kind == .terminal {
            controller?.toggleWire(orch, to: id)
            return
        }
        selectedNodeID = id
        for (nid, v) in nodeViews { v.isSelected = nid == id }
        // 글자·스티키·이미지는 레이어 순서를 지킨다. 콘솔 같은 창형 노드만 누르면 앞으로 온다.
        if let id, let v = nodeViews[id], !v.headerless { bringToFront(v) }
        onSelect?(id)
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvas.setFill()
        dirtyRect.fill()
        // 점 격자. 너무 작게 축소되면 그리지 않는다.
        let mag = enclosingScrollView?.magnification ?? 1
        if mag > 0.25 {
            let step: CGFloat = 36
            Theme.dot.setFill()
            var x = floor(dirtyRect.minX / step) * step
            while x < dirtyRect.maxX {
                var y = floor(dirtyRect.minY / step) * step
                while y < dirtyRect.maxY {
                    NSRect(x: x - 1, y: y - 1, width: 2, height: 2).fill()
                    y += step
                }
                x += step
            }
        }
        guard let ws = workspace else { return }
        for s in ws.strokes { Self.draw(stroke: s, offset: CanvasGeometry.origin) }
        if let cur = currentStroke {
            Self.draw(stroke: Stroke(points: cur, colorHex: penColor), offset: CanvasGeometry.origin)
        }
        if case .place(let p) = tool, let h = hoverPoint {
            let s = p.size
            let r = NSRect(x: h.x - s.width / 2, y: h.y - 20, width: s.width, height: s.height)
            let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
            path.lineWidth = 1.5 / max(mag, 0.2)
            path.setLineDash([6 / max(mag, 0.2), 5 / max(mag, 0.2)], count: 2, phase: 0)
            Theme.accent.withAlphaComponent(0.08).setFill()
            path.fill()
            Theme.accent.withAlphaComponent(0.8).setStroke()
            path.stroke()
            if case .agent(let id) = p, let choice = AgentCatalog.choice(id: id) {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                            .foregroundColor: NSColor(hex: choice.colorHex)]
                let str = NSAttributedString(string: choice.name, attributes: attrs)
                let sz = str.size()
                str.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard case .place = tool else { return }
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    /// 지우개: 누른 자리 가까이 지나는 보드 획을 지운다.
    private func erase(at p: Point) {
        guard let ws = workspace else { return }
        let r = 10 / max(enclosingScrollView?.magnification ?? 1, 0.2)
        let hit = ws.strokes.lastIndex { s in s.points.contains { hypot($0.x - p.x, $0.y - p.y) < r + s.width } }
        guard let i = hit else { return }
        model.mutateWorkspace(workspaceID) { $0.strokes.remove(at: i) }
        needsDisplay = true
    }

    static func draw(stroke: Stroke, offset: CGFloat) {
        guard let first = stroke.points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: first.x + offset, y: first.y + offset))
        for p in stroke.points.dropFirst() { path.line(to: NSPoint(x: p.x + offset, y: p.y + offset)) }
        if stroke.points.count == 1 { path.line(to: NSPoint(x: first.x + offset + 0.1, y: first.y + offset)) }
        NSColor(hex: stroke.colorHex).setStroke()
        path.stroke()
    }

    // MARK: 마우스: 빈 곳을 끌면 이동, 펜 도구면 그리기

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        select(nil)
        let p = convert(event.locationInWindow, from: nil)
        if case .place(let placement) = tool {
            controller?.place(placement, at: CanvasGeometry.modelPoint(p))
            return
        }
        if tool == .eraser {
            erase(at: CanvasGeometry.modelPoint(p))
            return
        }
        if tool == .pen {
            currentStroke = [CanvasGeometry.modelPoint(p)]
            return
        }
        if event.clickCount == 2 {
            NotificationCenter.default.post(name: .canvasDoubleClick, object: self, userInfo: ["point": CanvasGeometry.modelPoint(p)])
            return
        }
        guard let clip = enclosingScrollView?.contentView else { return }
        panStart = (event.locationInWindow, clip.bounds.origin)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        if tool == .eraser {
            erase(at: CanvasGeometry.modelPoint(convert(event.locationInWindow, from: nil)))
            return
        }
        if tool == .pen, currentStroke != nil {
            currentStroke?.append(CanvasGeometry.modelPoint(convert(event.locationInWindow, from: nil)))
            needsDisplay = true
            return
        }
        guard let (startWin, startOrigin) = panStart, let sv = enclosingScrollView else { return }
        let mag = sv.magnification
        let dx = (event.locationInWindow.x - startWin.x) / mag
        let dy = (event.locationInWindow.y - startWin.y) / mag
        sv.contentView.scroll(to: NSPoint(x: startOrigin.x - dx, y: startOrigin.y + dy))
        sv.reflectScrolledClipView(sv.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if let pts = currentStroke {
            currentStroke = nil
            if pts.count > 0 {
                let s = Stroke(points: pts, colorHex: penColor)
                model.mutateWorkspace(workspaceID) { $0.strokes.append(s) }
            }
            needsDisplay = true
            return
        }
        if panStart != nil {
            panStart = nil
            NSCursor.pop()
        }
    }

    override func resetCursorRects() {
        switch tool {
        case .pen, .place, .eraser: addCursorRect(visibleRect, cursor: .crosshair)
        case .select: break
        }
    }

    // MARK: 이미지 끌어다 놓기

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        var p = CanvasGeometry.modelPoint(convert(sender.draggingLocation, from: nil))
        for url in urls {
            let size = NSImage(contentsOf: url)?.size ?? CGSize(width: 400, height: 300)
            let scale = min(1, 520 / max(size.width, 1))
            let node = BoardNode(kind: .image, frame: Rect(x: p.x, y: p.y, w: size.width * scale, h: size.height * scale),
                                 title: url.lastPathComponent, text: url.path, strokes: [])
            model.addNode(node, to: workspaceID)
            p.x += 30; p.y += 30
        }
        return true
    }

    private func imageURLs(from info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: ["public.image"]]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
    }
}

private final class RankBox {
    let rank: [ObjectIdentifier: Int]
    init(_ r: [ObjectIdentifier: Int]) { rank = r }
}

extension Notification.Name {
    static let canvasDoubleClick = Notification.Name("symboard.canvasDoubleClick")
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 8 {
            self.init(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                      blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
        } else {
            self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                      blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }
}
