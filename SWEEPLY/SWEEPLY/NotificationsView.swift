import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationsStore.self) private var notificationsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session

    @AppStorage("hasSeededNotificationsV2") private var hasSeededNotifications = false
    @State private var selectedTab: NotificationTab = .all
    @State private var selectedJobId: UUID? = nil
    @State private var selectedInvoiceId: UUID? = nil
    @State private var showJobDetail: Bool = false
    @State private var showInvoiceDetail: Bool = false
    
    enum NotificationTab: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case jobs = "Jobs"
        case billing = "Billing"
        case team = "Team"
        case schedule = "Schedule"
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
        case .jobs:
            return notificationsStore.notifications.filter { $0.kind == .jobs }
        case .billing:
            return notificationsStore.notifications.filter { $0.kind == .billing }
        case .team:
            return notificationsStore.notifications.filter { $0.kind == .team }
        case .schedule:
            return notificationsStore.notifications.filter { $0.kind == .schedule }
        }
    }
    
    private var sortedNotifications: [AppNotification] {
        filteredNotifications.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                Divider()
                
                if sortedNotifications.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Notifications".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if unreadCount > 0 {
                        Button {
                            Task { 
                                await notificationsStore.markAllAsRead(userId: session.userId) 
                            }
                        } label: {
                            Text("Clear".translated())
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
            .onAppear {
                Task {
                    await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
                    if !hasSeededNotifications, let userId = session.userId {
                        await notificationsStore.seedIfNeeded(
                            jobs: jobsStore.jobs,
                            invoices: invoicesStore.invoices,
                            userId: userId
                        )
                        hasSeededNotifications = true
                    }
                }
            }
            .refreshable {
                await notificationsStore.load(isAuthenticated: session.isAuthenticated, userId: session.userId)
            }
            .sheet(isPresented: $showJobDetail) {
                if let jobId = selectedJobId {
                    NavigationStack {
                        JobDetailView(jobId: jobId)
                    }
                    .environment(jobsStore)
                    .environment(clientsStore)
                    .environment(session)
                }
            }
            .sheet(isPresented: $showInvoiceDetail) {
                if let invoiceId = selectedInvoiceId {
                    NavigationStack {
                        InvoiceDetailView(invoiceId: invoiceId)
                    }
                    .environment(invoicesStore)
                    .environment(clientsStore)
                    .environment(session)
                }
            }
        }
    }

    private func handleNotificationTap(_ notification: AppNotification) {
        if !notification.isRead {
            Task {
                await notificationsStore.markAsRead(id: notification.id, isAuthenticated: session.isAuthenticated)
            }
        }
        
        if let jobId = notification.jobId {
            selectedJobId = jobId
            showJobDetail = true
        } else if let invoiceId = notification.invoiceId {
            selectedInvoiceId = invoiceId
            showInvoiceDetail = true
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(NotificationTab.allCases, id: \.self) { tab in
                    tabPill(tab)
                }
            }
            .padding(4)
            .background(Color.sweeplyBackground)
            .clipShape(Capsule())
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func tabPill(_ tab: NotificationTab) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tabIcon(tab))
                    .font(.system(size: 11, weight: .medium))
                Text(tabLabel(tab))
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
            .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func tabIcon(_ tab: NotificationTab) -> String {
        switch tab {
        case .all:      return "bell.fill"
        case .unread:   return "envelope.open.fill"
        case .jobs:     return "briefcase.fill"
        case .billing:  return "creditcard.fill"
        case .team:     return "person.2.fill"
        case .schedule: return "calendar"
        }
    }
    
    private func tabCount(_ tab: NotificationTab) -> Int? {
        switch tab {
        case .unread: return unreadCount > 0 ? unreadCount : nil
        default: return nil
        }
    }
    



private func tabLabel(_ tab: NotificationTab) -> String {
    switch tab {
    case .all:      return "All"
    case .unread:   return unreadCount > 0 ? "Unread (\(unreadCount))" : "Unread"
    case .jobs:     return "Jobs".translated()
    case .billing:  return "Billing".translated()
    case .team:     return "Team".translated()
    case .schedule: return "Schedule".translated()
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
                        },
                        onTap: {
                            handleNotificationTap(notification)
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
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 60)
                
                ZStack {
                    Circle()
                        .fill(kindColorForTab(selectedTab).opacity(0.1))
                        .frame(width: 88, height: 88)
                    Image(systemName: emptyIcon)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(kindColorForTab(selectedTab))
                }
                
                VStack(spacing: 8) {
                    Text(emptyTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                    Text(emptyMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func kindColorForTab(_ tab: NotificationTab) -> Color {
        switch tab {
        case .all:      return Color.sweeplyTextSub
        case .unread:   return Color.sweeplyNavy
        case .jobs:     return Color.sweeplyAccent
        case .billing:  return Color.sweeplySuccess
        case .team:     return Color.sweeplyNavy
        case .schedule: return Color.sweeplyNavy
        }
    }

    private var emptyIcon: String {
        switch selectedTab {
        case .all:      return "bell.slash"
        case .unread:   return "envelope.open"
        case .jobs:     return "briefcase.fill"
        case .billing:  return "creditcard.slash"
        case .team:     return "person.2"
        case .schedule: return "calendar.badge.exclamationmark"
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .all:      return "No notifications".translated()
        case .unread:   return "All caught up".translated()
        case .jobs:     return "No job updates".translated()
        case .billing:  return "No billing activity".translated()
        case .team:     return "No team activity".translated()
        case .schedule: return "No schedule updates".translated()
        }
    }

    private var emptyMessage: String {
        switch selectedTab {
        case .all:      return "You're up to date. New notifications will appear here.".translated()
        case .unread:   return "You've read everything. Check back later for updates.".translated()
        case .jobs:     return "Check-ins, completions, and job assignments will appear here.".translated()
        case .billing:  return "Invoice due dates and payment confirmations will appear here.".translated()
        case .team:     return "Invite acceptances and team updates will appear here.".translated()
        case .schedule: return "No schedule changes or updates at the moment.".translated()
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: AppNotification
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    private var kindIcon: String {
        switch notification.kind {
        case .schedule: return "calendar"
        case .jobs:     return "briefcase.fill"
        case .billing:  return "creditcard"
        case .profile:  return "person.fill"
        case .system:   return "bell.fill"
        case .team:     return "person.2.fill"
        }
    }

    private var kindColor: Color {
        switch notification.kind {
        case .schedule: return Color.sweeplyNavy
        case .jobs:     return Color.sweeplyAccent
        case .billing:  return Color.sweeplySuccess
        case .profile:  return Color.sweeplyTextSub
        case .system:   return Color.sweeplyBorder
        case .team:     return Color.sweeplyNavy
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
                            Text("Mark read".translated())
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
            onTap()
        }
        .contextMenu {
            if notification.isRead {
                Button {
                    onMarkUnread()
                } label: {
                    Label("Mark as Unread".translated(), systemImage: "envelope.badge")
                }
            } else {
                Button {
                    onMarkRead()
                } label: {
                    Label("Mark as Read".translated(), systemImage: "checkmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete".translated(), systemImage: "trash")
            }
        }

    }

}

#Preview {
    NotificationsView()
        .environment(NotificationsStore())
        .environment(AppSession())
}
