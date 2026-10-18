import AppKit

// Finder·Dock 으로 띄워도 claude·codex 를 찾도록, 무엇보다 먼저 사용자 셸의 PATH 를 얻는다.
LoginEnvironment.bootstrap()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
