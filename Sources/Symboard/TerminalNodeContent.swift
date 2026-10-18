import AppKit
import SwiftUI
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
        let bubble = CanvasHostingView(rootView: ResumeBubble { [weak self] yes in
            guard let self else { return }
            self.model.sessions.answerResume([self.nodeID], resume: yes)
        })
        bubble.isHidden = !model.sessions.pendingResume.contains(node.id)
        container.addSubview(bubble)
        container.bubble = bubble
        resumeObserver = NotificationCenter.default.addObserver(forName: .resumeChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as? UUID == self.nodeID else { return }
                self.container.bubble?.isHidden = true
            }
        }
    }

    private var resumeObserver: NSObjectProtocol?

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Restart Process") { [weak self] in self?.restart() },
         ClosureMenuItem(title: "Hand Off To...") { [weak self] in
             guard let self else { return }
             self.model.handoff.begin(from: self.nodeID)
         },
         ClosureMenuItem(title: "Add Loop...") { [weak self] in
             guard let self else { return }
             (NSApp.delegate as? AppDelegate)?.windowController.newLoop(for: self.nodeID)
         }] + permissionItems()
    }

    /// claude·codex 노드의 권한 모드 고르기. 바꾸면 같은 대화로 다시 띄운다.
    private func permissionItems() -> [NSMenuItem] {
        guard let spec = model.node(nodeID)?.terminal, spec.agent == .claude || spec.agent == .codex else { return [] }
        let item = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let now = PermissionMode.current(for: spec)
        for mode in PermissionMode.allCases {
            let mi = ClosureMenuItem(title: mode.menuTitle) { [weak self] in
                guard let self, mode != now else { return }
                self.model.mutateNode(self.nodeID) { n in
                    if let t = n.terminal { n.terminal?.extraArgs = mode.apply(to: t) }
                }
                (NSApp.delegate as? AppDelegate)?.windowController.currentCanvas?.nodeViews[self.nodeID]?.syncFromModel()
                self.model.sessions.restart(self.nodeID)
            }
            mi.state = mode == now ? .on : .off
            sub.addItem(mi)
        }
        item.submenu = sub
        return [item]
    }

    func teardown() {}

    @objc private func restart() {
        exitBanner.isHidden = true
        model.sessions.restart(nodeID)
    }
}

/// 다시 열었을 때 노드마다 뜨는 "지난 대화 이어 할까요?" 말풍선.
struct ResumeBubble: View {
    var answer: (Bool) -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.symAccent)
            Text("Resume last conversation?").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.symText)
            Button("Yes") { answer(true) }.buttonStyle(PillButtonStyle(prominent: true)).axName("Yes")
            Button("No") { answer(false) }.buttonStyle(PillButtonStyle()).axName("No")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .floatingCapsule(radius: 12)
        .fixedSize()
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
    weak var bubble: NSView?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        terminal?.frame = bounds.insetBy(dx: 4, dy: 2)
        if let b = banner {
            b.frame = NSRect(x: (bounds.width - 260) / 2, y: bounds.height - 40, width: 260, height: 28)
        }
        if let b = bubble {
            let s = b.fittingSize
            b.frame = NSRect(x: bounds.width - s.width - 10, y: 8, width: s.width, height: s.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        (superview as? NodeView)?.beginInteraction()
        if let t = terminal { window?.makeFirstResponder(t) }
    }
}
