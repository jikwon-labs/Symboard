import AppKit
import SymboardCore

/// 터미널 노드 본문. 세션의 SwiftTerm 뷰를 그대로 붙인다.
final class TerminalNodeContent: NSObject, NodeContent {
    let nodeID: UUID
    unowned let model: AppModel
    let container = TerminalContainerView()
    private let exitBanner = NSButton(title: "Process exited - click to restart", target: nil, action: nil)

    var view: NSView { container }

    init(node: BoardNode, model: AppModel) {
        self.nodeID = node.id
        self.model = model
        super.init()
        exitBanner.bezelStyle = .push
        exitBanner.target = self
        exitBanner.action = #selector(restart)
        exitBanner.isHidden = true
        if let s = model.sessions.ensureSession(for: node) {
            container.terminal = s.view
            s.onExit = { [weak self] _ in self?.exitBanner.isHidden = false }
        }
        container.addSubview(exitBanner)
        container.banner = exitBanner
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Restart Process") { [weak self] in self?.restart() },
         ClosureMenuItem(title: "Add Loop...") { [weak self] in
             guard let self, let wsID = self.model.workspaceID(containing: self.nodeID),
                   let ws = self.model.workspace(wsID),
                   let rule = LoopDialog.run(nodes: ws.nodes, preselect: self.nodeID) else { return }
             self.model.loops.add(rule)
         }]
    }

    func teardown() {}

    @objc private func restart() {
        exitBanner.isHidden = true
        model.sessions.restart(nodeID)
    }
}

final class TerminalContainerView: NSView {
    var terminal: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let t = terminal { addSubview(t, positioned: .below, relativeTo: nil) }
            needsLayout = true
        }
    }
    weak var banner: NSView?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        terminal?.frame = bounds.insetBy(dx: 4, dy: 2)
        if let b = banner {
            b.frame = NSRect(x: (bounds.width - 260) / 2, y: bounds.height - 40, width: 260, height: 28)
        }
    }

    override func mouseDown(with event: NSEvent) {
        (superview as? NodeView)?.beginInteraction()
        if let t = terminal { window?.makeFirstResponder(t) }
    }
}
