import Foundation
import Testing
@testable import SymboardCore

@Suite struct SessionListTests {
    struct Row { var name: String; var ws: UUID; var status: NodeStatus }

    @Test func currentWorkspaceFirstThenByStatus() {
        let a = UUID(), b = UUID()
        let rows = [
            Row(name: "a-idle", ws: a, status: .idle),
            Row(name: "a-work", ws: a, status: .working),
            Row(name: "b-wait", ws: b, status: .waiting),
            Row(name: "b-exit", ws: b, status: .exited),
            Row(name: "b-work", ws: b, status: .working),
            Row(name: "a-wait", ws: a, status: .waiting),
        ]
        let out = SessionList.order(rows, current: b, workspace: \.ws, status: \.status).map(\.name)
        #expect(out == ["b-wait", "b-work", "b-exit", "a-wait", "a-work", "a-idle"])
    }

    @Test func keepsBoardOrderWithinSameStatus() {
        let a = UUID()
        let rows = [Row(name: "1", ws: a, status: .working), Row(name: "2", ws: a, status: .idle),
                    Row(name: "3", ws: a, status: .working), Row(name: "4", ws: a, status: .starting)]
        let out = SessionList.order(rows, current: nil, workspace: \.ws, status: \.status).map(\.name)
        #expect(out == ["1", "3", "2", "4"])
    }

    @Test func doneSitsBetweenWorkingAndIdle() {
        #expect(SessionList.rank(.working) < SessionList.rank(.done))
        #expect(SessionList.rank(.done) < SessionList.rank(.idle))
        #expect(SessionList.rank(.starting) == SessionList.rank(.idle))
    }
}
