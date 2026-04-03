import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self) private var profileStore

    private var profile: UserProfile? {
        profileStore.profile
    }

    private var notifications: [AppNotification] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        let todayJobs = jobsStore.jobs
            .filter { $0.date >= startOfToday && $0.date < endOfToday }
            .sorted { $0.date < $1.date }

        let overdueInvoices = invoicesStore.invoices
            .filter { $0.status == .overdue }
            .sorted { $0.dueDate < $1.dueDate }

        let upcomingInvoices = invoicesStore.invoices
            .filter { $0.status == .unpaid && $0.dueDate >= startOfToday }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(2)

        let needsBusinessProfile = profile.map {
            $0.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false

        var items: [AppNotification] = []

        if !todayJobs.isEmpty {
            let firstJob = todayJobs[0]
            items.append(
                AppNotification(
                    title: "Today's route is live",
                    message: "\(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s") scheduled. First stop: \(firstJob.clientName) at \(firstJob.date.formatted(date: .omitted, time: .shortened)).",
                    kind: .schedule,
                    timestamp: firstJob.date
                )
            )
        }

        if !overdueInvoices.isEmpty {
            let balance = overdueInvoices.reduce(0) { $0 + $1.amount }
            items.append(
                AppNotification(
                    title: "Overdue invoices need follow-up",
                    message: "\(overdueInvoices.count) overdue invoice\(overdueInvoices.count == 1 ? "" : "s") totaling \(balance.currency).",
                    kind: .billing,
                    timestamp: overdueInvoices[0].dueDate
                )
            )
        }

        for invoice in upcomingInvoices {
            items.append(
                AppNotification(
                    title: "Invoice due soon",
                    message: "\(invoice.clientName) invoice \(invoice.invoiceNumber) is due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted)).",
                    kind: .billing,
                    timestamp: invoice.dueDate
                )
            )
        }

        if needsBusinessProfile {
            items.append(
                AppNotification(
                    title: "Finish your business profile",
                    message: "Add your business name and phone number in Settings so clients see complete business details.",
                    kind: .profile,
                    timestamp: now
                )
            )
        }

        if clientsStore.clients.isEmpty {
            items.append(
                AppNotification(
                    title: "Add your first client",
                    message: "You are connected, but your client list is still empty. Start by creating your first customer record.",
                    kind: .system,
                    timestamp: now
                )
            )
        }

        return items.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if notifications.isEmpty {
                        emptyState
                    } else {
                        summaryCard

                        VStack(spacing: 12) {
                            ForEach(notifications) { notification in
                                NotificationCard(notification: notification)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sweeplyNavy)
                }
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
                    Text("\(notifications.count) active update\(notifications.count == 1 ? "" : "s")")
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

private struct AppNotification: Identifiable {
    enum Kind {
        case schedule
        case billing
        case profile
        case system
    }

    let id = UUID()
    let title: String
    let message: String
    let kind: Kind
    let timestamp: Date
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
