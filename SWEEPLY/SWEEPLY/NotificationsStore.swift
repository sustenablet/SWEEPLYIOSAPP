import Foundation
import Supabase
import Observation

@Observable
final class NotificationsStore {
    var notifications: [AppNotification] = []
    var lastError: String? = nil
    private var isLoaded = false

    func load(isAuthenticated: Bool, userId: UUID?) async {
        guard isAuthenticated, let userId = userId, SupabaseManager.isConfigured else {
            // Load mock notifications if not authenticated/configured
            notifications = MockData.notifications.sorted { $0.timestamp > $1.timestamp }
            return
        }

        do {
            let fetched: [RemoteNotification] = try await SupabaseManager.client.database
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
                    isRead: remote.isRead
                )
            }
            self.isLoaded = true
            self.lastError = nil
            
            // If the table is empty (e.g. new user), let's pre-populate it with a welcome message locally
            if notifications.isEmpty {
                notifications = [
                    AppNotification(
                        id: UUID(),
                        title: "Welcome to Sweeply",
                        message: "Your backend notifications are now connected and fully working!",
                        kind: .system,
                        timestamp: Date(),
                        isRead: false
                    )
                ]
            }
        } catch {
            print("Failed to fetch notifications: \(error)")
            self.lastError = "Failed to synchronize notifications."
            // Fallback to local
            if !isLoaded {
                notifications = MockData.notifications
            }
        }
    }

    func markAsRead(id: UUID, isAuthenticated: Bool) async {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = true
        }

        guard isAuthenticated, SupabaseManager.isConfigured else { return }
        
        do {
            try await SupabaseManager.client.database
                .from("notifications")
                .update(["is_read": true])
                .eq("id", value: id)
                .execute()
        } catch {
            print("Failed to mark notification as read: \(error)")
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

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case message
        case kind
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

struct AppNotification: Identifiable {
    enum Kind: String, Codable {
        case schedule
        case billing
        case profile
        case system
    }

    let id: UUID
    let title: String
    let message: String
    let kind: Kind
    let timestamp: Date
    var isRead: Bool = false
}
