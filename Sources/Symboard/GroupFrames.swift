import AppKit
import QuartzCore
import SymboardCore

/// 팀(그룹)에 속한 노드들을 감싸는 둥근 프레임. 머리를 끌면 노드가 함께 움직이고, 꺾쇠로 접는다.
/// 머리 밖의 몸통은 클릭을 받지 않아 보드 이동이 그대로 된다.
final class GroupFrameView: NSView {
    static let headerHeight: CGFloat = 30
    static let pad: CGFloat = 14

    let teamID: UUID
    weak var canvas: CanvasView?
    var team: Team
    var memberCount = 0
    var summary = ""
    private var dragStart: (NSPoint, [UUID: NSPoint])?
    private var moved = false
    private var headerWidth: CGFloat = 200
    /// 오케스트레이터 Connect 중일 때 테두리 위 알약. 원본 board 장면의 "Click to wire group" / "Group wired".
    enum WireState { case none, offer, wired }
    var wireState: WireState = .none {
        didSet {
            guard wireState != oldValue else { return }
            pill.state = wireState
            pill.isHidden = wireState == .none
            needsLayout = true
            needsDisplay = true
        }
    }
    private let pill = WirePillView()

    init(team: Team) {
        self.teamID = team.id
        self.team = team
        super.init(frame: .zero)
        wantsLayer = true
        pill.isHidden = true
        pill.onClick = { [weak self] in
            guard let self, let c = self.canvas?.controller, let orch = c.chrome.connectingOrchestrator else { return }
            c.toggleWire(orch, to: self.teamID)
        }
        addSubview(pill)
    }

    override func layout() {
        super.layout()
        let sz = pill.intrinsicContentSize
        pill.frame = NSRect(x: round((bounds.width - sz.width) / 2), y: Self.headerHeight - sz.height / 2, width: sz.width, height: sz.height)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var collapsed: Bool { team.collapsed ?? false }

    /// 프레임 몸통(머리 아래)의 사각형. 연결선이 여기에 붙는다.
    var bodyRect: NSRect { NSRect(x: frame.minX, y: frame.minY + Self.headerHeight, width: frame.width, height: frame.height - Self.headerHeight) }

    private var titleAttr: NSAttributedString {
        let s = NSMutableAttributedString(string: team.name.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold), .kern: 1.0, .foregroundColor: Theme.text])
        s.append(NSAttributedString(string: "   \(memberCount)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.textDim]))
        s.append(NSAttributedString(string: "  ·  \(summary)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: Theme.textDim]))
        return s
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(hex: team.colorHex)
        let body = NSRect(x: 0.5, y: Self.headerHeight, width: bounds.width - 1, height: bounds.height - Self.headerHeight - 0.5)
        let path = NSBezierPath(roundedRect: body, xRadius: 16, yRadius: 16)
        color.withAlphaComponent(0.035).setFill()
        path.fill()
        switch wireState {
        case .none:
            color.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 1
        case .offer:
            Theme.accent.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([5, 4], count: 2, phase: 0)
        case .wired:
            Theme.accent.setStroke()
            path.lineWidth = 1.5
        }
        path.stroke()

        let dot = NSRect(x: 8, y: Self.headerHeight / 2 - 4, width: 8, height: 8)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        let t = titleAttr
        let sz = t.size()
        t.draw(at: NSPoint(x: 24, y: (Self.headerHeight - sz.height) / 2))
        let chevX = 24 + sz.width + 10
        headerWidth = chevX + 18
        if let img = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            let tinted = img.tinted(Theme.textDim)
            tinted.draw(in: NSRect(x: chevX, y: Self.headerHeight / 2 - 5, width: 10, height: 10))
        }
        if collapsed {
            let s = NSAttributedString(string: "\(memberCount) hidden · click the arrow to open", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.textDim])
            s.draw(at: NSPoint(x: 18, y: Self.headerHeight + 16))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let p = convert(point, from: sv)
        guard bounds.contains(p) else { return nil }
        if !pill.isHidden, pill.frame.contains(p) { return pill }
        if p.y <= Self.headerHeight && p.x <= headerWidth + 8 { return self }
        // 접힌 프레임은 몸통 전체를 머리처럼 다룬다.
        if collapsed { return self }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let canvas else { return }
        let p = convert(event.locationInWindow, from: nil)
        if p.x >= headerWidth - 20 && p.x <= headerWidth + 8 && p.y <= Self.headerHeight {
            canvas.setGroup(teamID, collapsed: !collapsed)
            return
        }
        if event.clickCount == 2 {
            canvas.controller?.renameTeam(teamID)
            return
        }
        var origins: [UUID: NSPoint] = [:]
        for (id, v) in canvas.nodeViews where canvas.model.node(id)?.teamID == teamID { origins[id] = v.frame.origin }
        origins[teamID] = frame.origin
        moved = false
        dragStart = (canvas.convert(event.locationInWindow, from: nil), origins)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let (start, origins) = dragStart else { return }
        let p = canvas.convert(event.locationInWindow, from: nil)
        let dx = round(p.x - start.x), dy = round(p.y - start.y)
        moved = true
        for (id, o) in origins {
            if id == teamID { setFrameOrigin(NSPoint(x: o.x + dx, y: o.y + dy)) }
            else { canvas.nodeViews[id]?.setFrameOrigin(NSPoint(x: o.x + dx, y: o.y + dy)) }
        }
        canvas.layoutLinks()
    }

    override func mouseUp(with event: NSEvent) {
        guard let canvas, let (_, origins) = dragStart else { return }
        dragStart = nil
        if moved {
            for id in origins.keys where id != teamID { canvas.nodeViews[id]?.commitFrame() }
            canvas.layoutGroups()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let canvas, let c = canvas.controller else { return }
        let m = NSMenu()
        m.addItem(ClosureMenuItem(title: L("Rename Group...")) { c.renameTeam(self.teamID) })
        m.addItem(ClosureMenuItem(title: collapsed ? "Expand" : "Collapse") { canvas.setGroup(self.teamID, collapsed: !self.collapsed) })
        m.addItem(ClosureMenuItem(title: L("Ungroup")) { c.ungroup(self.teamID) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(title: Ln(memberCount, "Close %d Console...", "Close %d Consoles...")) { c.closeTeam(self.teamID) })
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: headerWidth, height: Self.headerHeight), cursor: .openHand)
    }
}

/// 노드·그룹 사이 곡선 연결선. 선 위로 점이 흐른다. 클릭은 받지 않는다.
final class LinksView: NSView {
    var isArrowLayer = false
    private var layers: [UUID: (CAShapeLayer, CALayer, CGPath)] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 두 사각형의 마주 보는 변 가운데를 잇는 곡선.
    static func path(from a: NSRect, to b: NSRect) -> CGPath {
        let p = CGMutablePath()
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        if abs(dx) >= abs(dy) {
            let s = CGPoint(x: dx >= 0 ? a.maxX : a.minX, y: a.midY)
            let e = CGPoint(x: dx >= 0 ? b.minX : b.maxX, y: b.midY)
            let k = max(abs(e.x - s.x) * 0.5, 40) * (dx >= 0 ? 1 : -1)
            p.move(to: s)
            p.addCurve(to: e, control1: CGPoint(x: s.x + k, y: s.y), control2: CGPoint(x: e.x - k, y: e.y))
        } else {
            let s = CGPoint(x: a.midX, y: dy >= 0 ? a.maxY : a.minY)
            let e = CGPoint(x: b.midX, y: dy >= 0 ? b.minY : b.maxY)
            let k = max(abs(e.y - s.y) * 0.5, 40) * (dy >= 0 ? 1 : -1)
            p.move(to: s)
            p.addCurve(to: e, control1: CGPoint(x: s.x, y: s.y + k), control2: CGPoint(x: e.x, y: e.y - k))
        }
        return p
    }

    /// 다이어그램 화살표: 두 사각형 가운데를 잇는 직선이 각 테두리와 만나는 점 사이.
    static func arrowPath(from a: NSRect, to b: NSRect) -> (CGPath, CGPoint) {
        func clip(_ r: NSRect, toward p: CGPoint) -> CGPoint {
            let c = CGPoint(x: r.midX, y: r.midY)
            let dx = p.x - c.x, dy = p.y - c.y
            guard dx != 0 || dy != 0 else { return c }
            let sx = dx == 0 ? .infinity : (r.width / 2 + 6) / abs(dx)
            let sy = dy == 0 ? .infinity : (r.height / 2 + 6) / abs(dy)
            let s = min(sx, sy)
            return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
        }
        let s = clip(a, toward: CGPoint(x: b.midX, y: b.midY))
        let e = clip(b, toward: CGPoint(x: a.midX, y: a.midY))
        let p = CGMutablePath()
        let mid = CGPoint(x: (s.x + e.x) / 2 + (e.y - s.y) * 0.03, y: (s.y + e.y) / 2 - (e.x - s.x) * 0.03)
        p.move(to: s)
        p.addQuadCurve(to: e, control: mid)
        let ang = atan2(e.y - mid.y, e.x - mid.x)
        for d in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            p.move(to: e)
            p.addLine(to: CGPoint(x: e.x + 14 * cos(ang + d), y: e.y + 14 * sin(ang + d)))
        }
        return (p, mid)
    }

    private var arrows: [UUID: (CAShapeLayer, CATextLayer?)] = [:]

    func updateArrows(_ segments: [(UUID, NSRect, NSRect, String?, String)]) {
        guard let root = layer else { return }
        let ids = Set(segments.map(\.0))
        for (id, l) in arrows where !ids.contains(id) { l.0.removeFromSuperlayer(); l.1?.removeFromSuperlayer(); arrows[id] = nil }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (id, a, b, label, color) in segments {
            let (path, mid) = Self.arrowPath(from: a, to: b)
            let shape = arrows[id]?.0 ?? CAShapeLayer()
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = Theme.resolved(Theme.ink(color) ?? Theme.text).cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            shape.lineJoin = .round
            if shape.superlayer == nil { root.addSublayer(shape) }
            var text = arrows[id]?.1
            if let label, !label.isEmpty {
                let t = text ?? CATextLayer()
                // 층 글자는 동적 색을 그릴 때 다시 풀지 않으므로 지금 모드의 색으로 고정해 넣는다(모드가 바뀌면 다시 불린다).
                t.string = NSAttributedString(string: label, attributes: [.font: Theme.handwriting(size: 15), .foregroundColor: Theme.resolved(Theme.text)])
                t.contentsScale = 2
                let size = (label as NSString).size(withAttributes: [.font: Theme.handwriting(size: 15)])
                t.frame = CGRect(x: mid.x + 8, y: mid.y - size.height / 2, width: size.width + 4, height: size.height + 2)
                if t.superlayer == nil { root.addSublayer(t) }
                text = t
            }
            arrows[id] = (shape, text)
        }
        CATransaction.commit()
    }

    /// faint: 에이전트가 띄운 콘솔과 부른 콘솔 사이 선(8차 3번). 모양은 같고 색만 옅다.
    func update(_ segments: [(UUID, NSRect, NSRect)], faint: Set<UUID> = []) {
        guard let root = layer else { return }
        let ids = Set(segments.map(\.0))
        for (id, l) in layers where !ids.contains(id) {
            l.0.removeFromSuperlayer(); l.1.removeFromSuperlayer()
            layers[id] = nil
        }
        for (id, a, b) in segments {
            let path = Self.path(from: a, to: b)
            if let cur = layers[id], cur.2 == path { continue }
            let shape = layers[id]?.0 ?? CAShapeLayer()
            let dot = layers[id]?.1 ?? CALayer()
            shape.path = path
            shape.fillColor = nil
            let light = faint.contains(id)
            shape.strokeColor = Theme.accent.withAlphaComponent(light ? 0.22 : 0.55).cgColor
            shape.lineWidth = 1.5
            dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
            dot.cornerRadius = 3.5
            dot.backgroundColor = Theme.accent.withAlphaComponent(light ? 0.45 : 1).cgColor
            dot.shadowColor = Theme.accent.cgColor
            dot.shadowOpacity = 0.9
            dot.shadowRadius = 4
            dot.shadowOffset = .zero
            if shape.superlayer == nil { root.addSublayer(shape); root.addSublayer(dot) }
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.path = path
            anim.calculationMode = .paced
            let len = hypot(b.midX - a.midX, b.midY - a.midY)
            anim.duration = max(1.6, Double(len) / 140)
            anim.repeatCount = .infinity
            dot.removeAnimation(forKey: "flow")
            dot.add(anim, forKey: "flow")
            layers[id] = (shape, dot, path)
        }
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        img.unlockFocus()
        return img
    }
}

/// 그룹 테두리 위에 뜨는 작은 알약. offer 는 테두리색 글자의 어두운 알약, wired 는 강조색으로 채운 알약.
final class WirePillView: NSView {
    var state: GroupFrameView.WireState = .offer { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(title) } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    var title: String { state == .wired ? "Group wired" : "Click to wire group" }

    private var attr: NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: state == .wired ? NSColor.white : Theme.accent])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(attr.size().width) + 40, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        if state == .wired {
            Theme.accent.setFill(); path.fill()
        } else {
            Theme.canvas.setFill(); path.fill()
            Theme.accent.withAlphaComponent(0.6).setStroke(); path.lineWidth = 1; path.stroke()
        }
        let icon = NSImage(systemSymbolName: state == .wired ? "link" : "plus.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))?.tinted(state == .wired ? .white : Theme.accent)
        icon?.draw(in: NSRect(x: 9, y: 5, width: 12, height: 12))
        let a = attr
        a.draw(at: NSPoint(x: 27, y: (bounds.height - a.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
