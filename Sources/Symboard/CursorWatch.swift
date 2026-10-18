import AppKit

/// 커서 시험용 기록. 화면 캡처에는 마우스 커서가 찍히지 않아서, `SYMBOARD_CURSORLOG=<파일>` 로 띄우면
/// 0.1초마다 마우스 아래 뷰와 `NSCursor.current` 를 보고 바뀔 때만 한 줄 적는다.
@MainActor
enum CursorWatch {
    private static var timer: Timer?
    private static var last = ""

    static func start(window: NSWindow) {
        guard timer == nil, let path = ProcessInfo.processInfo.environment["SYMBOARD_CURSORLOG"] else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window, let content = window.contentView else { return }
                let loc = window.mouseLocationOutsideOfEventStream
                let hit = content.hitTest(content.superview?.convert(loc, from: nil) ?? loc)
                var chain: [String] = []
                var v = hit
                while let cur = v, chain.count < 4 {
                    chain.append(String(describing: type(of: cur)).components(separatedBy: "<").first ?? "?")
                    v = cur.superview
                }
                let line = "pt=\(Int(loc.x)),\(Int(window.frame.height - loc.y)) cursor=\(name(NSCursor.current)) key=\(window.isKeyWindow) active=\(NSApp.isActive) rects=\(window.areCursorRectsEnabled) view=\(chain.joined(separator: "<"))"
                guard line != last else { return }
                last = line
                let stamped = "\(Date().timeIntervalSince1970) \(line)\n"
                if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close() }
                else { try? stamped.write(toFile: path, atomically: true, encoding: .utf8) }
            }
        }
    }

    static func name(_ c: NSCursor) -> String {
        let known: [(NSCursor, String)] = [(.arrow, "arrow"), (.iBeam, "iBeam"), (.openHand, "openHand"), (.closedHand, "closedHand"),
                                          (.crosshair, "crosshair"), (.pointingHand, "pointingHand"), (.resizeLeftRight, "resizeLR"),
                                          (.resizeUpDown, "resizeUD"), (.iBeamCursorForVerticalLayout, "iBeamV")]
        return known.first { $0.0 == c }?.1 ?? "other(\(c.hashValue))"
    }
}

/// 글 입력칸 위에서 I 모양 커서.
///
/// 원인(7차): SwiftUI 입력칸(`TextField`·`TextEditor`)은 AppKit 커서 사각형으로 I 커서를 거는데,
/// 그 위의 NSHostingView 가 자기 커서 갱신(cursorUpdate)으로 화살표를 다시 걸어 덮는다. 그래서 명령 바·
/// 오케스트레이터·칸반 카드 등 앱 안 SwiftUI 입력칸 어디에서도 커서가 바뀌지 않았다(기준본에서
/// `SYMBOARD_CURSORLOG` 로 확인: 입력칸 위에서도 `NSCursor.current` 가 arrow).
/// 입력칸 하나하나를 고치는 대신, 마우스가 움직일 때마다 AppKit hitTest(캔버스 배율도 맞게 계산한다)로
/// 마우스 아래가 편집 가능한 글 입력칸인지 보고, 맞으면 I 커서를 건다. 벗어나면 우리가 건 I 커서만 화살표로 돌린다
/// (노드 머리의 손 모양·터미널 I 커서처럼 다른 뷰가 건 커서는 건드리지 않는다).
@MainActor
enum TextCursor {
    private static var monitor: Any?
    private static var owning = false

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate, .leftMouseUp, .rightMouseUp, .scrollWheel]) { e in
            if let w = e.window {
                w.acceptsMouseMovedEvents = true
                // 이 이벤트로 호스팅 뷰가 커서를 고친 뒤에 판정해야 덮이지 않는다.
                DispatchQueue.main.async { MainActor.assumeIsolated { update(w) } }
            }
            return e
        }
        for w in NSApp.windows { w.acceptsMouseMovedEvents = true }
    }

    static func update(_ w: NSWindow) {
        // 누른 채 끄는 중(캔버스 closedHand, 글 고르기)에는 건드리지 않는다.
        guard NSEvent.pressedMouseButtons == 0, w.isVisible, let content = w.contentView else { return }
        let loc = w.mouseLocationOutsideOfEventStream
        guard let frame = content.superview, frame.bounds.contains(frame.convert(loc, from: nil)) else { return }
        let hit = content.hitTest(frame.convert(loc, from: nil))
        if isTextInput(hit) {
            if NSCursor.current != .iBeam { NSCursor.iBeam.set() }
            owning = true
        } else if owning {
            owning = false
            if NSCursor.current == .iBeam, !(hit.map(isTerminal) ?? false) { NSCursor.arrow.set() }
        }
    }

    /// 편집 가능한 글 입력칸(또는 그 안). 터미널은 스스로 커서를 다룬다.
    static func isTextInput(_ v: NSView?) -> Bool {
        var cur = v
        var depth = 0
        while let x = cur, depth < 4 {
            if isTerminal(x) { return false }
            if let t = x as? NSTextView { return t.isEditable }
            if let f = x as? NSTextField { return f.isEditable && f.isEnabled }
            cur = x.superview
            depth += 1
        }
        return false
    }

    static func isTerminal(_ v: NSView) -> Bool { v is SymTerminalView }
}
