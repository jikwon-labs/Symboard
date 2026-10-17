import AppKit
import SymboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var windowController: MainWindowController!
    var debugBridge: DebugBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
