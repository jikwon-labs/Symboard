import AppKit
import Combine
import SymboardCore

extension Notification.Name {
    /// 작업공간 목록·선택이 바뀌었을 때(노드 단위 변경은 제외).
    static let workspacesChanged = Notification.Name("symboard.workspacesChanged")
    /// 노드가 추가·삭제됐을 때. object 는 작업공간 id.
    static let nodesChanged = Notification.Name("symboard.nodesChanged")
}

/// 앱 상태의 단일 원본. 바뀔 때마다 잠깐 모았다가 디스크에 저장한다.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState
    let store: StateStore
    lazy var sessions = SessionManager(model: self)
    lazy var loops = LoopRunner(model: self)
    lazy var handoff = HandoffCoordinator(model: self)
    lazy var usage = UsageStore(model: self)
    lazy var profiles = ProfilesModel(model: self)
    lazy var memory = MemoryModel(model: self)
    private var saveWork: DispatchWorkItem?
    /// 작업공간마다 보드 되돌리기 기록(9차). 바뀐 뒤 0.6초 조용하면 한 칸.
    private var histories: [UUID: BoardHistory] = [:]
    private var historyWork: DispatchWorkItem?

    init(store: StateStore) {
        self.store = store
        self.state = store.load()
        if state.selectedIndex == nil { state = .initial() }
        recordHistory()
    }

    var statusDirectory: URL { store.directory.appendingPathComponent("status", isDirectory: true) }

    /// claude 가 보드에 콘솔을 띄우는 도구의 소켓(8차 3번).
    lazy var boardTools = BoardToolServer(directory: store.directory)

    // MARK: 저장

    func scheduleSave() {
        scheduleHistory()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do { try store.save(state) } catch { NSLog("Symboard: save failed: \(error)") }
    }

    // MARK: 되돌리기

    private func scheduleHistory() {
        historyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recordHistory() }
        historyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func recordHistory() {
        historyWork?.cancel()
        historyWork = nil
        for ws in state.workspaces { histories[ws.id, default: BoardHistory()].record(BoardSnapshot(ws)) }
    }

    var canUndoBoard: Bool {
        let ws = selectedWorkspace
        var h = histories[ws.id] ?? BoardHistory()
        return h.canUndo || h.record(BoardSnapshot(ws))
    }
    var canRedoBoard: Bool { histories[selectedWorkspace.id]?.canRedo ?? false }

    /// 보고 있는 작업공간을 한 칸 되돌린다(redo 면 다시 한다). 사라지는 콘솔은 프로세스를 끄고, 돌아오는 콘솔은 다시 띄운다.
    @discardableResult
    func stepBoard(redo: Bool) -> Bool {
        let wsID = selectedWorkspace.id
        var h = histories[wsID] ?? BoardHistory()
        let current = BoardSnapshot(selectedWorkspace)
        guard let target = redo ? h.redo(current: current) : h.undo(current: current) else { histories[wsID] = h; return false }
        histories[wsID] = h
        historyWork?.cancel()
        historyWork = nil
        let gone = Set(current.nodes.map(\.id)).subtracting(target.nodes.map(\.id))
        for id in gone { sessions.terminate(id) }
        mutateWorkspace(wsID) { target.apply(to: &$0) }
        // 되돌린 결과는 기록하지 않는다(mutateWorkspace 가 건 기록 예약을 지운다).
        historyWork?.cancel()
        historyWork = nil
        NotificationCenter.default.post(name: .nodesChanged, object: wsID)
        return true
    }

    // MARK: 작업공간

    var selectedWorkspace: Workspace { state.workspaces[state.selectedIndex ?? 0] }

    func workspace(_ id: UUID) -> Workspace? { state.workspaces.first { $0.id == id } }

    func selectWorkspace(_ id: UUID) {
        guard state.selectedWorkspaceID != id else { return }
        state.selectedWorkspaceID = id
        scheduleSave()
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
    }

    @discardableResult
    func addWorkspace(name: String) -> Workspace {
        let ws = Workspace(name: name)
        state.workspaces.append(ws)
        state.selectedWorkspaceID = ws.id
        scheduleSave()
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
        return ws
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        mutateWorkspace(id) { $0.name = name }
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
    }

    func removeWorkspace(_ id: UUID) {
        guard state.workspaces.count > 1, let ws = workspace(id) else { return }
        for node in ws.nodes { sessions.terminate(node.id) }
        state.workspaces.removeAll { $0.id == id }
        if state.selectedWorkspaceID == id { state.selectedWorkspaceID = state.workspaces.first?.id }
        scheduleSave()
        NotificationCenter.default.post(name: .workspacesChanged, object: nil)
    }

    func mutateState(_ body: (inout AppState) -> Void) {
        body(&state)
        scheduleSave()
    }

    func mutateWorkspace(_ id: UUID, _ body: (inout Workspace) -> Void) {
        guard let i = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        body(&state.workspaces[i])
        scheduleSave()
    }

    /// 1차 상태를 2차 화면에 맞춘다: 프로젝트 폴더가 없는 작업공간에 폴더를 붙이고,
    /// "프로그램 - 폴더" 꼴의 콘솔 이름을 짧은 사람 이름으로 바꾼다.
    func assignProjects(fallback: String) {
        var changed = false
        for i in state.workspaces.indices {
            // 빈 작업공간은 프로젝트를 정하지 않는다(처음 실행이면 홈 화면에서 폴더를 고른다).
            if state.workspaces[i].projectPath == nil, !state.workspaces[i].nodes.isEmpty {
                state.workspaces[i].projectPath = Projects.inferPath(for: state.workspaces[i], fallback: fallback)
                changed = true
            }
            for j in state.workspaces[i].nodes.indices {
                let n = state.workspaces[i].nodes[j]
                guard let spec = n.terminal, n.title == MainWindowController.defaultTitle(for: spec) else { continue }
                state.workspaces[i].nodes[j].title = NamePool.next(used: Set(state.workspaces[i].nodes.map(\.title)))
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    // MARK: 노드

    func node(_ id: UUID) -> BoardNode? {
        for ws in state.workspaces { if let n = ws.nodes.first(where: { $0.id == id }) { return n } }
        return nil
    }

    func workspaceID(containing nodeID: UUID) -> UUID? {
        state.workspaces.first { ws in ws.nodes.contains { $0.id == nodeID } }?.id
    }

    func addNode(_ node: BoardNode, to wsID: UUID? = nil) {
        let target = wsID ?? selectedWorkspace.id
        mutateWorkspace(target) { $0.nodes.append(node) }
        NotificationCenter.default.post(name: .nodesChanged, object: target)
    }

    func removeNode(_ id: UUID) {
        guard let wsID = workspaceID(containing: id) else { return }
        sessions.terminate(id)
        mutateWorkspace(wsID) { ws in
            ws.nodes.removeAll { $0.id == id }
            ws.loops.removeAll { $0.nodeID == id }
            ws.links?.removeAll { $0.from == id || $0.to == id }
        }
        NotificationCenter.default.post(name: .nodesChanged, object: wsID)
    }

    func mutateNode(_ id: UUID, _ body: (inout BoardNode) -> Void) {
        for i in state.workspaces.indices {
            if let j = state.workspaces[i].nodes.firstIndex(where: { $0.id == id }) {
                body(&state.workspaces[i].nodes[j])
                scheduleSave()
                return
            }
        }
    }

    /// 노드를 맨 앞(배열 끝) 또는 맨 뒤(배열 처음)로 옮긴다.
    func moveLayer(_ id: UUID, toFront: Bool) {
        guard let wsID = workspaceID(containing: id) else { return }
        mutateWorkspace(wsID) { ws in
            guard let i = ws.nodes.firstIndex(where: { $0.id == id }) else { return }
            let n = ws.nodes.remove(at: i)
            if toFront { ws.nodes.append(n) } else { ws.nodes.insert(n, at: 0) }
        }
        NotificationCenter.default.post(name: .nodesChanged, object: wsID)
    }

    /// 새 노드를 놓을 자리: 현재 화면 중앙 근처에서 기존 노드와 덜 겹치게 조금씩 비켜 놓는다.
    func suggestedFrame(size: CGSize, near center: Point) -> Rect {
        let existing = selectedWorkspace.nodes.map(\.frame)
        var x = center.x - size.width / 2
        var y = center.y - size.height / 2
        var tries = 0
        while tries < 30, existing.contains(where: { abs($0.x - x) < 24 && abs($0.y - y) < 24 }) {
            x += 32; y += 32; tries += 1
        }
        return Rect(x: x, y: y, w: size.width, h: size.height)
    }
}
