import Foundation

/// 오른쪽 세션 목록의 줄 순서. 지금 보는 작업공간을 맨 위에 두고, 작업공간 안에서는 사람이 봐야 할 것부터 놓는다.
public enum SessionList {
    /// 작을수록 위. 답을 기다리는 콘솔 → 일하는 콘솔 → 끝났는데 아직 안 본 콘솔 → 쉬는 콘솔 → 꺼진 콘솔.
    public static func rank(_ s: NodeStatus) -> Int {
        switch s {
        case .waiting: return 0
        case .working: return 1
        case .done: return 2
        case .idle, .starting: return 3
        case .exited: return 4
        }
    }

    /// 작업공간 묶음 순서(지금 작업공간 먼저, 나머지는 받은 순서)와 묶음 안의 상태 순서로 줄을 세운다.
    /// 같은 칸끼리는 받은 순서(보드에 놓인 순서)를 지킨다.
    public static func order<T>(_ items: [T], current: UUID?, workspace: (T) -> UUID, status: (T) -> NodeStatus) -> [T] {
        var wsOrder: [UUID: Int] = [:]
        for it in items where wsOrder[workspace(it)] == nil { wsOrder[workspace(it)] = wsOrder.count + 1 }
        if let current { wsOrder[current] = 0 }
        return items.enumerated().sorted { a, b in
            let ka = (wsOrder[workspace(a.element)] ?? 0, rank(status(a.element)), a.offset)
            let kb = (wsOrder[workspace(b.element)] ?? 0, rank(status(b.element)), b.offset)
            return ka < kb
        }.map(\.element)
    }
}
