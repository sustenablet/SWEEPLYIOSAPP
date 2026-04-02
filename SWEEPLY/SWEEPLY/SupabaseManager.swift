import Foundation
import Supabase

/// Loads `SupabaseConfig.plist` from the app bundle (copy from `SupabaseConfig.example.plist`, add URL + anon key from Project Settings → API).
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
            assertionFailure("SupabaseConfig.plist missing or invalid. Add SUPABASE_URL and SUPABASE_ANON_KEY.")
            return nil
        }
        return (url, anon)
    }()

    static let shared: SupabaseClient? = {
        guard let config else { return nil }
        return SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }()

    static var isConfigured: Bool { shared != nil }
}
