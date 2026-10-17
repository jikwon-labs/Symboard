import AppKit
import SymboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var windowController: MainWindowController!
    var debugBridge: DebugBridge?
    /// App Nap 을 막는다. 창이 가려져도 상태 판정·루프 타이머가 계속 돌아야 한다.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                          reason: "Monitoring agent terminals")
        model = AppModel(store: StateStore(directory: StateStore.defaultDirectory))
        MainMenu.install()
        windowController = MainWindowController(model: model)
        windowController.showWindow(nil)
        debugBridge = DebugBridge(controller: windowController, home: model.store.directory)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.captureViewports()
        model?.saveNow()
        model?.sessions.terminateAll()
    }
}
