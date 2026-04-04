import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(AppSession.self) private var session

    @State private var selectedFilter: NotificationFilter = .all
    @State private var isRefreshing = false
    
    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
    }

    private var unreadCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
    }

    private var filteredNotifications: [AppNotification] {
        switch selectedFilter {
        case .all:
            return notificationsStore.notifications
        case .unread:
            return notificationsStore.notifications.filter { !$0.isRead }
        }
    }
    
    private var groupedNotifications: [(String, [AppNotification])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotifications) { notification -> String in
            if calendar.isDateInToday(notification.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(notification.timestamp) {
                return "Yesterday"
            } else if let daysAgo = calendar.dateComponents([.day], from: notification.timestamp, to: Date()).day, daysAgo < 7 {
                return "This Week"
            } else {
                return "Earlier"
            }
        }
        return grouped.sorted { first, second in
            let order = ["Today", "Yesterday", "This Week", "Earlier"]
            return order.firstIndex(of: first.key) ?? 3 < order.firstIndex(of: second.key) ?? 3
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Summary
                notificationHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                
                Divider()
                
                // Filter Pills
                filterPills
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                Divider()
                
                // Notifications List
                if filteredNotifications.isEmpty {
                    emptyStateView
                } else {
                    notificationsList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                isRefreshing = true
                await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
                isRefreshing = false
            }
        }
    }

    // MARK: - Header

    private var notificationHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(unreadCount > 0 ? "\(unreadCount) unread" : "All caught up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                if unreadCount > 0 {
                    Text("Tap to view details")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                } else {
                    Text("You're up to date!")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            Spacer()
            
            if unreadCount > 0 {
                Button {
                    Task {
                        await notificationsStore.markAllAsRead(userId: session.userId)
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.sweeplyNavy.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        HStack(spacing: 10) {
            ForEach(NotificationFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                        
                        if filter == .unread && unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.sweeplyDestructive)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(selectedFilter == filter ? .white : Color.sweeplyNavy)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(selectedFilter == filter ? Color.sweeplyNavy : Color.sweeplySurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(selectedFilter == filter ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
                    )
                }
            }
            
            Spacer()
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(groupedNotifications, id: \.0) { section, notifications in
                    Section {
                        ForEach(notifications) { notification in
                            NotificationRow(
                                notification: notification,
                                onMarkRead: {
                                    Task {
                                        await notificationsStore.markAsRead(id: notification.id, isAuthenticated: session.isAuthenticated)
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await notificationsStore.delete(id: notification.id)
                                    }
                                }
                            )
                            
                            if notification.id != filteredNotifications.last?.id {
                                Divider()
                                    .padding(.leading, 74)
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.sweeplyBackground)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.sweeplyBackground)
                    .frame(width: 100, height: 100)
                Image(systemName: selectedFilter == .unread ? "bell.slash" : "bell")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text(selectedFilter == .unread ? "No unread notifications" : "No notifications")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                Text(selectedFilter == .unread 
                     ? "You've seen everything. Check back later for new updates."
                     : "Your notifications will appear here when you have schedule changes, invoice updates, and more.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onMarkRead: () -> Void
    let onDelete: () -> Void
    
    @State private var showActions = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineLimit(2)
                        
                        Text(notification.message)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    if !notification.isRead {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(notification.timestamp.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
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
                                .foregroundStyle(Color.sweeplyDestructive.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .opacity(notification.isRead ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !notification.isRead {
                onMarkRead()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !notification.isRead {
                Button {
                    onMarkRead()
                } label: {
                    Label("Read", systemImage: "checkmark.circle")
                }
                .tint(Color.sweeplyAccent)
            }
        }
    }

    private var iconName: String {
        switch notification.kind {
        case .schedule:
            return "calendar.badge.clock"
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
        .environment(ClientsStore())
        .environment(JobsStore())
        .environment(InvoicesStore())
        .environment(AppSession())
}
