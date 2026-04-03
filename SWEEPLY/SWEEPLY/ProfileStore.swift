import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class ProfileStore {
    var profile: UserProfile?
    var isLoading = false
    var lastError: String?

    func clear() {
        profile = nil
        lastError = nil
    }

    func load(userId: UUID) async {
        guard let client = SupabaseManager.shared else {
            profile = MockData.profile
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let row: ProfileRow = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            profile = row.toUserProfile(id: userId)
        } catch {
            // Profile may not exist yet (trigger handles creation on sign-up).
            // Fall back to a blank profile with the userId so the user can fill it in.
            profile = UserProfile(
                id: userId,
                fullName: "",
                businessName: "",
                email: "",
                phone: "",
                settings: AppSettings()
            )
            lastError = nil // not a hard error
        }
    }

    func save(_ updated: UserProfile, userId: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            profile = updated
            return true
        }
        lastError = nil
        do {
            let settingsData = try JSONEncoder().encode(updated.settings)
            let settingsString = String(data: settingsData, encoding: .utf8) ?? "{}"
            
            let row = ProfileRowUpsert(
                id: userId,
                fullName: updated.fullName,
                businessName: updated.businessName,
                email: updated.email,
                phone: updated.phone,
                settings_json: settingsString
            )
            let refreshed: ProfileRow = try await client
                .from("profiles")
                .upsert(row, onConflict: "id")
                .select()
                .single()
                .execute()
                .value
            profile = refreshed.toUserProfile(id: userId)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

// MARK: - DTOs

private struct ProfileRow: Decodable {
    let fullName: String?
    let businessName: String?
    let email: String?
    let phone: String?
    let settings_json: String?

    enum CodingKeys: String, CodingKey {
        case fullName     = "full_name"
        case businessName = "business_name"
        case email
        case phone
        case settings_json
    }

    func toUserProfile(id: UUID) -> UserProfile {
        let settings: AppSettings
        if let jsonString = settings_json,
           let data = jsonString.data(using: .utf8) {
            settings = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
        } else {
            settings = AppSettings()
        }
        
        return UserProfile(
            id: id,
            fullName: fullName ?? "",
            businessName: businessName ?? "",
            email: email ?? "",
            phone: phone ?? "",
            settings: settings
        )
    }
}

private struct ProfileRowUpsert: Encodable {
    let id: UUID
    let fullName: String
    let businessName: String
    let email: String
    let phone: String
    let settings_json: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName     = "full_name"
        case businessName = "business_name"
        case email
        case phone
        case settings_json
    }
}
