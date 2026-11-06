import AppKit
import UserNotifications

/// 앱이 앞에 없을 때 macOS 알림 센터에 띄우는 알림. 맡긴 콘솔이 끝났을 때 쓴다(WorkerReporter).
/// 앱이 앞에 있으면 오른쪽 위 알림만 쓰고 여기로는 보내지 않는다.
/// .app 번들로 돌 때만 쓴다(번들 없이 띄운 실행 파일에서 UNUserNotificationCenter 를 부르면 죽는다).
@MainActor
final class SystemNotices: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotices()
    private var asked = false

    private var available: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// 누르면 그 콘솔로 간다.
    func post(title: String, body: String, nodeID: UUID) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            c.userInfo = ["node": nodeID.uuidString]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if asked { send(); return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { send() }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["node"] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let raw, let id = UUID(uuidString: raw) { MainWindowController.current?.focus(nodeID: id) }
            completionHandler()
        }
    }

    /// 앱이 앞에 있을 때 온 알림은 띄우지 않는다(오른쪽 위 알림이 있다).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
