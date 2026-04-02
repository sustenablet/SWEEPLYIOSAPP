import SwiftUI
import Supabase

@main
struct SWEEPLYApp: App {
    @State private var appSession = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
                .onOpenURL { url in
                    SupabaseManager.shared?.auth.handle(url)
                }
        }
    }
}
