import SwiftUI
import Supabase

@main
struct SWEEPLYApp: App {
    @State private var appSession    = AppSession()
    @State private var clientsStore  = ClientsStore()
    @State private var jobsStore     = JobsStore()
    @State private var invoicesStore = InvoicesStore()
    @State private var profileStore  = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appSession)
                .environment(clientsStore)
                .environment(jobsStore)
                .environment(invoicesStore)
                .environment(profileStore)
                .onOpenURL { url in
                    SupabaseManager.shared?.auth.handle(url)
                }
        }
    }
}
