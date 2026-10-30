import AppKit
import SymboardCore

/// 끌어다 놓은 이미지 노드. 보드의 펜 도구가 켜져 있으면 이미지 위에 표시를 그린다.
/// 획 좌표는 이미지 영역 기준 0~1 로 저장해서 노드 크기를 바꿔도 같은 자리에 남는다.
final class ImageContent: NodeContent {
    let nodeID: UUID
    unowned let model: AppModel
    let markup: ImageMarkupView
    var view: NSView { markup }

    init(node: BoardNode, model: AppModel) {
        nodeID = node.id
        self.model = model
        markup = ImageMarkupView()
        markup.image = node.text.flatMap { NSImage(contentsOfFile: $0) }
        markup.strokes = node.strokes ?? []
        markup.onStroke = { [weak self] s in
            guard let self else { return }
            self.model.mutateNode(self.nodeID) { $0.strokes = ($0.strokes ?? []) + [s] }
        }
    }

    func sync(node: BoardNode) {
        if markup.strokes != (node.strokes ?? []) {
            markup.strokes = node.strokes ?? []
            markup.needsDisplay = true
        }
    }

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: L("Clear Markup")) { [weak self] in
            guard let self else { return }
            self.model.mutateNode(self.nodeID) { $0.strokes = [] }
            self.markup.strokes = []
            self.markup.needsDisplay = true
        }]
    }
}

final class ImageMarkupView: NSView {
    var image: NSImage?
    var strokes: [Stroke] = []
    var onStroke: ((Stroke) -> Void)?
    private var current: [Point]?

    override var isFlipped: Bool { true }

    private var penOn: Bool {
        var v: NSView? = superview
        while let cur = v, !(cur is CanvasView) { v = cur.superview }
        return (v as? CanvasView)?.tool == .pen
    }

    /// 이미지가 실제로 그려지는 사각형(비율 유지).
    var imageRect: NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return bounds }
        let s = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        bounds.fill()
        let r = imageRect
        if let image {
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            let s = NSAttributedString(string: "Image not found", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            s.draw(at: NSPoint(x: 10, y: 10))
        }
        for s in strokes { draw(s, in: r) }
        if let cur = current { draw(Stroke(points: cur), in: r) }
    }

    private func draw(_ s: Stroke, in r: NSRect) {
        guard let first = s.points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = s.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        func p(_ q: Point) -> NSPoint { NSPoint(x: r.minX + q.x * r.width, y: r.minY + q.y * r.height) }
        path.move(to: p(first))
        for q in s.points.dropFirst() { path.line(to: p(q)) }
        if s.points.count == 1 { path.line(to: NSPoint(x: p(first).x + 0.1, y: p(first).y)) }
        NSColor(hex: s.colorHex).setStroke()
        path.stroke()
    }

    private func normalized(_ event: NSEvent) -> Point {
        let r = imageRect
        let q = convert(event.locationInWindow, from: nil)
        return Point(x: Double((q.x - r.minX) / max(r.width, 1)), y: Double((q.y - r.minY) / max(r.height, 1)))
    }

    override func mouseDown(with event: NSEvent) {
        (superview as? NodeView)?.beginInteraction()
        guard penOn else { return }
        current = [normalized(event)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        current?.append(normalized(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let pts = current else { return }
        current = nil
        let s = Stroke(points: pts)
        strokes.append(s)
        onStroke?(s)
        needsDisplay = true
    }
}
