import AppKit
import UserNotifications

/// macOS notifications for finished turns and resource warnings.
/// Clicking a notification jumps to the session it's about.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Permission { case unknown, allowed, denied }

    @Published private(set) var permission: Permission = .unknown
    var onOpenSession: ((String) -> Void)?

    /// UNUserNotificationCenter needs a real app bundle (not `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    func start() {
        center?.delegate = self
        refreshPermission()
    }

    func requestPermissionIfNeeded() {
        guard let center else { return }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                if status == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in self.permission = granted ? .allowed : .denied }
                    }
                } else {
                    self.permission = status == .denied ? .denied : .allowed
                }
            }
        }
    }

    func refreshPermission() {
        center?.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self.permission = status == .notDetermined ? .unknown : status == .denied ? .denied : .allowed
            }
        }
    }

    func post(identifier: String, title: String, body: String, sessionId: String, sound: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["sessionId": sessionId]
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "io.github.yentur.ClaudeDeck"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        Task { @MainActor in
            if let sessionId { self.onOpenSession?(sessionId) }
            completionHandler()
        }
    }
}
