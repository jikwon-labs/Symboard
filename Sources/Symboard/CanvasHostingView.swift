import AppKit
import SwiftUI
import SymboardCore

/// 확대/축소된 캔버스 위에 놓는 SwiftUI 호스팅 뷰.
///
/// NSHostingView 는 마우스 위치를 "창 좌표 − 자기 원점" 으로만 계산하고 조상 뷰의 배율(NSScrollView
/// magnification)을 반영하지 않는다. 그래서 배율 51% 에서 누른 자리가 SwiftUI 안에서는 51% 지점으로
/// 잡혀 버튼이 눌리지 않았다. 여기서 이벤트 위치를 "배율을 뺀 자리" 로 바꿔 넘겨, SwiftUI 가 같은 계산을
/// 해도 실제로 누른 지점이 나오게 한다.
final class CanvasHostingView<Content: View>: NSHostingView<Content> {
    /// 이 뷰 좌표 1 이 창 좌표로 몇인지(캔버스 배율). 1 이면 고칠 필요가 없다.
    private var windowScale: CGFloat { convert(NSSize(width: 1, height: 1), to: nil).width }

    private func corrected(_ event: NSEvent) -> NSEvent {
        let scale = windowScale
        guard abs(scale - 1) > 0.001, event.window != nil else { return event }
        let local = convert(event.locationInWindow, from: nil)
        let origin = convert(NSPoint(x: bounds.minX, y: bounds.minY), to: nil)
        let u = CanvasInput.unscaledWindowPoint(localX: local.x - bounds.minX, localY: local.y - bounds.minY,
                                                originX: origin.x, originY: origin.y, flipped: isFlipped)
        let p = NSPoint(x: u.x, y: u.y)
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved:
            return NSEvent.mouseEvent(with: event.type, location: p, modifierFlags: event.modifierFlags,
                                      timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                      eventNumber: event.eventNumber, clickCount: event.clickCount,
                                      pressure: event.pressure) ?? event
        default:
            return event
        }
    }

    override func mouseDown(with event: NSEvent) { super.mouseDown(with: corrected(event)) }
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: corrected(event)) }
    override func mouseDragged(with event: NSEvent) { super.mouseDragged(with: corrected(event)) }
    override func rightMouseDown(with event: NSEvent) { super.rightMouseDown(with: corrected(event)) }
    override func rightMouseUp(with event: NSEvent) { super.rightMouseUp(with: corrected(event)) }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: corrected(event)) }
    override func otherMouseDown(with event: NSEvent) { super.otherMouseDown(with: corrected(event)) }
    override func otherMouseUp(with event: NSEvent) { super.otherMouseUp(with: corrected(event)) }
}
