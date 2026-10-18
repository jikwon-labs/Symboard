import SwiftUI
import SymboardCore

/// 레포별·전역 메모. 버튼을 눌렀을 때만 고른 노드에 입력으로 보낸다.
@MainActor
final class MemoryModel: ObservableObject {
    unowned let model: AppModel
    /// nil 이면 전역.
    @Published var scope: String?
    @Published var editingID: UUID?
    @Published var pressEnter = false
    @Published var note = ""
    @Published private(set) var revision = 0

    init(model: AppModel) { self.model = model }

    /// 보드에 있는 터미널 노드 폴더들의 레포 목록.
    var repos: [String] {
        let fromNodes = model.state.workspaces.flatMap(\.nodes).compactMap { $0.terminal?.cwd }.compactMap { MemoryScope.repoRoot(for: $0) }
        let fromNotes = model.state.memories.compactMap(\.repoPath)
        return Array(Set(fromNodes + fromNotes)).sorted()
    }

    var notes: [MemoryNote] { model.state.memories.filter { $0.repoPath == scope } }

    func add() {
        let n = MemoryNote(repoPath: scope, title: "New memory", body: "")
        model.mutateState { $0.memories.append(n) }
        editingID = n.id
        revision += 1
    }

    func update(_ id: UUID, title: String? = nil, body: String? = nil) {
        model.mutateState { s in
            guard let i = s.memories.firstIndex(where: { $0.id == id }) else { return }
            if let title { s.memories[i].title = title }
            if let body { s.memories[i].body = body }
        }
        revision += 1
    }

    func remove(_ id: UUID) {
        model.mutateState { $0.memories.removeAll { $0.id == id } }
        revision += 1
    }

    /// 선택한 노드에 메모를 넣는다.
    func send(_ n: MemoryNote, to nodeID: UUID?) {
        guard let nodeID, let target = model.node(nodeID), target.kind == .terminal,
              let s = model.sessions.session(for: nodeID), s.running else {
            note = "Select a running terminal node on the board first."
            return
        }
        s.sendText(MemoryScope.text(for: n), submit: pressEnter)
        note = "Sent \"\(n.title)\" to \(target.title)"
    }
}

struct MemoryPanelView: View {
    @ObservedObject var memory: MemoryModel
    @ObservedObject var panel: SidePanelState

    var body: some View {
        let _ = memory.revision
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $memory.scope) {
                    Text("Global").tag(String?.none)
                    ForEach(memory.repos, id: \.self) { r in Text((r as NSString).lastPathComponent).tag(String?.some(r)) }
                }
                .labelsHidden()
                Button("New") { memory.add() }.controlSize(.small)
            }
            Toggle("Press Enter after sending", isOn: $memory.pressEnter).font(.system(size: 10)).controlSize(.mini)
            Text(selectedText).font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(memory.notes) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            if memory.editingID == n.id {
                                TextField("Title", text: Binding(get: { n.title }, set: { memory.update(n.id, title: $0) }))
                                    .textFieldStyle(.roundedBorder)
                                TextEditor(text: Binding(get: { n.body }, set: { memory.update(n.id, body: $0) }))
                                    .font(.system(size: 11)).frame(height: 90)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4)))
                            } else {
                                Text(n.title).font(.system(size: 12, weight: .semibold))
                                Text(n.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4)
                            }
                            HStack {
                                Button("Send to Node") { memory.send(n, to: panel.selectedNodeID) }
                                Button(memory.editingID == n.id ? "Done" : "Edit") {
                                    memory.editingID = memory.editingID == n.id ? nil : n.id
                                }
                                Spacer()
                                Button { memory.remove(n.id) } label: { Image(systemName: "trash") }.buttonStyle(.plainHit)
                            }
                            .controlSize(.small)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
                    }
                    if memory.notes.isEmpty {
                        Text("No memories here yet. Memories are only sent when you press Send to Node.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if !memory.note.isEmpty { Text(memory.note).font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .padding(8)
    }

    private var selectedText: String {
        guard let id = panel.selectedNodeID, let n = memory.model.node(id) else { return "Target: none (click a terminal node)" }
        return "Target: \(n.title)"
    }
}
