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
    private let teamBadge = NSTextField(labelWithString: "")

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

    static func isHeaderless(_ kind: NodeKind) -> Bool { [.text, .sticky, .image].contains(kind) }

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
            shield.nodeView = self
            addSubview(shield)
        }
        addSubview(resizeHandle)
        header.nodeView = self
        resizeHandle.nodeView = self
        header.closeButton.target = self
        header.closeButton.action = #selector(closeClicked)
        header.menuButton.target = self
        header.menuButton.action = #selector(menuClicked(_:))
        teamBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        teamBadge.textColor = .white
        teamBadge.wantsLayer = true
        teamBadge.layer?.cornerRadius = 4
        header.addSubview(teamBadge)
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
        header.needsLayout = true
    }

    func syncFromModel() {
        guard let node = model.node(nodeID) else { return }
        let target = CanvasGeometry.viewRect(node.frame)
        if frame != target { frame = target }
        header.titleLabel.stringValue = node.role.map { "\($0) - \(node.title)" } ?? node.title
        if let teamID = node.teamID, let ws = canvas?.workspace, let team = ws.teams.first(where: { $0.id == teamID }) {
            teamBadge.stringValue = " \(team.name) "
            teamBadge.layer?.backgroundColor = NSColor(hex: team.colorHex).cgColor
            teamBadge.isHidden = false
        } else {
            teamBadge.isHidden = true
        }
        header.badgeView = teamBadge.isHidden ? nil : teamBadge
        header.needsLayout = true
        content.sync(node: node)
    }

    func setStatus(_ status: NodeStatus?) {
        header.setStatus(status)
    }

    private func updateBorder() {
        if headerless {
            layer?.borderColor = Theme.accent.cgColor
            layer?.borderWidth = isSelected ? 1.5 : 0
            resizeHandle.isHidden = !isSelected
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

    private func rename() {
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

/// 노드 헤더. 끌면 노드가 움직이고, 두 번 누르면 이름을 바꾼다.
final class NodeHeaderView: NSView {
    weak var nodeView: NodeView?
    let titleLabel = NSTextField(labelWithString: "")
    let statusDot = NSView()
    let statusLabel = NSTextField(labelWithString: "")
    let closeButton = NSButton()
    let menuButton = NSButton()
    weak var badgeView: NSView?
    private var dragStart: (NSPoint, NSPoint)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.isHidden = true
        for (b, sym, tip) in [(closeButton, "xmark", "Close"), (menuButton, "ellipsis", "More")] {
            b.bezelStyle = .inline
            b.isBordered = false
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)
            b.contentTintColor = NSColor(calibratedWhite: 0.75, alpha: 1)
            b.toolTip = tip
        }
        [statusDot, titleLabel, statusLabel, closeButton, menuButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 10
        if !statusDot.isHidden {
            statusDot.frame = NSRect(x: x, y: (h - 8) / 2, width: 8, height: 8)
            x += 14
        }
        closeButton.frame = NSRect(x: bounds.width - 26, y: (h - 20) / 2, width: 20, height: 20)
        menuButton.frame = NSRect(x: bounds.width - 48, y: (h - 20) / 2, width: 20, height: 20)
        var right = bounds.width - 54
        statusLabel.sizeToFit()
        if !statusLabel.isHidden {
            statusLabel.frame = NSRect(x: right - statusLabel.frame.width, y: (h - statusLabel.frame.height) / 2,
                                       width: statusLabel.frame.width, height: statusLabel.frame.height)
            right = statusLabel.frame.minX - 6
        }
        if let badge = badgeView as? NSTextField {
            badge.sizeToFit()
            badge.frame = NSRect(x: right - badge.frame.width, y: (h - 16) / 2, width: badge.frame.width, height: 16)
            right = badge.frame.minX - 6
        }
        titleLabel.frame = NSRect(x: x, y: (h - 16) / 2, width: max(10, right - x), height: 16)
    }

    func setStatus(_ status: NodeStatus?) {
        guard let status else {
            statusDot.isHidden = true
            statusLabel.isHidden = true
            needsLayout = true
            return
        }
        statusDot.isHidden = false
        statusLabel.isHidden = false
        statusDot.layer?.backgroundColor = status.color.cgColor
        if statusLabel.stringValue != status.label {
            statusLabel.stringValue = status.label
            needsLayout = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let nv = nodeView else { return }
        nv.beginInteraction()
        if event.clickCount == 2 {
            dragStart = nil
            return
        }
        dragStart = (nv.superview!.convert(event.locationInWindow, from: nil), nv.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let nv = nodeView, let (start, origin) = dragStart, let sv = nv.superview else { return }
        let p = sv.convert(event.locationInWindow, from: nil)
        nv.setFrameOrigin(NSPoint(x: round(origin.x + p.x - start.x), y: round(origin.y + p.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { nodeView?.commitFrame() }
        dragStart = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
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
        case .starting: return .systemGray
        case .working: return .systemGreen
        case .idle: return .systemBlue
        case .waiting: return .systemOrange
        case .exited: return .systemRed
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
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
        alert.window.initialFirstResponder = tv
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return tv.string
    }
}
