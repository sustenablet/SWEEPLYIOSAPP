import Foundation
import Supabase

/// Lightweight helper for inserting in-app notification records from any store.
/// Call with `await` — fires and forgets on failure.
/// Pass `userId` explicitly when available; omit to auto-resolve from the active Supabase auth session.
enum NotificationHelper {
    static func insert(
        userId: UUID? = nil,
        title: String,
        message: String,
        kind: String,
        jobId: UUID? = nil,
        invoiceId: UUID? = nil,
        isRead: Bool = false
    ) async {
        guard let client = SupabaseManager.shared else { return }
        let resolvedId = userId ?? client.auth.currentUser?.id
        guard let uid = resolvedId else { return }
        do {
            struct Payload: Encodable {
                let user_id: UUID
                let title: String
                let message: String
                let kind: String
                let job_id: UUID?
                let invoice_id: UUID?
                let is_read: Bool
            }
            let payload = Payload(
                user_id: uid,
                title: title,
                message: message,
                kind: kind,
                job_id: jobId,
                invoice_id: invoiceId,
                is_read: isRead
            )
            try await client
                .from("notifications")
                .insert(payload)
                .execute()
        } catch {
            print("NotificationHelper: failed to insert — \(error)")
        }
    }
}
