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

enum BoardTool {
    case select
    case pen
}

/// 이동·확대/축소가 되는 보드. 확대/축소는 NSScrollView 의 magnification 을 쓴다.
final class BoardScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMagnification = true
        minMagnification = CanvasGeometry.minZoom
        maxMagnification = CanvasGeometry.maxZoom
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        drawsBackground = true
        backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
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
    var tool: BoardTool = .select { didSet { window?.invalidateCursorRects(for: self) } }
    private(set) var nodeViews: [UUID: NodeView] = [:]
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
        needsDisplay = true
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
        selectedNodeID = id
        for (nid, v) in nodeViews { v.isSelected = nid == id }
        if let id, let v = nodeViews[id] { bringToFront(v) }
        onSelect?(id)
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        dirtyRect.fill()
        // 점 격자. 너무 작게 축소되면 그리지 않는다.
        let mag = enclosingScrollView?.magnification ?? 1
        if mag > 0.25 {
            let step: CGFloat = 40
            NSColor(calibratedWhite: 0.24, alpha: 1).setFill()
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
        if tool == .pen { addCursorRect(visibleRect, cursor: .crosshair) }
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
            let node = BoardNode(kind: .image, frame: Rect(x: p.x, y: p.y, w: size.width * scale, h: size.height * scale + NodeView.headerHeight),
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
