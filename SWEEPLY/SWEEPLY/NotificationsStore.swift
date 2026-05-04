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
            let fetched: [RemoteNotification] = try await client
                .from("notifications")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(100)
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
            .filter { _ in true }
            self.isLoaded = true
            self.lastError = nil

            // Fire at most ONE banner per load — for the single most recent truly new notification
            // (created within the last 60 seconds to avoid re-firing historical unread items)
            let cutoff = Date().addingTimeInterval(-60)
            let newUnread = self.notifications.filter {
                !$0.isRead && !previousIds.contains($0.id) && $0.timestamp > cutoff
            }
            if let latest = newUnread.max(by: { $0.timestamp < $1.timestamp }) {
                NotificationManager.shared.fireInstantBanner(title: latest.title, body: latest.message)
                NotificationCenter.default.post(name: NSNotification.Name("NewNotificationsArrived"), object: nil)
            }

            // If the table is empty (new user), insert a persisted welcome notification
            if notifications.isEmpty {
                await NotificationHelper.insert(
                    userId: userId,
                    title: "Welcome to Sweeply",
                    message: "You're all set — job reminders and schedule updates will appear here.",
                    kind: "system"
                )
                // Reload to show the persisted welcome notification
                let welcomed: [RemoteNotification] = (try? await client
                    .from("notifications")
                    .select()
                    .eq("user_id", value: userId)
                    .order("created_at", ascending: false)
                    .limit(100)
                    .execute()
                    .value) ?? []
                self.notifications = welcomed.map { remote in
                    AppNotification(
                        id: remote.id, title: remote.title, message: remote.message,
                        kind: AppNotification.Kind(rawValue: remote.kind) ?? .system,
                        timestamp: remote.createdAt, isRead: remote.isRead,
                        jobId: remote.jobId, invoiceId: remote.invoiceId
                    )
                }
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
            try await client
                .from("notifications")
                .update(["is_read": true])
                .eq("user_id", value: userId)
                .execute()
        } catch {
            print("Failed to mark all notifications as read: \(error)")
        }
    }

    /// Backfills notifications from existing jobs/invoices on first launch.
    /// Only runs when the table is empty; inserts up to 10 completed jobs,
    /// 5 paid invoices, and any overdue invoices, then reloads from Supabase.
    func seedIfNeeded(jobs: [Job], invoices: [Invoice], userId: UUID) async {
        let isEmptyOrWelcome = notifications.isEmpty ||
            (notifications.count == 1 && notifications[0].title == "Welcome to Sweeply")
        guard isEmptyOrWelcome else { return }

        var seeded = false

        // Seed as already-read so they appear in history but never fire push banners
        let recentCompleted = jobs
            .filter { $0.status == .completed }
            .sorted { $0.date > $1.date }
            .prefix(10)
        for job in recentCompleted {
            await NotificationHelper.insert(
                userId: userId,
                title: "Job Completed",
                message: "\(job.serviceType.rawValue) for \(job.clientName) — marked complete",
                kind: "jobs",
                isRead: true
            )
            seeded = true
        }

        let recentPaid = invoices
            .filter { $0.status == .paid }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
        for invoice in recentPaid {
            await NotificationHelper.insert(
                userId: userId,
                title: "Invoice Paid",
                message: "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.total.currency) received",
                kind: "billing",
                isRead: true
            )
            seeded = true
        }

        let overdue = invoices.filter { $0.status == .overdue }.prefix(3)
        for invoice in overdue {
            await NotificationHelper.insert(
                userId: userId,
                title: "Invoice Overdue",
                message: "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.total.currency) overdue",
                kind: "billing",
                isRead: true
            )
            seeded = true
        }

        if seeded {
            await load(isAuthenticated: true, userId: userId)
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
