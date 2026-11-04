import AppKit

/// 노드 뒤로 잔잔하게 퍼지는 주황 파동. 맡긴 콘솔의 끝 알림을 받은 lead 콘솔에 치고(WorkerReporter),
/// 사용자가 그 콘솔을 볼 때(누르기·포커스·입력)까지 계속 퍼진다.
/// 노드보다 뒤 층에 두고 클릭은 받지 않는다. 노드를 옮기거나 크기를 바꾸면 따라간다.
@MainActor
final class NodeRippleView: NSView {
    static let color = NSColor(hex: "#F39C3C")
    /// 노드 가장자리에서 파동이 퍼지는 거리.
    static let spread: CGFloat = 44
    static let rings = 3
    static let ringDuration: CFTimeInterval = 2.4
    /// 링 사이 간격. 링 하나의 길이를 링 수로 나눠 끊김 없이 이어지게 한다.
    static var ringGap: CFTimeInterval { ringDuration / Double(rings) }

    private weak var node: NSView?
    /// 파동을 켠 시각.
    let startedAt = Date()
    private var cornerRadius: CGFloat = 12
    private var frameObserver: NSObjectProtocol?

    init(behind node: NSView, cornerRadius: CGFloat) {
        self.node = node
        self.cornerRadius = cornerRadius
        super.init(frame: node.frame.insetBy(dx: -Self.spread, dy: -Self.spread))
        wantsLayer = true
        node.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: node, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 노드 자리·크기에 맞춰 링을 다시 깐다.
    private func follow() {
        guard let node else { return }
        isHidden = node.isHidden
        let f = node.frame.insetBy(dx: -Self.spread, dy: -Self.spread)
        guard f != frame else { return }
        frame = f
        start()
    }

    func start() {
        guard let root = layer, let node else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let s = Self.spread, r = cornerRadius
        let inner = CGRect(x: s, y: s, width: node.frame.width, height: node.frame.height)
        let outer = inner.insetBy(dx: -s, dy: -s)
        let from = CGPath(roundedRect: inner, cornerWidth: r, cornerHeight: r, transform: nil)
        let to = CGPath(roundedRect: outer, cornerWidth: r + s, cornerHeight: r + s, transform: nil)

        // 동작 줄이기가 켜져 있으면 움직이지 않는 테두리 하나만 둔다.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let mid = inner.insetBy(dx: -s / 3, dy: -s / 3)
            let ring = makeRing(CGPath(roundedRect: mid, cornerWidth: r + s / 3, cornerHeight: r + s / 3, transform: nil))
            ring.opacity = 0.5
            root.addSublayer(ring)
            return
        }

        let now = CACurrentMediaTime()
        for i in 0..<Self.rings {
            let ring = makeRing(from)
            ring.opacity = 0
            root.addSublayer(ring)

            let path = CABasicAnimation(keyPath: "path")
            path.fromValue = from
            path.toValue = to
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.6
            fade.toValue = 0
            let thin = CABasicAnimation(keyPath: "lineWidth")
            thin.fromValue = 2.5
            thin.toValue = 0.5
            let g = CAAnimationGroup()
            g.animations = [path, fade, thin]
            g.duration = Self.ringDuration
            g.beginTime = now + Double(i) * Self.ringGap
            g.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.35, 1)
            g.fillMode = .backwards
            g.repeatCount = .infinity
            g.isRemovedOnCompletion = false
            ring.add(g, forKey: "symRipple")
        }
    }

    private func makeRing(_ path: CGPath) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.path = path
        ring.fillColor = Self.color.withAlphaComponent(0.05).cgColor
        ring.strokeColor = Self.color.cgColor
        ring.lineWidth = 2
        return ring
    }

    /// 살짝 옅어지며 사라진다.
    func stop() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
    }
}

extension CanvasView {
    /// id 노드 뒤에 주황 파동을 켠다. 이미 치고 있으면 그대로 둔다. 이 캔버스에 없는 노드면 아무것도 하지 않는다.
    func startRipple(_ id: UUID) {
        guard ripples[id] == nil, let v = nodeViews[id] else { return }
        let r = NodeRippleView(behind: v, cornerRadius: v.layer?.cornerRadius ?? 12)
        addSubview(r, positioned: .below, relativeTo: nil)
        r.isHidden = v.isHidden
        r.start()
        ripples[id] = r
    }

    /// id 노드의 파동을 끈다(사용자가 그 노드를 봤을 때).
    func stopRipple(_ id: UUID) {
        guard let r = ripples.removeValue(forKey: id) else { return }
        r.stop()
    }

    /// 파동을 켠 뒤 사용자가 그 콘솔에 글자를 쳤으면 본 것으로 치고 끈다(이미 골라져 있어 누를 일이 없을 때).
    func stopRipplesTypedInto(lastUserKey: (UUID) -> Date?) {
        for (id, r) in ripples {
            if let key = lastUserKey(id), key > r.startedAt { stopRipple(id) }
        }
    }
}
