import SwiftUI
import Supabase

@main
struct SWEEPLYApp: App {
    @State private var appSession = AppSession()
    @State private var clientsStore = ClientsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
                .environment(clientsStore)
                .onOpenURL { url in
                    SupabaseManager.shared?.auth.handle(url)
                }
        }
    }
}
