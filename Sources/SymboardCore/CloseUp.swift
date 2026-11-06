import Foundation

/// 콘솔 가까이 보기. 멀리서 보던 콘솔 하나를 창에 꽉 차게 확대하고, 같은 키를 다시 누르면 보던 자리로 돌아간다.
/// 콘솔 글꼴 크기는 그대로 두고 캔버스 배율만 바꾼다(글꼴을 바꾸면 칸 수가 바뀌어 claude 화면이 다시 그려진다).
public struct CloseUp: Equatable, Sendable {
    /// 가까이 보고 있는 콘솔.
    public var nodeID: UUID
    /// 들어가기 전에 보던 위치·배율. 나올 때 되돌린다.
    public var previous: Viewport
    /// 어느 작업공간에서 들어갔는지. 작업공간이 바뀌면 되돌리지 않는다.
    public var workspaceID: UUID
    /// 가까이 보기로 맞춘 화면. 사용자가 화면을 옮기면 이것과 달라지고, 그때는 가까이 보기를 벗어난 것으로 본다.
    public var shown: Viewport?

    public init(nodeID: UUID, previous: Viewport, workspaceID: UUID, shown: Viewport? = nil) {
        self.nodeID = nodeID; self.previous = previous; self.workspaceID = workspaceID; self.shown = shown
    }

    /// 지금 화면(`now`)이 아직 가까이 보기로 맞춘 화면 그대로인가. 화면 점으로 8pt, 배율 1% 까지는 같은 것으로 친다.
    /// 맞춘 화면을 모르면(shown 이 nil) 그대로로 본다.
    public func stillShown(_ now: Viewport) -> Bool {
        guard let s = shown else { return true }
        guard s.zoom > 0, abs(now.zoom / s.zoom - 1) <= 0.01 else { return false }
        let dx = (now.center.x - s.center.x) * s.zoom, dy = (now.center.y - s.center.y) * s.zoom
        return dx * dx + dy * dy <= 64
    }

    /// 가까이 보기를 벗어났으면(작업공간이 다르거나 화면을 옮겼으면) 지난 기록은 버린다.
    public static func active(_ current: CloseUp?, workspaceID: UUID, now: Viewport) -> CloseUp? {
        guard let c = current, c.workspaceID == workspaceID, c.stillShown(now) else { return nil }
        return c
    }

    /// 콘솔 둘레에 남기는 여백(캔버스 좌표가 아니라 화면 점).
    public static let margin: Double = 24
    /// 너무 크게 키우면 글자가 흐려 보여 2배에서 멈춘다.
    public static let maxZoom: Double = 2

    /// 콘솔 `frame` 이 화면의 쓸 수 있는 영역(`width`×`height`, 화면 점)에 꽉 차는 배율.
    /// 쓸 수 있는 영역이 없으면 1.
    public static func zoom(fitting frame: Rect, width: Double, height: Double, minZoom: Double, maxZoom: Double = CloseUp.maxZoom) -> Double {
        let w = width - margin * 2, h = height - margin * 2
        guard frame.w > 0, frame.h > 0, w > 0, h > 0 else { return 1 }
        let z = min(w / frame.w, h / frame.h)
        return min(maxZoom, max(minZoom, z))
    }

    /// 콘솔의 가운데.
    public static func center(of frame: Rect) -> Point { Point(x: frame.x + frame.w / 2, y: frame.y + frame.h / 2) }

    /// 키를 눌렀을 때 할 일. 같은 콘솔을 가까이 보는 중이면 되돌리고, 아니면(다른 콘솔이거나 처음) 들어간다.
    public enum Step: Equatable, Sendable { case enter, restore }
    public static func step(current: CloseUp?, target: UUID, workspaceID: UUID) -> Step {
        guard let c = current, c.workspaceID == workspaceID, c.nodeID == target else { return .enter }
        return .restore
    }
}
