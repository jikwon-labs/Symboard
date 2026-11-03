import Foundation
import Testing
@testable import SymboardCore

/// 12차: 기본 노드 이름은 화면에서 지금 언어로, Colorful 채움은 라이트에서 밝게.
@Suite struct DefaultNameTests {
    func node(_ title: String) -> BoardNode {
        BoardNode(kind: .checklist, frame: Rect(x: 0, y: 0, w: 10, h: 10), title: title)
    }

    @Test func defaultTitleFollowsLanguage() {
        #expect(node("Checklist").displayTitle(in: .ko) == "체크리스트")
        #expect(node("Checklist").displayTitle(in: .en) == "Checklist")
        #expect(node("Note").displayTitle(in: .ko) == "메모")
    }

    @Test func renamedTitleStays() {
        #expect(node("My tasks").displayTitle(in: .ko) == "My tasks")
        // 표에 있는 글이라도 기본 이름이 아니면 바꾸지 않는다("Done" 은 노드 기본 이름이 아니다).
        #expect(node("Done").displayTitle(in: .ko) == "Done")
    }

    @Test func everyDefaultHasKorean() {
        for t in DefaultNames.nodeTitles.union(DefaultNames.kanbanColumns) {
            #expect(Strings.ko[t] != nil, "no Korean for \(t)")
        }
    }

    @Test func kanbanColumns() {
        #expect(KanbanColumn(title: "In Progress").displayTitle(in: .ko) == "진행 중")
        #expect(KanbanColumn(title: "Shipping").displayTitle(in: .ko) == "Shipping")
    }
}

@Suite struct ShapeFillTests {
    /// DiagramMaker.dim 과 같은 계산(22%, 버림).
    func dim(_ hex: String) -> String {
        let c = ShapeFill.rgb(hex)!
        return String(format: "#%02X%02X%02X", Int(c.r * 255 * 0.22), Int(c.g * 255 * 0.22), Int(c.b * 255 * 0.22))
    }
    func luminance(_ hex: String) -> Double {
        let c = ShapeFill.rgb(hex)!
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    @Test func darkFillBecomesLightInLightMode() {
        for tint in ["#56A8F5", "#6FCF97", "#E9C46A", "#B48CF2", "#F28AB2", "#56C2C9"] {
            let d = dim(tint)
            #expect(ShapeFill.isDarkened(d))
            let l = ShapeFill.forMode(d, light: true)
            #expect(luminance(l) > 0.8, "\(tint) -> \(l)")
            // 색 계열이 남는다: 가장 강한 성분이 원래 색과 같다.
            let o = ShapeFill.rgb(tint)!, n = ShapeFill.rgb(l)!
            let strongest = { (c: (r: Double, g: Double, b: Double)) in [c.r, c.g, c.b].enumerated().max { $0.element < $1.element }!.offset }
            #expect(strongest(o) == strongest(n), "\(tint) -> \(l)")
        }
    }

    @Test func darkModeAndUserColorsUntouched() {
        #expect(ShapeFill.forMode(dim("#56A8F5"), light: false) == dim("#56A8F5"))
        #expect(ShapeFill.forMode("#C9A227", light: true) == "#C9A227")
        #expect(ShapeFill.forMode("#000000", light: true) == "#000000")
        #expect(ShapeFill.forMode("oops", light: true) == "oops")
    }
}

/// 홈에서 프로젝트를 목록에서 빼기.
@Suite struct RemoveProjectTests {
    func ws(_ name: String, _ path: String?, nodes: Int = 0) -> Workspace {
        var w = Workspace(name: name)
        w.projectPath = path
        w.nodes = (0..<nodes).map { _ in BoardNode(kind: .checklist, frame: Rect(x: 0, y: 0, w: 10, h: 10), title: "Checklist") }
        return w
    }

    @Test func removesAllWorkspacesOfProject() {
        let a1 = ws("A1", "/a", nodes: 2), a2 = ws("A2", "/a", nodes: 1), b = ws("B", "/b")
        var state = AppState(workspaces: [a1, b, a2], selectedWorkspaceID: a2.id)
        let ids = Projects.remove("/a", from: &state)
        #expect(state.workspaces.map(\.id) == [b.id])
        #expect(Set(ids) == Set((a1.nodes + a2.nodes).map(\.id)))
        #expect(state.selectedWorkspaceID == b.id)
        #expect(Projects.paths(in: state.workspaces) == ["/b"])
    }

    @Test func keepsSelectionWhenOtherProject() {
        let a = ws("A", "/a"), b = ws("B", "/b")
        var state = AppState(workspaces: [a, b], selectedWorkspaceID: b.id)
        Projects.remove("/a", from: &state)
        #expect(state.selectedWorkspaceID == b.id)
    }

    @Test func lastProjectLeavesEmptyWorkspace() {
        let a = ws("A", "/a", nodes: 1)
        var state = AppState(workspaces: [a], selectedWorkspaceID: a.id)
        Projects.remove("/a", from: &state)
        #expect(state.workspaces.count == 1)
        #expect(state.workspaces[0].projectPath == nil)
        #expect(state.workspaces[0].nodes.isEmpty)
        #expect(state.selectedWorkspaceID == state.workspaces[0].id)
        #expect(Projects.paths(in: state.workspaces).isEmpty)
    }

    @Test func unknownPathChangesNothing() {
        let a = ws("A", "/a")
        var state = AppState(workspaces: [a], selectedWorkspaceID: a.id)
        let before = state
        #expect(Projects.remove("/zzz", from: &state).isEmpty)
        #expect(state == before)
    }
}

/// 홈 카드의 마지막 작업 시각.
@Suite struct ProjectLastActiveTests {
    @Test func latestAmongWorkspaces() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var a1 = Workspace(name: "A1", projectPath: "/a"); a1.lastActiveAt = t0
        var a2 = Workspace(name: "A2", projectPath: "/a"); a2.lastActiveAt = t0.addingTimeInterval(500)
        let b = Workspace(name: "B", projectPath: "/b")
        #expect(Projects.lastActive("/a", in: [a1, b, a2]) == t0.addingTimeInterval(500))
        #expect(Projects.lastActive("/b", in: [a1, b, a2]) == nil)
    }

    @Test func agoBuckets() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        func ago(_ s: TimeInterval) -> String { Projects.ago(now.addingTimeInterval(-s), now: now) }
        #expect(ago(10) == L("just now"))
        #expect(ago(60) == L("%d minute ago", 1))
        #expect(ago(3 * 3600 + 100) == L("%d hours ago", 3))
        #expect(ago(2 * 86400) == L("%d days ago", 2))
        #expect(ago(90 * 86400) == L("%d months ago", 3))
        #expect(ago(-5) == L("just now"))
    }

    @Test func koreanStrings() {
        #expect(L10n.translate("%d hours ago", to: .ko) == "%d시간 전")
        #expect(L10n.translate("just now", to: .ko) == "방금")
    }

    @Test func oldStateDecodesWithoutTimestamp() throws {
        let data = try StateStore.encode(AppState.initial())
        let s = try StateStore.decode(data)
        #expect(s.workspaces[0].lastActiveAt == nil)
    }
}
