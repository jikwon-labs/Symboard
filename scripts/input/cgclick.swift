// CGEvent 로 실제 마우스 클릭·끌기·키 입력을 보낸다. orca computer 가 접근성 판정 때문에 클릭을 거부하는 자리에서 쓴다.
// 사용: cgclick click X Y [count]   (Symboard 창 기준 포인트)
//       cgclick drag X1 Y1 X2 Y2
//       cgclick move X Y        (누르지 않고 마우스만 옮긴다. 커서 모양 시험용)
//       cgclick key CODE [cmd,opt,shift,ctrl]  (키 코드 하나를 수정 키와 함께)
//       cgclick keys LETTERS    (ABC 자판 자리의 실제 키 코드로 친다. 입력기를 거치므로 한글 입력 상태면 dkssud → 안녕)
// 같은 앱이 여러 개 떠 있으면 SYMBOARD_PID 로 시험 인스턴스를 고른다.
// 창 위치는 CGWindowList 에서 local.symboard.app 창을 찾아 더한다.
import AppKit
import CoreGraphics

func targetApp() -> NSRunningApplication? {
    if let s = ProcessInfo.processInfo.environment["SYMBOARD_PID"], let pid = pid_t(s) { return NSRunningApplication(processIdentifier: pid) }
    return NSRunningApplication.runningApplications(withBundleIdentifier: "local.symboard.app").first
}

func symboardWindowOrigin() -> CGPoint? {
    guard let app = targetApp(),
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    // 팝오버도 layer 0 창으로 잡히므로 가장 큰 창(본 창)을 기준으로 삼는다.
    var best: (area: CGFloat, origin: CGPoint)?
    for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat] {
            let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
            if area > (best?.area ?? 0) { best = (area, CGPoint(x: b["X"] ?? 0, y: b["Y"] ?? 0)) }
        }
    }
    return best?.origin
}

func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}

let args = CommandLine.arguments
if args.count >= 3, args[1] == "keys" {
    // orca type-text·press-key 는 글자를 바로 넣어 입력기(IME)를 거치지 않는다. 그래서 키 코드로 보낸다.
    let codes: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49]
    targetApp()?.activate()
    usleep(150_000)
    for ch in args[2] {
        guard let k = codes[ch] else { print("no key for \(ch)"); exit(2) }
        CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true)?.post(tap: .cghidEventTap); usleep(30_000)
        CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: false)?.post(tap: .cghidEventTap); usleep(60_000)
    }
    print("ok keys")
    exit(0)
}
if args.count >= 3, args[1] == "key" {
    // cgclick key CODE [cmd,opt,shift,ctrl] — 키 코드 하나를 수정 키와 함께. 예: key 123 opt (Option+←), key 51 cmd (Cmd+Backspace)
    // 수정 키도 실제 키(눌렀다 뗌)로 보낸다. 글자 키에 flags 만 달면 그 수정 키가 눌린 채로 남아 뒤 키에 붙었다.
    var flags: CGEventFlags = []
    var mods: [(CGKeyCode, CGEventFlags)] = []
    for m in (args.count > 3 ? args[3] : "").split(separator: ",") {
        switch m {
        case "cmd": mods.append((55, .maskCommand))
        case "opt": mods.append((58, .maskAlternate))
        case "shift": mods.append((56, .maskShift))
        case "ctrl": mods.append((59, .maskControl))
        default: break
        }
    }
    targetApp()?.activate()
    usleep(150_000)
    for (code, f) in mods {
        flags.insert(f)
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!; e.flags = flags
        e.post(tap: .cghidEventTap); usleep(30_000)
    }
    let k = CGKeyCode(args[2])!
    let down = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true)!; down.flags = flags
    let up = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: false)!; up.flags = flags
    down.post(tap: .cghidEventTap); usleep(40_000); up.post(tap: .cghidEventTap); usleep(40_000)
    for (code, f) in mods.reversed() {
        flags.remove(f)
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!; e.flags = flags
        e.post(tap: .cghidEventTap); usleep(30_000)
    }
    usleep(50_000)
    print("ok key \(k) \(args.count > 3 ? args[3] : "")")
    exit(0)
}
guard args.count >= 4, let o = symboardWindowOrigin() else { print("usage or window missing"); exit(2) }
targetApp()?.activate()
usleep(150_000)
let p = CGPoint(x: o.x + Double(args[2])!, y: o.y + Double(args[3])!)
switch args[1] {
case "click":
    let n = args.count > 4 ? Int(args[4])! : 1
    post(.mouseMoved, p); usleep(60_000)
    for i in 1...n {
        post(.leftMouseDown, p, clicks: Int64(i)); usleep(50_000)
        post(.leftMouseUp, p, clicks: Int64(i)); usleep(90_000)
    }
case "drag":
    let q = CGPoint(x: o.x + Double(args[4])!, y: o.y + Double(args[5])!)
    post(.mouseMoved, p); usleep(60_000)
    post(.leftMouseDown, p); usleep(120_000)
    for i in 1...20 {
        let t = Double(i) / 20
        post(.leftMouseDragged, CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)); usleep(25_000)
    }
    usleep(150_000)
    post(.leftMouseUp, q)
case "move":
    // 실제 마우스처럼 지금 자리에서 목표까지 여러 걸음의 mouseMoved 로 옮긴다.
    // (CGWarpMouseCursorPosition 은 뒤 0.25초 이벤트를 막고, 한 번의 이벤트로는 커서 갱신이 일어나지 않았다.)
    let src = CGEventSource(stateID: .hidSystemState)
    src?.localEventsSuppressionInterval = 0
    let from = CGEvent(source: nil)?.location ?? p
    for i in 1...12 {
        let t = Double(i) / 12
        let q = CGPoint(x: from.x + (p.x - from.x) * t, y: from.y + (p.y - from.y) * t)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: q, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(16_000)
    }
default: print("unknown"); exit(2)
}
print("ok \(args[1]) at \(p)")
