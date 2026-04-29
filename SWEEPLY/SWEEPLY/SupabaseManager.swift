import Foundation
import Supabase

/// Loads `SupabaseConfig.plist` from the app bundle (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
enum SupabaseManager {
    private static let config: (url: URL, anonKey: String)? = {
        guard let plistURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let urlString = dict["SUPABASE_URL"],
              let anon = dict["SUPABASE_ANON_KEY"],
              let url = URL(string: urlString),
              !urlString.isEmpty,
              !anon.isEmpty
        else {
            #if DEBUG
            print("[SupabaseManager] SupabaseConfig.plist missing or invalid - running in offline mode")
            #endif
            return nil
        }
        return (url, anon)
    }()

    static let shared: SupabaseClient? = {
        guard let config else { return nil }
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                redirectToURL: URL(string: "sweeply://auth-callback")
            )
        )
        return SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: options
        )
    }()

    static var isConfigured: Bool { shared != nil }
}
