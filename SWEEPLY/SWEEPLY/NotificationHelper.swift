import Foundation
import Supabase

/// Lightweight helper for inserting in-app notification records from any store.
/// Call with `await` — fires and forgets on failure.
enum NotificationHelper {
    static func insert(userId: UUID, title: String, message: String, kind: String) async {
        guard let client = SupabaseManager.shared else { return }
        do {
            struct Payload: Encodable {
                let user_id: UUID
                let title: String
                let message: String
                let kind: String
                let is_read: Bool
            }
            let payload = Payload(user_id: userId, title: title, message: message, kind: kind, is_read: false)
            try await client.database
                .from("notifications")
                .insert(payload)
                .execute()
        } catch {
            print("NotificationHelper: failed to insert — \(error)")
        }
    }
}
