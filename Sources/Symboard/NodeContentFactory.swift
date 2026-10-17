import AppKit
import SymboardCore

/// 터미널이 아닌 노드 본문을 만든다.
@MainActor
enum NodeContentFactory {
    static func make(node: BoardNode, model: AppModel) -> NodeContent {
        PlaceholderContent(text: node.kind.rawValue)
    }
}

final class PlaceholderContent: NodeContent {
    let label: NSTextField
    var view: NSView { label }
    init(text: String) { label = NSTextField(labelWithString: text) }
    func sync(node: BoardNode) {}
}
