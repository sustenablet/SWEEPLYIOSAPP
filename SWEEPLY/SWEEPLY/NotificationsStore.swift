import Foundation
import Supabase
import Observation

@Observable
final class NotificationsStore {
    var notifications: [AppNotification] = []
    var lastError: String? = nil
    private var isLoaded = false

    func load(isAuthenticated: Bool, userId: UUID?) async {
        guard isAuthenticated, let userId = userId, let client = SupabaseManager.shared else {
            // Load mock notifications if not authenticated/configured
            notifications = MockData.notifications.sorted { $0.timestamp > $1.timestamp }
            return
        }

        let previousIds = Set(notifications.map(\.id))

        do {
            let fetched: [RemoteNotification] = try await client.database
                .from("notifications")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.notifications = fetched.map { remote in
                AppNotification(
                    id: remote.id,
                    title: remote.title,
                    message: remote.message,
                    kind: AppNotification.Kind(rawValue: remote.kind) ?? .system,
                    timestamp: remote.createdAt,
                    isRead: remote.isRead,
                    jobId: remote.jobId,
                    invoiceId: remote.invoiceId
                )
            }
            self.isLoaded = true
            self.lastError = nil

            // Fire a local banner for any genuinely new unread notification
            let newUnread = self.notifications.filter { !$0.isRead && !previousIds.contains($0.id) }
            for n in newUnread {
                NotificationManager.shared.fireInstantBanner(title: n.title, body: n.message)
            }

            // If the table is empty (e.g. new user), pre-populate locally with a welcome message
            if notifications.isEmpty {
                notifications = [
                    AppNotification(
                        id: UUID(),
                        title: "Welcome to Sweeply",
                        message: "You're all set — job reminders, invoice alerts, and schedule updates will appear here.",
                        kind: .system,
                        timestamp: Date(),
                        isRead: false
                    )
                ]
            }
        } catch {
            print("Failed to fetch notifications: \(error)")
            self.lastError = "Failed to synchronize notifications."
            if !isLoaded {
                notifications = MockData.notifications
            }
        }
    }

    func markAsRead(id: UUID, isAuthenticated: Bool) async {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = true
        }

        guard isAuthenticated, let client = SupabaseManager.shared else { return }
        
        do {
            try await client.database
                .from("notifications")
                .update(["is_read": true])
                .eq("id", value: id)
                .execute()
        } catch {
            print("Failed to mark notification as read: \(error)")
        }
    }

    func markAsUnread(id: UUID, isAuthenticated: Bool) async {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = false
        }

        guard isAuthenticated, let client = SupabaseManager.shared else { return }
        
        do {
            try await client.database
                .from("notifications")
                .update(["is_read": false])
                .eq("id", value: id)
                .execute()
        } catch {
            print("Failed to mark notification as unread: \(error)")
        }
    }

    func markAllAsRead(userId: UUID?) async {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        guard let userId = userId, let client = SupabaseManager.shared else { return }
        do {
            try await client.database
                .from("notifications")
                .update(["is_read": true])
                .eq("user_id", value: userId)
                .execute()
        } catch {
            print("Failed to mark all notifications as read: \(error)")
        }
    }

    func delete(id: UUID) async {
        notifications.removeAll(where: { $0.id == id })
        guard let client = SupabaseManager.shared else { return }
        do {
            try await client.database
                .from("notifications")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            print("Failed to delete notification: \(error)")
        }
    }
}

// MARK: - Models

struct RemoteNotification: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let title: String
    let message: String
    let kind: String
    let isRead: Bool
    let createdAt: Date
    let jobId: UUID?
    let invoiceId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case message
        case kind
        case isRead = "is_read"
        case createdAt = "created_at"
        case jobId = "job_id"
        case invoiceId = "invoice_id"
    }
}

struct AppNotification: Identifiable {
    enum Kind: String, Codable {
        case schedule
        case jobs
        case billing
        case profile
        case system
        case team
    }

    let id: UUID
    let title: String
    let message: String
    let kind: Kind
    let timestamp: Date
    var isRead: Bool = false
    var jobId: UUID? = nil
    var invoiceId: UUID? = nil
}
