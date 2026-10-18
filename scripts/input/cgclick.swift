// CGEvent 로 실제 마우스 클릭·끌기·키 입력을 보낸다. orca computer 가 접근성 판정 때문에 클릭을 거부하는 자리에서 쓴다.
// 사용: cgclick click X Y [count]   (Symboard 창 기준 포인트)
//       cgclick drag X1 Y1 X2 Y2
// 창 위치는 CGWindowList 에서 local.symboard.app 창을 찾아 더한다.
import AppKit
import CoreGraphics

func symboardWindowOrigin() -> CGPoint? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.symboard.app").first,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat] { return CGPoint(x: b["X"] ?? 0, y: b["Y"] ?? 0) }
    }
    return nil
}

func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}

let args = CommandLine.arguments
guard args.count >= 4, let o = symboardWindowOrigin() else { print("usage or window missing"); exit(2) }
NSRunningApplication.runningApplications(withBundleIdentifier: "local.symboard.app").first?.activate()
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
default: print("unknown"); exit(2)
}
print("ok \(args[1]) at \(p)")
