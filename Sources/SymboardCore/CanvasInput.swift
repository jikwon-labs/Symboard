import Foundation

/// 확대/축소된 캔버스 위 입력 좌표 계산.
public enum CanvasInput {
    /// SwiftUI 호스팅 뷰는 마우스 위치를 "창 좌표 − 자기 원점" 으로만 계산한다(배율 무시).
    /// 그 계산 결과가 실제 로컬 좌표 (localX, localY) 가 되도록 넘길 창 좌표를 돌려준다.
    /// - Parameters:
    ///   - localX, localY: 뷰 안의 실제 좌표(뷰 좌표계, flipped 면 아래로 증가).
    ///   - originX, originY: 뷰 좌표 (0,0) 의 창 좌표(창 좌표는 위로 증가).
    public static func unscaledWindowPoint(localX: Double, localY: Double, originX: Double, originY: Double,
                                           flipped: Bool) -> (x: Double, y: Double) {
        (originX + localX, flipped ? originY - localY : originY + localY)
    }
}

/// 새 노드를 화면에 보이는 자리로 옮기는 계산.
public enum CanvasLayout {
    /// frame 을 safe 안으로 옮긴다. 한 방향이 safe 보다 크면 그 방향은 safe 의 시작에 맞춘다.
    public static func fit(_ frame: Rect, in safe: Rect) -> Rect {
        var f = frame
        f.x = frame.w >= safe.w ? safe.x : min(max(frame.x, safe.x), safe.x + safe.w - frame.w)
        f.y = frame.h >= safe.h ? safe.y : min(max(frame.y, safe.y), safe.y + safe.h - frame.h)
        return f
    }
}
