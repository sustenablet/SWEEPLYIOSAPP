import SwiftUI
import Supabase
import UIKit

// MARK: - AppDelegate for shortcut item handling

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        UserDefaults.standard.set(shortcutItem.type, forKey: "pendingShortcut")
        completionHandler(true)
    }
}

@main
struct SWEEPLYApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appSession    = AppSession()
    @State private var clientsStore  = ClientsStore()
    @State private var jobsStore     = JobsStore()
    @State private var invoicesStore = InvoicesStore()
    @State private var profileStore  = ProfileStore()
    @State private var notificationsStore = NotificationsStore()
    @State private var notificationManager = NotificationManager.shared

    @AppStorage("pendingShortcut") private var pendingShortcut: String = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
                .environment(clientsStore)
                .environment(jobsStore)
                .environment(invoicesStore)
                .environment(profileStore)
                .environment(notificationsStore)
                .environment(notificationManager)
                .onAppear {
                    notificationManager.checkAuthorizationStatus()
                    registerQuickActions()
                }
                .onOpenURL { url in
                    SupabaseManager.shared?.auth.handle(url)
                }
        }
    }

    private func registerQuickActions() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: "com.sweeply.newjob",
                localizedTitle: "New Job",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "briefcase.fill")
            ),
            UIApplicationShortcutItem(
                type: "com.sweeply.ai",
                localizedTitle: "AI Assistant",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "sparkles")
            ),
            UIApplicationShortcutItem(
                type: "com.sweeply.schedule",
                localizedTitle: "Today's Schedule",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "calendar")
            )
        ]
    }
}
