import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(AppSession.self) private var session
    @Environment(NotificationManager.self) private var notificationManager

    @State private var selectedTab: NotificationTab = .all
    
    enum NotificationTab: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case schedule = "Schedule"
        case billing = "Billing"
    }

    private var unreadCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
    }

    private var filteredNotifications: [AppNotification] {
        switch selectedTab {
        case .all:
            return notificationsStore.notifications
        case .unread:
            return notificationsStore.notifications.filter { !$0.isRead }
        case .schedule:
            return notificationsStore.notifications.filter { $0.kind == .schedule }
        case .billing:
            return notificationsStore.notifications.filter { $0.kind == .billing }
        }
    }
    
    private var sortedNotifications: [AppNotification] {
        filteredNotifications.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                Divider()
                
                // Content
                if sortedNotifications.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if unreadCount > 0 {
                        Button {
                            Task { 
                                await notificationsStore.markAllAsRead(userId: session.userId) 
                            }
                        } label: {
                            Text("Clear")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
            .refreshable {
                await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(NotificationTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tabLabel(tab))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(6)
        .background(Color.sweeplySurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
        .padding(.horizontal, 20)
    }
    
    private func tabLabel(_ tab: NotificationTab) -> String {
        switch tab {
        case .all:
            return "All"
        case .unread:
            return unreadCount > 0 ? "Unread (\(unreadCount))" : "Unread"
        case .schedule:
            return "Schedule"
        case .billing:
            return "Billing"
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(sortedNotifications) { notification in
                    NotificationRow(
                        notification: notification,
                        onMarkRead: {
                            Task {
                                await notificationsStore.markAsRead(
                                    id: notification.id,
                                    isAuthenticated: session.isAuthenticated
                                )
                            }
                        },
                        onMarkUnread: {
                            Task {
                                await notificationsStore.markAsUnread(
                                    id: notification.id,
                                    isAuthenticated: session.isAuthenticated
                                )
                            }
                        },
                        onDelete: {
                            Task {
                                await notificationsStore.delete(id: notification.id)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptyMessage
        )
    }
    
    private var emptyIcon: String {
        switch selectedTab {
        case .all: return "bell.slash"
        case .unread: return "envelope.open"
        case .schedule: return "calendar.badge.exclamationmark"
        case .billing: return "creditcard.slash"
        }
    }
    
    private var emptyTitle: String {
        switch selectedTab {
        case .all: return "No notifications"
        case .unread: return "All caught up"
        case .schedule: return "No schedule updates"
        case .billing: return "No billing activity"
        }
    }
    
    private var emptyMessage: String {
        switch selectedTab {
        case .all: return "You're up to date. New notifications will appear here."
        case .unread: return "You've read everything. Check back later for updates."
        case .schedule: return "No schedule changes or updates at the moment."
        case .billing: return "No invoice or payment activity to show."
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onDelete: () -> Void

    private var kindIcon: String {
        switch notification.kind {
        case .schedule: return "calendar"
        case .billing:  return "creditcard"
        case .profile:  return "person.fill"
        case .system:   return "bell.fill"
        }
    }

    private var kindColor: Color {
        switch notification.kind {
        case .schedule: return Color.sweeplyNavy
        case .billing:  return Color.sweeplyAccent
        case .profile:  return Color.sweeplyTextSub
        case .system:   return Color.sweeplyBorder
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left accent bar
            Rectangle()
                .fill(notification.isRead ? Color.clear : kindColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 4)
                .clipShape(Capsule())

            // Kind icon in colored circle
            ZStack {
                Circle()
                    .fill(kindColor.opacity(notification.isRead ? 0.08 : 0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: kindIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(kindColor.opacity(notification.isRead ? 0.45 : 1))
            }

            // Content
            VStack(alignment: .leading, spacing: 5) {
                // Title + timestamp on same line
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.isRead ? .medium : .semibold))
                        .foregroundStyle(Color.sweeplyNavy.opacity(notification.isRead ? 0.55 : 1))
                        .lineLimit(2)

                    Spacer()

                    Text(notification.timestamp.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                        .lineLimit(1)

                    if !notification.isRead {
                        Circle()
                            .fill(kindColor)
                            .frame(width: 7, height: 7)
                    }
                }

                Text(notification.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(notification.isRead ? 0.55 : 1))
                    .lineLimit(2)

                // Actions row
                HStack(spacing: 12) {
                    Spacer()
                    if !notification.isRead {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onMarkRead()
                        } label: {
                            Text("Mark read")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(kindColor)
                        }
                    }
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background {
            Color.sweeplySurface
                .overlay {
                    if !notification.isRead {
                        kindColor.opacity(0.03)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(notification.isRead ? Color.sweeplyBorder : kindColor.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !notification.isRead {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onMarkRead()
            }
        }
        .contextMenu {
            if notification.isRead {
                Button {
                    onMarkUnread()
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
            } else {
                Button {
                    onMarkRead()
                } label: {
                    Label("Mark as Read", systemImage: "checkmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

    }

}

#Preview {
    NotificationsView()
        .environment(NotificationsStore())
        .environment(AppSession())
}
