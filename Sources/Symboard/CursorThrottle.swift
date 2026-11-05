import AppKit
import ObjectiveC
import SymboardCore

/// 같은 커서를 프레임마다 다시 거는 것을 앱 전체에서 거른다(성능 점검 2차, SymboardCore `CursorDedupe`).
///
/// 커서를 거는 곳이 AppKit 커서 영역·추적 영역, SwiftTerm `cursorUpdate`, SwiftUI 등 여러 곳이라
/// 하나하나 고치지 않고 `NSCursor.set` 한 곳을 바꿔 끼운다.
enum CursorThrottle {
    /// 메인 스레드에서만 읽고 쓴다(NSCursor.set 은 메인에서만 불린다).
    nonisolated(unsafe) static var dedupe = CursorDedupe<ObjectIdentifier>()
    nonisolated(unsafe) private static var installed = false
    /// 실제로 건 횟수와 건너뛴 횟수(디버그 통로 "cursorStats").
    nonisolated(unsafe) static var applied = 0
    nonisolated(unsafe) static var skipped = 0

    @MainActor
    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.set)),
              let replacement = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.sym_dedupedSet)) else { return }
        installed = true
        method_exchangeImplementations(original, replacement)
        // 다른 앱으로 갔다 오면 커서가 바깥에서 바뀌었으므로 다음 한 번은 꼭 건다.
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in dedupe.reset() }
        }
    }
}

extension NSCursor {
    /// 바꿔 끼운 뒤에는 이 이름이 원래 `set` 을 가리킨다.
    @objc func sym_dedupedSet() {
        let skip = CursorThrottle.dedupe.shouldSkip(ObjectIdentifier(self), isCurrent: NSCursor.current === self,
                                                    now: ProcessInfo.processInfo.systemUptime)
        if skip {
            CursorThrottle.skipped &+= 1
            return
        }
        CursorThrottle.applied &+= 1
        sym_dedupedSet()
    }
}
