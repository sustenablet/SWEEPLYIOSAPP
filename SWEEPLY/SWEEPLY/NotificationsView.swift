import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(AppSession.self) private var session

    @State private var showDeleteAll = false
    
    private var unreadCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
    }

    private var sortedNotifications: [AppNotification] {
        notificationsStore.notifications.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Stats
                    if !notificationsStore.notifications.isEmpty {
                        statsHeader
                    }

                    // Notifications List
                    if notificationsStore.notifications.isEmpty {
                        emptyState
                    } else {
                        notificationsList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if unreadCount > 0 {
                        Button("Mark all read") { 
                            Task { 
                                await notificationsStore.markAllAsRead(userId: session.userId) 
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
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
            .confirmationDialog("Delete All Notifications", isPresented: $showDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    Task {
                        for notification in notificationsStore.notifications {
                            await notificationsStore.delete(id: notification.id)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all notifications. This action cannot be undone.")
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        SectionCard {
            HStack(spacing: 16) {
                // Unread count
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unreadCount)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("unread")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                
                Rectangle()
                    .fill(Color.sweeplyBorder)
                    .frame(width: 1, height: 40)
                
                // Total count
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(notificationsStore.notifications.count)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("total")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                
                Spacer()
                
                // Bell icon
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        VStack(spacing: 12) {
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
                    onDelete: {
                        Task {
                            await notificationsStore.delete(id: notification.id)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        SectionCard {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "bell.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                }
                
                VStack(spacing: 6) {
                    Text("No notifications")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    
                    Text("You're all caught up! Check back later for updates about your jobs, invoices, and account.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onMarkRead: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(notification.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        if !notification.isRead {
                            Circle()
                                .fill(Color.sweeplyAccent)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(notification.message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(2)
                    
                    HStack {
                        Text(notification.timestamp.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        
                        Spacer()
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            if !notification.isRead {
                                Button {
                                    onMarkRead()
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                            }
                            
                            Button {
                                onDelete()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.sweeplyDestructive)
                            }
                        }
                    }
                }
            }
        }
        .opacity(notification.isRead ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !notification.isRead {
                onMarkRead()
            }
        }
    }

    private var iconName: String {
        switch notification.kind {
        case .schedule:
            return "calendar"
        case .billing:
            return "dollarsign.circle"
        case .profile:
            return "person.circle"
        case .system:
            return "sparkles"
        }
    }

    private var accentColor: Color {
        switch notification.kind {
        case .schedule:
            return .sweeplyNavy
        case .billing:
            return .sweeplyAccent
        case .profile:
            return .blue
        case .system:
            return .purple
        }
    }
}

#Preview {
    NotificationsView()
        .environment(NotificationsStore())
        .environment(AppSession())
}
