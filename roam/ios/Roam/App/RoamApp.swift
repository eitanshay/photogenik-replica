import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct RoamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .environment(AppModel.shared.settings)
                .environment(Narrator.shared)
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await AppModel.shared.becameActive() } }
            if p == .background { Background.schedule() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.register()
        Background.register()
        // iOS relaunches the app in the background for region and significant-change events;
        // the location manager must exist before this method returns for them to be delivered.
        MainActor.assumeIsolated {
            AppModel.shared.bootstrap()
        }
        return true
    }

    // Show alerts even with the app open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["placeID"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            AppModel.shared.handleNotification(action: action, placeID: id)
        }
    }
}

/// Overnight prep while charging: refresh the Michelin data, place unresolved saves, write audio scripts.
enum Background {
    static let prepareID = "com.eitanshay.roam.prepare"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: prepareID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            schedule()
            let work = Task { @MainActor in
                await MichelinStore.shared.refreshIfStale()
                await AppModel.shared.resolvePending()
                await AppModel.shared.prepareScripts()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGProcessingTaskRequest(identifier: prepareID)
        req.requiresExternalPower = true
        req.requiresNetworkConnectivity = true
        req.earliestBeginDate = Date().addingTimeInterval(4 * 3_600)
        try? BGTaskScheduler.shared.submit(req)
    }
}
