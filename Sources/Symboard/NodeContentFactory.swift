import AppKit
import SymboardCore

/// 터미널이 아닌 노드 본문을 만든다.
@MainActor
enum NodeContentFactory {
    static func make(node: BoardNode, model: AppModel) -> NodeContent {
        switch node.kind {
        case .sticky:
            return HostedContent(node: node, model: model, menu: StickyColors.menu) { StickyView(box: $0, isSticky: true) }
        case .text:
            return HostedContent(node: node, model: model) { StickyView(box: $0, isSticky: false) }
        case .checklist:
            return HostedContent(node: node, model: model) { ChecklistView(box: $0) }
        case .kanban:
            return HostedContent(node: node, model: model) { KanbanView(box: $0) }
        case .image:
            return ImageContent(node: node, model: model)
        default:
            return PlaceholderContent(text: node.kind.rawValue)
        }
    }
}

final class PlaceholderContent: NodeContent {
    let label: NSTextField
    var view: NSView { label }
    init(text: String) { label = NSTextField(labelWithString: text) }
    func sync(node: BoardNode) {}
}
