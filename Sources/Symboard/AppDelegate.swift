import AppKit
import SymboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var windowController: MainWindowController!
    var debugBridge: DebugBridge?
    /// App Nap 을 막는다. 창이 가려져도 상태 판정·루프 타이머가 계속 돌아야 한다.
    private var activity: NSObjectProtocol?
    private var retargetMonitor: Any?

    @MainActor
    static func retargetScroll(_ e: NSEvent) -> Bool {
        let p = e.locationInWindow
        guard let w = NSApp.orderedWindows.first(where: { $0.isVisible && $0.frame.contains(p) }),
              let content = w.contentView else { return false }
        let wp = w.convertPoint(fromScreen: p)
        guard let v = content.hitTest(content.superview?.convert(wp, from: nil) ?? wp) else { return false }
        v.scrollWheel(with: e)
        return true
    }

    @MainActor
    static func retarget(_ e: NSEvent) -> NSEvent? {
        let p = e.locationInWindow // 창이 없으면 화면 좌표
        let wins = NSApp.orderedWindows.filter { $0.isVisible && $0.frame.contains(p) }
        guard let w = wins.first else { return nil }
        return NSEvent.mouseEvent(with: e.type, location: w.convertPoint(fromScreen: p), modifierFlags: e.modifierFlags,
                                  timestamp: e.timestamp, windowNumber: w.windowNumber, context: nil,
                                  eventNumber: e.eventNumber, clickCount: max(e.clickCount, 1), pressure: e.pressure)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                          reason: "Monitoring agent terminals")
        model = AppModel(store: StateStore(directory: StateStore.defaultDirectory))
        MainMenu.install()
        windowController = MainWindowController(model: model)
        windowController.showWindow(nil)
        debugBridge = DebugBridge(controller: windowController, home: model.store.directory)
        NSApp.activate(ignoringOtherApps: true)
        // 창이 없는 마우스 이벤트(일부 자동 입력 도구의 끌기)는 화면 좌표로 온다. 그 자리의 우리 창으로 다시 겨눈다.
        // 실제 마우스 이벤트는 늘 창을 달고 오므로 영향이 없다.
        retargetMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                                                      .rightMouseDown, .rightMouseUp, .scrollWheel]) { e in
            guard e.window == nil else { return e }
            if e.type == .scrollWheel {
                // 넘겨줄 창을 찾았으면 원래(창 없는) 이벤트는 버린다.
                return MainActor.assumeIsolated { Self.retargetScroll(e) } ? nil : e
            }
            return MainActor.assumeIsolated { Self.retarget(e) } ?? e
        }
    }

    /// 창을 닫아도 콘솔은 계속 돈다(Cmd+Q 로 끝낸다). Dock 아이콘을 누르면 창을 다시 연다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.showWindow(nil); windowController?.window?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.captureViewports()
        model?.saveNow()
        model?.sessions.terminateAll()
    }
}
