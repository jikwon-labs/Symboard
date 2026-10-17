import AppKit
import SwiftUI
import SymboardCore

/// SwiftUI 본문이 보는 노드 사본. 편집은 save 로 모델에 되돌린다.
@MainActor
final class NodeBox: ObservableObject {
    @Published var node: BoardNode
    let save: (BoardNode) -> Void

    init(node: BoardNode, save: @escaping (BoardNode) -> Void) {
        self.node = node
        self.save = save
    }

    func update(_ body: (inout BoardNode) -> Void) {
        var n = node
        body(&n)
        node = n
        save(n)
    }

    func binding<T>(_ key: WritableKeyPath<BoardNode, T>) -> Binding<T> {
        Binding(get: { self.node[keyPath: key] }, set: { v in self.update { $0[keyPath: key] = v } })
    }
}

/// SwiftUI 뷰를 노드 본문으로 붙인다.
final class HostedContent: NodeContent {
    let box: NodeBox
    let host: NSView
    var view: NSView { host }
    private let extraMenu: (NodeBox) -> [NSMenuItem]

    init<V: View>(node: BoardNode, model: AppModel, menu: @escaping (NodeBox) -> [NSMenuItem] = { _ in [] },
                  @ViewBuilder make: (NodeBox) -> V) {
        let id = node.id
        box = NodeBox(node: node) { [weak model] n in
            model?.mutateNode(id) { cur in
                // 위치·크기는 NodeView 가 관리하므로 본문 편집으로 덮어쓰지 않는다.
                let frame = cur.frame
                cur = n
                cur.frame = frame
            }
        }
        extraMenu = menu
        host = NSHostingView(rootView: make(box).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {
        var n = node
        n.frame = box.node.frame
        if n != box.node { box.node = node }
    }

    func menuItems() -> [NSMenuItem] { extraMenu(box) }
}

// MARK: 스티키·텍스트

struct StickyView: View {
    @ObservedObject var box: NodeBox
    var isSticky: Bool

    var body: some View {
        TextEditor(text: Binding(get: { box.node.text ?? "" }, set: { v in box.update { $0.text = v } }))
            .font(.system(size: isSticky ? 15 : 13, design: isSticky ? .rounded : .default))
            .scrollContentBackground(.hidden)
            .foregroundStyle(isSticky ? Color.black.opacity(0.85) : Color.white)
            .padding(8)
            .background(isSticky ? Color(nsColor: NSColor(hex: box.node.colorHex ?? "#FFD60A")) : Color(white: 0.12))
    }
}

enum StickyColors {
    static let all: [(String, String)] = [("Yellow", "#FFD60A"), ("Pink", "#FF9FC6"), ("Green", "#9BE59B"), ("Blue", "#9CCBFF"), ("Purple", "#C9B3FF")]

    @MainActor
    static func menu(_ box: NodeBox) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, hex) in all { sub.addItem(ClosureMenuItem(title: name) { box.update { $0.colorHex = hex } }) }
        item.submenu = sub
        return [item]
    }
}

// MARK: 체크리스트

struct ChecklistView: View {
    @ObservedObject var box: NodeBox
    @State private var draft = ""

    var items: [ChecklistItem] { box.node.checklist ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let done = items.filter(\.done).count
            if !items.isEmpty {
                ProgressView(value: Double(done), total: Double(max(items.count, 1)))
                    .padding(.horizontal, 10).padding(.top, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            Button {
                                box.update { n in
                                    if let i = n.checklist?.firstIndex(where: { $0.id == item.id }) { n.checklist?[i].done.toggle() }
                                }
                            } label: {
                                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(item.done ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                            Spacer()
                            Button {
                                box.update { $0.checklist?.removeAll { $0.id == item.id } }
                            } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(10)
            }
            TextField("Add item", text: $draft)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onSubmit {
                    let t = draft.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    box.update { $0.checklist = ($0.checklist ?? []) + [ChecklistItem(text: t)] }
                    draft = ""
                }
        }
        .background(Color(white: 0.12))
    }
}

// MARK: 칸반

struct KanbanView: View {
    @ObservedObject var box: NodeBox

    var columns: [KanbanColumn] { box.node.kanban ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { ci, col in
                KanbanColumnView(box: box, index: ci, column: col, isLast: ci == columns.count - 1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.12))
    }
}

struct KanbanColumnView: View {
    @ObservedObject var box: NodeBox
    var index: Int
    var column: KanbanColumn
    var isLast: Bool
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(column.title)  \(column.cards.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(column.cards.enumerated()), id: \.offset) { i, card in
                        HStack(alignment: .top) {
                            Text(card).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                            if index > 0 {
                                Button { move(i, by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                            }
                            if !isLast {
                                Button { move(i, by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                            }
                            Button { box.update { $0.kanban?[index].cards.remove(at: i) } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.22)))
                    }
                }
            }
            TextField("Add card", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit {
                    let t = draft.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    box.update { $0.kanban?[index].cards.append(t) }
                    draft = ""
                }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
    }

    private func move(_ i: Int, by d: Int) {
        box.update { n in
            guard var cols = n.kanban, cols.indices.contains(index + d) else { return }
            let card = cols[index].cards.remove(at: i)
            cols[index + d].cards.append(card)
            n.kanban = cols
        }
    }
}
