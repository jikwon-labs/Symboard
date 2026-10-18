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
