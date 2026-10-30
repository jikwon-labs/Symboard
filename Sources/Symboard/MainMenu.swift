import AppKit
import SymboardCore

enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("About Symboard"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide Symboard"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("Quit Symboard"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File"))
        fileMenu.addItem(withTitle: L("New Terminal..."), action: #selector(MainWindowController.newTerminalMenu(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: L("New Workspace..."), action: #selector(MainWindowController.newWorkspace(_:)), keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L("View"))
        viewMenu.addItem(withTitle: L("Zoom In"), action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
        viewMenu.addItem(withTitle: L("Zoom Out"), action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: L("Actual Size"), action: #selector(MainWindowController.zoomReset(_:)), keyEquivalent: "0")
        // Cmd+1~9 는 콘솔 이동에 쓰므로 Zoom to Fit 은 Cmd+Shift+1. 실제 키 처리는 창 키 감시(키 코드)가 한다.
        let fit = viewMenu.addItem(withTitle: L("Zoom to Fit"), action: #selector(MainWindowController.zoomToFit(_:)), keyEquivalent: "1")
        fit.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        let nextConsole = viewMenu.addItem(withTitle: L("Next Console"), action: #selector(MainWindowController.nextConsole(_:)), keyEquivalent: "\t")
        nextConsole.keyEquivalentModifierMask = [.control]
        let prevConsole = viewMenu.addItem(withTitle: L("Previous Console"), action: #selector(MainWindowController.previousConsole(_:)), keyEquivalent: "\t")
        prevConsole.keyEquivalentModifierMask = [.control, .shift]
        let goItem = viewMenu.addItem(withTitle: L("Go to Console"), action: nil, keyEquivalent: "")
        let goMenu = NSMenu(title: L("Go to Console"))
        for i in 1...9 {
            let it = goMenu.addItem(withTitle: L("Console %d", i), action: #selector(MainWindowController.goToConsoleMenu(_:)), keyEquivalent: "\(i)")
            it.tag = i
        }
        goItem.submenu = goMenu
        viewMenu.addItem(.separator())
        let next = viewMenu.addItem(withTitle: L("Next Workspace"), action: #selector(MainWindowController.nextWorkspace(_:)), keyEquivalent: "]")
        next.keyEquivalentModifierMask = [.command, .shift]
        let prev = viewMenu.addItem(withTitle: L("Previous Workspace"), action: #selector(MainWindowController.previousWorkspace(_:)), keyEquivalent: "[")
        prev.keyEquivalentModifierMask = [.command, .shift]
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
