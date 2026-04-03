import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(AppSession.self) private var session

    @State private var filterUnread = false


    private var unreadCount: Int {
        notificationsStore.notifications.filter { !$0.isRead }.count
    }

    private var filteredNotifications: [AppNotification] {
        if filterUnread {
            return notificationsStore.notifications.filter { !$0.isRead }
        }
        return notificationsStore.notifications
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard

                    HStack {
                        Picker("Filter", selection: $filterUnread) {
                            Text("All").tag(false)
                            Text("Unread (\(unreadCount))").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        
                        Spacer()
                    }

                    if filteredNotifications.isEmpty {
                        emptyState

                    } else {
                        VStack(spacing: 12) {
                            ForEach(filteredNotifications) { notification in
                                NotificationCard(notification: notification)
                                    .onTapGesture {
                                        Task {
                                            await notificationsStore.markAsRead(id: notification.id, isAuthenticated: session.isAuthenticated)
                                        }
                                    }
                                    .contextMenu {
                                        if !notification.isRead {
                                            Button("Mark as Read") {
                                                Task { await notificationsStore.markAsRead(id: notification.id, isAuthenticated: session.isAuthenticated) }
                                            }
                                        }
                                        Button(role: .destructive) {
                                            Task { await notificationsStore.delete(id: notification.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if unreadCount > 0 {
                        Button("Mark all read") { 
                            Task { await notificationsStore.markAllAsRead(userId: session.userId) }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
            .refreshable {
                await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
            }
        }
    }

    private var summaryCard: some View {
        SectionCard {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy.opacity(0.1))
                        .frame(width: 52, height: 52)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unreadCount) active update\(unreadCount == 1 ? "" : "s")")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Billing, scheduling, and account signals from your live app data.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                Spacer()
            }
        }
    }

    private var emptyState: some View {
        SectionCard {
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                Text("No notifications right now")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Your schedule, invoices, and profile are all quiet at the moment.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }
}


private struct NotificationCard: View {
    let notification: AppNotification

    var body: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accentColor)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(notification.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        if !notification.isRead {
                            Circle()
                                .fill(Color.sweeplyDestructive)
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                        }
                        Spacer()
                        Text(notification.timestamp.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }

                    Text(notification.message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(notification.isRead ? 0.6 : 1.0)
    }

    private var iconName: String {
        switch notification.kind {
        case .schedule:
            return "calendar"
        case .billing:
            return "creditcard"
        case .profile:
            return "building.2"
        case .system:
            return "sparkles"
        }
    }

    private var accentColor: Color {
        switch notification.kind {
        case .schedule:
            return .sweeplyNavy
        case .billing:
            return .sweeplyDestructive
        case .profile:
            return .sweeplyAccent
        case .system:
            return .blue
        }
    }
}
