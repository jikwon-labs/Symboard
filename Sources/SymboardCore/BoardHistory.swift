import Foundation

/// 보드 되돌리기(⌘Z)·다시 하기(⇧⌘Z)의 기록(9차).
/// 바뀔 때마다 기록하지 않고, 바뀐 뒤 잠깐 조용해진 상태("자리 잡은 상태")만 한 칸으로 남긴다.
/// 그래서 끌기·입력처럼 잘게 바뀌는 것도 한 번에 되돌리고, 사람·에이전트·명령 어느 쪽이 바꿨든 같은 방법으로 되돌린다.
public struct BoardSnapshot: Equatable, Sendable {
    public var nodes: [BoardNode]
    public var teams: [Team]
    public var strokes: [Stroke]
    public var links: [NodeLink]

    public init(_ ws: Workspace) {
        nodes = ws.nodes; teams = ws.teams; strokes = ws.strokes; links = ws.links ?? []
    }

    /// 비교용: 사용자가 바꾼 것이 아닌 값(콘솔의 대화 id·띄운 적 있음)을 지운다.
    var comparable: BoardSnapshot {
        var s = self
        for i in s.nodes.indices {
            s.nodes[i].terminal?.sessionID = nil
            s.nodes[i].terminal?.hasLaunched = false
        }
        return s
    }

    /// 이 상태로 작업공간을 되돌린다. 남아 있는 콘솔의 대화 id·띄운 적 있음은 지금 값을 지킨다(이어 가기가 끊기지 않게).
    public func apply(to ws: inout Workspace) {
        let live = Dictionary(ws.nodes.compactMap { n in n.terminal.map { (n.id, $0) } }, uniquingKeysWith: { a, _ in a })
        var restored = nodes
        for i in restored.indices {
            guard let now = live[restored[i].id], var spec = restored[i].terminal else { continue }
            spec.sessionID = now.sessionID ?? spec.sessionID
            spec.hasLaunched = now.hasLaunched || spec.hasLaunched
            restored[i].terminal = spec
        }
        ws.nodes = restored
        ws.teams = teams
        ws.strokes = strokes
        ws.links = links.isEmpty ? nil : links
        // 사라진 노드를 가리키는 루프는 뺀다.
        let ids = Set(restored.map(\.id))
        ws.loops.removeAll { !ids.contains($0.nodeID) && $0.targetIDs == nil && !($0.targetAll ?? false) }
    }
}

public struct BoardHistory: Sendable {
    public static let limit = 100
    public private(set) var undoStack: [BoardSnapshot] = []
    public private(set) var redoStack: [BoardSnapshot] = []
    /// 마지막으로 자리 잡은 상태.
    public private(set) var settled: BoardSnapshot?

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// 지금 상태를 자리 잡은 상태로 기록한다. 앞 상태와 다르면 앞 상태를 되돌리기 칸에 쌓고 다시 하기 칸을 비운다.
    @discardableResult
    public mutating func record(_ current: BoardSnapshot) -> Bool {
        guard let prev = settled else { settled = current; return false }
        guard prev.comparable != current.comparable else { settled = current; return false }
        undoStack.append(prev)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
        settled = current
        return true
    }

    /// 되돌릴 상태. 아직 기록하지 않은 변경이 있으면 먼저 기록한다(방금 한 일을 되돌린다).
    public mutating func undo(current: BoardSnapshot) -> BoardSnapshot? {
        record(current)
        guard let target = undoStack.popLast(), let now = settled else { return nil }
        redoStack.append(now)
        settled = target
        return target
    }

    public mutating func redo(current: BoardSnapshot) -> BoardSnapshot? {
        // 되돌린 뒤 새로 바꿨으면 다시 하기 칸은 비워진다.
        record(current)
        guard let target = redoStack.popLast(), let now = settled else { return nil }
        undoStack.append(now)
        settled = target
        return target
    }
}
