import Foundation
import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - 通知偏好与去重（对齐安卓 NotifyPrefs）

final class NotifyPrefs {
    static let shared = NotifyPrefs()

    private let defaults = UserDefaults.standard
    private let seenPrefix = "notify.seen."
    private let seenTTL: TimeInterval = 7 * 24 * 3600

    var enabled: Bool {
        get {
            if defaults.object(forKey: "notify.enabled") == nil { return true }
            return defaults.bool(forKey: "notify.enabled")
        }
        set { defaults.set(newValue, forKey: "notify.enabled") }
    }

    var dndEnabled: Bool {
        get {
            if defaults.object(forKey: "notify.dndEnabled") == nil { return true }
            return defaults.bool(forKey: "notify.dndEnabled")
        }
        set { defaults.set(newValue, forKey: "notify.dndEnabled") }
    }

    var dndStartMinute: Int {
        get { defaults.object(forKey: "notify.dndStart") as? Int ?? 22 * 60 }
        set { defaults.set(newValue, forKey: "notify.dndStart") }
    }

    var dndEndMinute: Int {
        get { defaults.object(forKey: "notify.dndEnd") as? Int ?? 8 * 60 }
        set { defaults.set(newValue, forKey: "notify.dndEnd") }
    }

    func inQuietHours(now: Date = Date()) -> Bool {
        guard dndEnabled else { return false }
        let start = dndStartMinute
        let end = dndEndMinute
        if start == end { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if start < end {
            return current >= start && current < end
        }
        return current >= start || current < end
    }

    func isSeen(_ eventId: String) -> Bool {
        defaults.object(forKey: seenPrefix + eventId) != nil
    }

    func markSeen(_ eventId: String, at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: seenPrefix + eventId)
    }

    func pruneSeen() {
        let expireAt = Date().timeIntervalSince1970 - seenTTL
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(seenPrefix) {
            let stamp = (value as? Double) ?? 0
            if stamp < expireAt {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - 事件与拉取

struct NotifyEvent {
    let id: String
    let category: String
    let title: String
    let body: String
    let route: String
    let refId: String
    let createdAt: String
    let level: String
}

enum NotifyRepository {
    /// 拉取 notify.feed 并弹本地通知。
    /// 去重：同一 event.id 7 天内只弹一次；免打扰期内不弹也不标记，解除后补发。
    @discardableResult
    static func poll() async -> Int {
        guard SessionStore.shared.hasToken else { return 0 }

        guard let data = try? await APIClient.shared.post("notify.feed") else { return 0 }
        let events = data.objects("events")
        var posted = 0

        for json in events {
            let id = json.str("id")
            if id.isEmpty || NotifyPrefs.shared.isSeen(id) { continue }

            let event = NotifyEvent(
                id: id,
                category: json.str("category"),
                title: json.str("title").isEmpty ? "门店助手" : json.str("title"),
                body: json.str("body"),
                route: json.str("route"),
                refId: json.str("refId"),
                createdAt: json.str("createdAt"),
                level: json.str("level")
            )

            if !NotifyPrefs.shared.enabled {
                NotifyPrefs.shared.markSeen(id)
                continue
            }
            if NotifyPrefs.shared.inQuietHours() {
                continue
            }

            NotificationPresenter.shared.present(event)
            NotifyPrefs.shared.markSeen(id)
            posted += 1
        }

        NotifyPrefs.shared.pruneSeen()
        return posted
    }
}

// MARK: - 本地通知展示

final class NotificationPresenter {
    static let shared = NotificationPresenter()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func present(_ event: NotifyEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.userInfo = [
            "route": event.route,
            "refId": event.refId,
            "eventId": event.id
        ]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - 前台轮询

final class NotifyPoller {
    static let shared = NotifyPoller()

    private var timer: Timer?

    func start() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        Task { _ = await NotifyRepository.poll() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { _ = await NotifyRepository.poll() }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - APNs 预埋接入点

protocol PushProvider {
    var enabled: Bool { get }
    func unregister() async
}

/// 默认关闭：当前无 APNs 证书 / Provisioning 权限，使用本地通知 + 周期拉取。
/// 接入步骤：
/// 1. 在 Apple Developer 为 Bundle ID 开启 Push Notifications 并下载描述文件；
/// 2. Xcode 增加 Push Notifications capability 与 aps-environment 授权；
/// 3. 将 enabled 改为 true，并在 AppDelegate 中上报 deviceToken；
/// 4. 服务端 push.register / push_send_apns 已完成对接位。
struct IOSPushProvider: PushProvider {
    var enabled: Bool { false }

    func unregister() async {}
}

enum PushRegistry {
    static var provider: PushProvider = IOSPushProvider()

    static func registerIfNeeded() {
        guard SessionStore.shared.hasToken else { return }
        guard provider.enabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func reportToken(_ token: String) {
        guard !token.isEmpty else { return }
        Task {
            _ = try? await APIClient.shared.post("push.register", [
                "platform": AppConfig.platform,
                "token": token,
                "deviceName": UIDevice.current.model,
                "appVersion": AppConfig.version
            ])
        }
    }

    static func unregister() async {
        guard provider.enabled else { return }
        _ = try? await APIClient.shared.post("push.unregister")
        await provider.unregister()
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var pendingRoute: String?

    private let backgroundTaskId = "com.tastien.storestaff.native.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationPresenter.shared.requestAuthorization()
        registerBackgroundTask()
        PushRegistry.registerIfNeeded()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundRefresh()
    }

    // MARK: 通知点击

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String ?? "home"
        AppDelegate.pendingRoute = route
        NotificationCenter.default.post(name: .appOpenRoute, object: nil, userInfo: ["route": route])
        completionHandler()
    }

    // MARK: APNs

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard PushRegistry.provider.enabled else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushRegistry.reportToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 未配置 APNs 时静默降级为本地通知。
    }

    // MARK: 后台刷新

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskId, using: nil) { task in
            Task {
                _ = await NotifyRepository.poll()
                self.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
