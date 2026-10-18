import AppKit
import SymboardCore

/// 노드 종류마다 다른 본문을 공급한다.
@MainActor
protocol NodeContent: AnyObject {
    var view: NSView { get }
    /// 모델이 바뀌었을 때 화면을 맞춘다.
    func sync(node: BoardNode)
    /// 헤더 메뉴에 넣을 항목.
    func menuItems() -> [NSMenuItem]
    /// 노드를 삭제할 때.
    func teardown()
}

extension NodeContent {
    func menuItems() -> [NSMenuItem] { [] }
    func teardown() {}
}

/// 캔버스 위 노드 하나: 헤더(끌어서 이동), 본문, 오른쪽 아래 크기 조절 손잡이.
final class NodeView: NSView {
    static let headerHeight: CGFloat = 28
    static let minSize = CGSize(width: 160, height: 90)

    let nodeID: UUID
    unowned let model: AppModel
    weak var canvas: CanvasView?
    let content: NodeContent
    let header = NodeHeaderView()
    private let resizeHandle = ResizeHandleView()
    /// 오케스트레이터 오른쪽 가장자리의 연결 손잡이. 끌어서 그룹·콘솔 위에 놓으면 연결하거나 끊는다.
    private let wirePort = WirePortView()

    var isSelected = false {
        didSet {
            updateBorder()
            if !isSelected && editing { setEditing(false) }
        }
    }

    /// 헤더 없이 본문만 보이는 노드(글자·스티키·이미지). 몸통을 끌어 옮기고 두 번 눌러 편집한다.
    let headerless: Bool
    private let shield = MoveShieldView()
    private(set) var editing = false

    static func isHeaderless(_ kind: NodeKind) -> Bool { [.text, .sticky, .image, .shape].contains(kind) }

    static func make(node: BoardNode, model: AppModel) -> NodeView {
        let content: NodeContent
        switch node.kind {
        case .terminal: content = TerminalNodeContent(node: node, model: model)
        default: content = NodeContentFactory.make(node: node, model: model)
        }
        return NodeView(node: node, model: model, content: content)
    }

    init(node: BoardNode, model: AppModel, content: NodeContent) {
        self.nodeID = node.id
        self.model = model
        self.content = content
        self.headerless = Self.isHeaderless(node.kind)
        super.init(frame: CanvasGeometry.viewRect(node.frame))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.backgroundColor = Theme.terminalBackground.cgColor

        addSubview(content.view)
        addSubview(header)
        if headerless {
            header.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 4
            shield.nodeView = self
            addSubview(shield)
        }
        addSubview(resizeHandle)
        if node.kind == .orchestrator {
            wirePort.nodeView = self
            addSubview(wirePort)
        }
        header.nodeView = self
        resizeHandle.nodeView = self
        header.closeButton.target = self
        header.closeButton.action = #selector(closeClicked)
        header.menuButton.target = self
        header.menuButton.action = #selector(menuClicked(_:))
        header.chevron.target = self
        header.chevron.action = #selector(menuClicked(_:))
        header.restartButton.target = self
        header.restartButton.action = #selector(restartClicked)
        header.duplicateButton.target = self
        header.duplicateButton.action = #selector(duplicateClicked)
        header.isTerminal = node.kind == .terminal
        header.kindIcon.image = NSImage(systemSymbolName: LayersList.symbol(node.kind), accessibilityDescription: nil)
        updateBorder()
        layoutParts()
        syncFromModel()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    private func layoutParts() {
        let b = bounds
        let top = headerless ? 0 : Self.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: b.width, height: Self.headerHeight)
        content.view.frame = NSRect(x: 0, y: top, width: b.width, height: max(0, b.height - top))
        shield.frame = b
        resizeHandle.frame = NSRect(x: b.width - 16, y: b.height - 16, width: 16, height: 16)
        wirePort.frame = NSRect(x: b.width - 18, y: b.midY - 9, width: 18, height: 18)
        header.needsLayout = true
    }

    func syncFromModel() {
        guard let node = model.node(nodeID) else { return }
        let target = CanvasGeometry.viewRect(node.frame)
        if frame != target { frame = target }
        header.titleLabel.stringValue = node.title
        header.roleLabel.stringValue = node.role ?? ""
        if let spec = node.terminal {
            header.glyph.choice = AgentCatalog.choice(for: spec)
            if let perm = PermissionMode.label(for: spec) {
                header.permBadge.set(text: perm, color: Theme.accent, filled: true)
                header.permBadge.isHidden = false
            } else { header.permBadge.isHidden = true }
            header.toolTip = "\(AgentCatalog.choice(for: spec).name) · \((spec.cwd as NSString).abbreviatingWithTildeInPath)"
        }
        header.needsLayout = true
        content.sync(node: node)
    }

    /// 마지막으로 받은 상태. 사용자 답을 기다리면 테두리로 눈에 띄게 한다.
    private var lastStatus: NodeStatus?

    func setStatus(_ status: NodeStatus?) {
        header.setStatus(status)
        if status != lastStatus {
            lastStatus = status
            updateBorder()
        }
    }

    private func updateBorder() {
        if headerless {
            layer?.borderColor = Theme.accent.cgColor
            layer?.borderWidth = isSelected ? 1.5 : 0
            resizeHandle.isHidden = !isSelected
            return
        }
        if lastStatus == .waiting {
            layer?.borderColor = NodeStatus.waiting.color.cgColor
            layer?.borderWidth = 2
            return
        }
        layer?.borderColor = (isSelected ? Theme.accent : Theme.nodeBorder).cgColor
        layer?.borderWidth = isSelected ? 1.5 : 1
    }

    // MARK: 동작

    @objc private func closeClicked() {
        if model.node(nodeID)?.kind == .terminal, model.sessions.session(for: nodeID)?.running == true {
            let alert = NSAlert()
            alert.messageText = "Close this terminal?"
            alert.informativeText = "The running process will be terminated."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        content.teardown()
        model.removeNode(nodeID)
    }

    @objc private func menuClicked(_ sender: NSButton) {
        let menu = NSMenu()
        for item in content.menuItems() { menu.addItem(item) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem(title: "Rename...") { [weak self] in self?.rename() })
        menu.addItem(ClosureMenuItem(title: "Set Role...") { [weak self] in self?.setRole() })
        if let ws = canvas?.workspace {
            let linkItem = NSMenuItem(title: "Link To", action: nil, keyEquivalent: "")
            let lsub = NSMenu()
            for t in ws.teams where ws.nodes.contains(where: { $0.teamID == t.id }) {
                lsub.addItem(ClosureMenuItem(title: "Group: \(t.name)") { [weak self] in self?.link(to: t.id) })
            }
            for n in ws.nodes where n.id != nodeID {
                lsub.addItem(ClosureMenuItem(title: n.title) { [weak self] in self?.link(to: n.id) })
            }
            if ws.links?.contains(where: { $0.from == nodeID || $0.to == nodeID }) == true {
                lsub.addItem(.separator())
                lsub.addItem(ClosureMenuItem(title: "Remove Links") { [weak self] in
                    guard let self else { return }
                    self.model.mutateWorkspace(ws.id) { $0.links?.removeAll { $0.from == self.nodeID || $0.to == self.nodeID } }
                    self.canvas?.layoutLinks()
                })
            }
            linkItem.submenu = lsub
            menu.addItem(linkItem)
            let teamItem = NSMenuItem(title: "Team", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(ClosureMenuItem(title: "None") { [weak self] in self?.assignTeam(nil) })
            for t in ws.teams { sub.addItem(ClosureMenuItem(title: t.name) { [weak self] in self?.assignTeam(t.id) }) }
            sub.addItem(.separator())
            sub.addItem(ClosureMenuItem(title: "New Team...") { [weak self] in self?.newTeam() })
            teamItem.submenu = sub
            menu.addItem(teamItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func restartClicked() {
        model.sessions.restart(nodeID)
    }

    @objc private func duplicateClicked() {
        canvas?.select(nodeID)
        canvas?.controller?.duplicateSelection()
    }

    func rename() {
        guard let node = model.node(nodeID) else { return }
        if let name = Prompt.text(title: "Rename node", value: node.title) {
            model.mutateNode(nodeID) { $0.title = name }
            syncFromModel()
        }
    }

    private func setRole() {
        let current = model.node(nodeID)?.role ?? ""
        if let role = Prompt.text(title: "Role name", message: "Leave empty to clear.", value: current) {
            model.mutateNode(nodeID) { $0.role = role.isEmpty ? nil : role }
            syncFromModel()
        }
    }

    func link(to target: UUID) {
        guard let ws = canvas?.workspace else { return }
        model.mutateWorkspace(ws.id) { w in
            if w.links?.contains(where: { $0.from == nodeID && $0.to == target }) == true { return }
            w.links = (w.links ?? []) + [NodeLink(from: nodeID, to: target)]
        }
        canvas?.layoutLinks()
    }

    private func newTeam() {
        guard let ws = canvas?.workspace,
              let name = Prompt.text(title: "New team", value: "Team \(ws.teams.count + 1)"), !name.isEmpty else { return }
        let team = Team(name: name, colorHex: Composer.teamColors[ws.teams.count % Composer.teamColors.count])
        model.mutateWorkspace(ws.id) { $0.teams.append(team) }
        assignTeam(team.id)
    }

    private func assignTeam(_ id: UUID?) {
        model.mutateNode(nodeID) { $0.teamID = id }
        syncFromModel()
        canvas?.layoutGroups()
    }

    /// 편집 중이면 가림막을 치우고 본문에 입력 초점을 준다.
    func setEditing(_ on: Bool) {
        guard headerless else { return }
        editing = on
        shield.isHidden = on
        if on {
            canvas?.select(nodeID)
            if let tv = Self.firstTextView(in: content.view) { window?.makeFirstResponder(tv) }
        } else if let w = window, let fr = w.firstResponder as? NSView, fr.isDescendant(of: self) {
            w.makeFirstResponder(canvas)
        }
    }

    private static func firstTextView(in v: NSView) -> NSView? {
        if v is NSTextView { return v }
        for s in v.subviews { if let t = firstTextView(in: s) { return t } }
        return nil
    }

    func beginInteraction() {
        canvas?.select(nodeID)
    }

    func commitFrame() {
        let r = CanvasGeometry.modelRect(frame)
        model.mutateNode(nodeID) { $0.frame = r }
    }

    override func mouseDown(with event: NSEvent) {
        beginInteraction()
        super.mouseDown(with: event)
    }
}

/// 노드 헤더. 왼쪽: CLI 글자 배지·꺾쇠(메뉴)·상태 점·이름, 오른쪽: 권한 배지·상태 알약·다시 시작·복제·닫기.
/// 끌면 노드가 움직이고, 이름을 두 번 누르면 이름을 바꾼다.
final class NodeHeaderView: NSView {
    weak var nodeView: NodeView?
    let glyph = GlyphView()
    let chevron = NSButton()
    let titleLabel = NSTextField(labelWithString: "")
    let roleLabel = NSTextField(labelWithString: "")
    let statusDot = NSView()
    let statusPill = PillLabel()
    let permBadge = PillLabel()
    let restartButton = NSButton()
    let duplicateButton = NSButton()
    let closeButton = NSButton()
    let menuButton = NSButton()
    let kindIcon = NSImageView()
    var isTerminal = false { didSet { applyKind() } }
    private var dragStart: (NSPoint, NSPoint)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingTail
        roleLabel.font = .systemFont(ofSize: 11)
        roleLabel.textColor = Theme.textDim
        roleLabel.lineBreakMode = .byTruncatingTail
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.isHidden = true
        statusPill.isHidden = true
        permBadge.isHidden = true
        permBadge.set(text: "AUTO", color: Theme.accent, filled: true)
        kindIcon.contentTintColor = Theme.textDim
        for (b, sym, tip) in [(closeButton, "xmark", "Close"), (menuButton, "ellipsis", "More"),
                              (restartButton, "arrow.clockwise", "Restart"), (duplicateButton, "plus.square.on.square", "Duplicate"),
                              (chevron, "chevron.down", "Menu")] {
            b.bezelStyle = .inline
            b.isBordered = false
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: b === chevron ? 8 : 11, weight: .semibold))
            b.contentTintColor = Theme.textDim
            b.toolTip = tip
        }
        [glyph, chevron, statusDot, titleLabel, roleLabel, permBadge, statusPill, restartButton, duplicateButton,
         closeButton, menuButton, kindIcon].forEach(addSubview)
        applyKind()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func applyKind() {
        glyph.isHidden = !isTerminal
        chevron.isHidden = !isTerminal
        restartButton.isHidden = !isTerminal
        duplicateButton.isHidden = !isTerminal
        menuButton.isHidden = isTerminal
        kindIcon.isHidden = isTerminal
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let mid = { (v: CGFloat) in (h - v) / 2 }
        var x: CGFloat = 8
        if isTerminal {
            glyph.frame = NSRect(x: x, y: mid(18), width: 18, height: 18)
            x += 19
            chevron.frame = NSRect(x: x, y: mid(16), width: 12, height: 16)
            x += 16
        } else {
            kindIcon.frame = NSRect(x: x + 2, y: mid(14), width: 14, height: 14)
            x += 22
        }
        if !statusDot.isHidden {
            statusDot.frame = NSRect(x: x, y: mid(7), width: 7, height: 7)
            x += 13
        }
        var right = bounds.width - 6
        for b in [closeButton, duplicateButton, restartButton, menuButton] where !b.isHidden {
            b.frame = NSRect(x: right - 22, y: mid(20), width: 22, height: 20)
            right -= 23
        }
        right -= 4
        for pill in [statusPill, permBadge] where !pill.isHidden {
            let w = pill.fittingWidth
            pill.frame = NSRect(x: right - w, y: mid(16), width: w, height: 16)
            right -= w + 6
        }
        titleLabel.sizeToFit()
        let tw = min(titleLabel.frame.width, max(10, right - x))
        titleLabel.frame = NSRect(x: x, y: mid(16), width: tw, height: 16)
        let rx = x + tw + 6
        roleLabel.frame = NSRect(x: rx, y: mid(15), width: max(0, right - rx), height: 15)
    }

    func setStatus(_ status: NodeStatus?) {
        guard let status else {
            statusDot.isHidden = true
            statusPill.isHidden = true
            needsLayout = true
            return
        }
        let paused = nodeView.flatMap { nv in nv.model.sessions.session(for: nv.nodeID)?.paused } ?? false
        let onHold = nodeView.map { $0.model.sessions.pendingResume.contains($0.nodeID) } ?? false
        let wasHidden = statusPill.isHidden
        statusDot.isHidden = false
        statusPill.isHidden = false
        statusDot.layer?.backgroundColor = ((paused || onHold) ? Theme.textDim : status.color).cgColor
        let text = onHold ? "ON HOLD" : (paused ? "PAUSED" : status.pillText)
        if statusPill.text != text || wasHidden {
            statusPill.set(text: text, color: (paused || onHold) ? Theme.textDim : status.color, filled: false)
            needsLayout = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let nv = nodeView else { return }
        nv.beginInteraction()
        if event.clickCount == 2 {
            dragStart = nil
            if titleLabel.frame.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { nv.rename() }
            return
        }
        dragStart = (nv.superview!.convert(event.locationInWindow, from: nil), nv.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let nv = nodeView, let (start, origin) = dragStart, let sv = nv.superview else { return }
        let p = sv.convert(event.locationInWindow, from: nil)
        nv.setFrameOrigin(NSPoint(x: round(origin.x + p.x - start.x), y: round(origin.y + p.y - start.y)))
        nv.canvas?.layoutGroups()
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { nodeView?.commitFrame() }
        dragStart = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

/// 모노 대문자 작은 알약(상태·권한 배지).
final class PillLabel: NSView {
    private(set) var text = ""
    private var color = Theme.textDim
    private var filled = false
    private static let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)

    var fittingWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Self.font, .kern: 0.8]).width) + (filled ? 12 : 22)
    }

    func set(text: String, color: NSColor, filled: Bool) {
        self.text = text; self.color = color; self.filled = filled
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        if filled {
            color.withAlphaComponent(0.9).setFill(); path.fill()
        } else {
            color.withAlphaComponent(0.10).setFill(); path.fill()
            color.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1; path.stroke()
            let dot = NSRect(x: 7, y: bounds.midY - 2.5, width: 5, height: 5)
            color.setFill(); NSBezierPath(ovalIn: dot).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .kern: 0.8, .foregroundColor: filled ? NSColor.white : color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: filled ? (bounds.width - sz.width) / 2 : 15, y: (bounds.height - sz.height) / 2))
    }
}

/// CLI 글자 배지(로고 대신).
final class GlyphView: NSView {
    var choice: AgentChoice? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = choice else { return }
        let col = NSColor(hex: c.colorHex)
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        col.withAlphaComponent(0.18).setFill(); path.fill()
        col.withAlphaComponent(0.55).setStroke(); path.lineWidth = 1; path.stroke()
        let font = NSFont.monospacedSystemFont(ofSize: c.glyph.count > 1 ? 7.5 : 10, weight: .bold)
        let str = NSAttributedString(string: c.glyph, attributes: [.font: font, .foregroundColor: col])
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }
}

extension NodeStatus {
    /// 헤더 상태 알약 문구.
    var pillText: String {
        switch self {
        case .starting: return "STARTING"
        case .working: return "RUNNING"
        case .idle: return "READY"
        case .waiting: return "NEEDS YOU"
        case .done: return "DONE"
        case .exited: return "EXITED"
        }
    }
}

/// 헤더 없는 노드 위의 투명 가림막. 누르면 선택, 끌면 이동, 두 번 누르면 편집.
final class MoveShieldView: NSView {
    weak var nodeView: NodeView?
    private var dragStart: (NSPoint, NSPoint)?
    private var moved = false

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 펜으로 이미지 위에 그릴 때는 본문이 받는다.
        if nodeView?.canvas?.tool == .pen { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let nv = nodeView, let sv = nv.superview else { return }
        nv.beginInteraction()
        if event.clickCount == 2 {
            dragStart = nil
            nv.setEditing(true)
            return
        }
        moved = false
        dragStart = (sv.convert(event.locationInWindow, from: nil), nv.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let nv = nodeView, let (start, origin) = dragStart, let sv = nv.superview else { return }
        let p = sv.convert(event.locationInWindow, from: nil)
        moved = true
        nv.setFrameOrigin(NSPoint(x: round(origin.x + p.x - start.x), y: round(origin.y + p.y - start.y)))
        nv.canvas?.layoutLinks()
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil && moved { nodeView?.commitFrame() }
        dragStart = nil
    }
}

final class ResizeHandleView: NSView {
    weak var nodeView: NodeView?
    private var start: (NSPoint, NSSize)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 1
        for i in 0..<3 {
            let o = CGFloat(i) * 4 + 4
            p.move(to: NSPoint(x: bounds.maxX - 2, y: bounds.maxY - o))
            p.line(to: NSPoint(x: bounds.maxX - o, y: bounds.maxY - 2))
        }
        p.stroke()
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let nv = nodeView, let sv = nv.superview else { return }
        nv.beginInteraction()
        start = (sv.convert(event.locationInWindow, from: nil), nv.frame.size)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let nv = nodeView, let (p0, s0) = start, let sv = nv.superview else { return }
        let p = sv.convert(event.locationInWindow, from: nil)
        nv.setFrameSize(NSSize(width: max(NodeView.minSize.width, round(s0.width + p.x - p0.x)),
                               height: max(NodeView.minSize.height, round(s0.height + p.y - p0.y))))
        nv.canvas?.layoutGroups()
    }

    override func mouseUp(with event: NSEvent) {
        if start != nil { nodeView?.commitFrame() }
        start = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

extension NodeStatus {
    var color: NSColor {
        switch self {
        case .starting: return Theme.textDim
        case .working: return Theme.accent
        case .idle: return NSColor(hex: "#6FCF97")
        case .waiting: return NSColor(hex: "#E9C46A")
        case .done: return NSColor(hex: "#7AA7E8")
        case .exited: return NSColor(hex: "#B5524A")
        }
    }
}

/// 클로저를 실행하는 메뉴 항목.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

/// 간단한 입력 창.
enum Prompt {
    static func text(title: String, message: String = "", value: String = "", placeholder: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = value
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard run(alert, focus: field) == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 창을 띄우고 열리자마자 field 에 초점을 준다(글자는 모두 골라 둔다).
    /// initialFirstResponder 만으로는 NSAlert 가 첫 단추에 초점을 두는 때가 있어, 창이 뜬 뒤 한 번 더 잡는다.
    /// Enter 는 첫 단추(저장), Esc 는 Cancel 단추.
    static func run(_ alert: NSAlert, focus field: NSView) -> NSApplication.ModalResponse {
        alert.layout()
        alert.window.initialFirstResponder = field
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(field)
            (field as? NSTextField)?.selectText(nil)
        }
        return alert.runModal()
    }

    static func multiline(title: String, message: String = "", value: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        let tv = scroll.documentView as! NSTextView
        tv.string = value
        tv.font = .systemFont(ofSize: 13)
        tv.isRichText = false
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        // 여러 줄 칸은 Enter 가 줄바꿈이라 Cmd+Enter 로 저장한다.
        alert.buttons[0].keyEquivalentModifierMask = .command
        guard run(alert, focus: tv) == .alertFirstButtonReturn else { return nil }
        return tv.string
    }
}


/// 오케스트레이터의 연결 손잡이. 눌러 끌면 보드에 임시 선을 그리고, 놓은 자리의 그룹 틀이나 콘솔에 연결을 켜거나 끈다.
final class WirePortView: NSView {
    weak var nodeView: NodeView?
    private var line: CAShapeLayer?
    private var start: NSPoint = .zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 4)
        Theme.accent.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: -1.5, dy: -1.5))
        ring.lineWidth = 1
        ring.stroke()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        guard let canvas = nodeView?.canvas else { return }
        start = canvas.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
        let l = CAShapeLayer()
        l.strokeColor = Theme.accent.cgColor
        l.fillColor = nil
        l.lineWidth = 2
        l.lineDashPattern = [6, 4]
        canvas.wantsLayer = true
        canvas.layer?.addSublayer(l)
        line = l
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas = nodeView?.canvas, let l = line else { return }
        let p = canvas.convert(event.locationInWindow, from: nil)
        let path = CGMutablePath()
        path.move(to: start)
        let dx = max(60, abs(p.x - start.x) / 2)
        path.addCurve(to: p, control1: NSPoint(x: start.x + dx, y: start.y), control2: NSPoint(x: p.x - dx, y: p.y))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        l.path = path
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        line?.removeFromSuperlayer()
        line = nil
        guard let nv = nodeView, let canvas = nv.canvas, let c = canvas.controller else { return }
        let p = canvas.convert(event.locationInWindow, from: nil)
        // 콘솔 노드가 그룹 틀 안에 있으므로 콘솔을 먼저 본다. 그룹 머리·여백에 놓으면 그룹 전체.
        if let (id, v) = canvas.nodeViews.first(where: { $0.value.frame.contains(p) && $0.key != nv.nodeID }),
           nv.model.node(id)?.kind == .terminal, v.isHidden == false {
            c.toggleWire(nv.nodeID, to: id)
            c.chrome.flash(Self.message(c, orch: nv.nodeID, target: id, name: nv.model.node(id)?.title ?? "console"))
        } else if let (id, _) = canvas.groupViews.first(where: { $0.value.frame.contains(p) }) {
            c.toggleWire(nv.nodeID, to: id)
            let name = nv.model.selectedWorkspace.teams.first { $0.id == id }?.name ?? "group"
            c.chrome.flash(Self.message(c, orch: nv.nodeID, target: id, name: name))
        } else {
            c.chrome.flash("Drop on a group or a console to wire it")
        }
    }

    private static func message(_ c: MainWindowController, orch: UUID, target: UUID, name: String) -> String {
        let wired = c.model.selectedWorkspace.links?.contains { $0.from == orch && $0.to == target } ?? false
        return wired ? "Wired \(name)" : "Unwired \(name)"
    }
}
