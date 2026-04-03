import SwiftUI

struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore

    @State private var jobs: [Job]         = MockData.makeJobs()
    @State private var invoices: [Invoice] = MockData.makeInvoices()

    private let profile = MockData.profile
    @State private var appeared        = false
    @State private var showProfileMenu = false
    @State private var showPlaybook    = true
    @State private var playbookDone: [Bool] = Array(repeating: false, count: 4)

    // MARK: - Derived

    private var initials: String {
        profile.fullName
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
    }

    private var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            ?? DateInterval(start: Date(), end: Date().addingTimeInterval(86400 * 7))
    }

    private var todayJobs: [Job] {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        return jobs.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    private var weekEarned: Double {
        jobs
            .filter { $0.date >= weekInterval.start && $0.date < weekInterval.end && $0.status == .completed }
            .reduce(0) { $0 + $1.price }
    }

    private var weekJobsDone: Int {
        jobs.filter { $0.date >= weekInterval.start && $0.date < weekInterval.end && $0.status == .completed }.count
    }

    private var totalClients: Int { max(clientsStore.clients.count, MockData.clients.count) }

    private var scheduledCount: Int { jobs.filter { $0.status == .scheduled }.count }

    private var todayRemaining: Int {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        return jobs.filter {
            $0.date >= start && $0.date < end &&
            ($0.status == .scheduled || $0.status == .inProgress)
        }.count
    }

    private var outstandingTotal: Double {
        invoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
    }

    private var outstandingInvoices: [Invoice] {
        invoices
            .filter { $0.status != .paid }
            .sorted { a, b in
                if a.status == .overdue && b.status != .overdue { return true }
                if b.status == .overdue && a.status != .overdue { return false }
                return a.dueDate < b.dueDate
            }
    }

    private var allPlaybookDone: Bool { playbookDone.allSatisfy { $0 } }
    private var playbookDoneCount: Int { playbookDone.filter { $0 }.count }

    private var longDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ───────────────────────────────────────
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                Divider()

                // ── Revenue hero ─────────────────────────────────
                revenueHero
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)

                Divider()

                // ── 4-column stats strip ─────────────────────────
                statsStrip
                    .padding(.vertical, 20)

                Divider()

                // ── Get started checklist ────────────────────────
                if showPlaybook && !allPlaybookDone {
                    playbookSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    Divider()
                }

                // ── Today's schedule ─────────────────────────────
                scheduleSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                // ── Outstanding invoices ──────────────────────────
                if !outstandingInvoices.isEmpty {
                    Divider()
                    outstandingSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { appeared = true }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .confirmationDialog("", isPresented: $showProfileMenu, titleVisibility: .hidden) {
            Button("Settings") {}
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
        } message: {
            Text("\(profile.fullName) · \(profile.businessName)")
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(longDate)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(profile.businessName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Button { showProfileMenu = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 36, height: 36)
                    Text(initials)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Revenue Hero

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REVENUE THIS WEEK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            Text(weekEarned.currency)
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .tracking(-1.5)

            if weekJobsDone > 0 {
                Text("\(weekJobsDone) job\(weekJobsDone == 1 ? "" : "s") completed")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            } else {
                Text("No completed jobs yet this week")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            StatColumn(value: "\(totalClients)", label: "Clients")
            stripDivider
            StatColumn(value: "\(scheduledCount)", label: "Scheduled")
            stripDivider
            StatColumn(value: "\(todayRemaining)", label: "Today")
            stripDivider
            StatColumn(value: outstandingTotal.currency, label: "Outstanding")
        }
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // MARK: - Playbook

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("GET STARTED")
                Spacer()
                Text("\(playbookDoneCount) of 4")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showPlaybook = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }

            VStack(spacing: 14) {
                playbookRow(0, "Add your first client")
                playbookRow(1, "Schedule your first job")
                playbookRow(2, "Send your first invoice")
                playbookRow(3, "Complete your business profile")
            }
        }
    }

    @ViewBuilder
    private func playbookRow(_ index: Int, _ title: String) -> some View {
        let done = playbookDone[index]
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                playbookDone[index].toggle()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if done {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(done ? Color.sweeplyTextSub : Color.primary)
                    .strikethrough(done, color: Color.sweeplyTextSub)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("TODAY")
                Spacer()
                if !todayJobs.isEmpty {
                    Text("\(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            if todayJobs.isEmpty {
                Text("Nothing scheduled for today.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayJobs.enumerated()), id: \.element.id) { idx, job in
                        DashJobRow(job: job)
                        if idx < todayJobs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Outstanding Section

    private var outstandingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("OUTSTANDING")
                Spacer()
                Text(outstandingTotal.currency)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            VStack(spacing: 0) {
                ForEach(Array(outstandingInvoices.prefix(4).enumerated()), id: \.element.id) { idx, inv in
                    DashInvoiceRow(invoice: inv)
                    if idx < min(outstandingInvoices.count, 4) - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.sweeplyTextSub)
            .tracking(0.8)
    }
}

// MARK: - Stat Column

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dashboard Job Row

private struct DashJobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            // Time
            VStack(alignment: .trailing, spacing: 1) {
                Text(timeStr)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Text(amPm)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 36, alignment: .trailing)

            // Status dot
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(job.clientName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(job.price.currency)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                }
                Text("\(job.serviceType.rawValue) · \(durationStr) · \(job.address)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 13)
    }

    private var dotColor: Color {
        switch job.status {
        case .scheduled:  return Color(white: 0.75)
        case .inProgress: return Color.sweeplyAccent
        case .completed:  return Color.sweeplyAccent
        case .cancelled:  return Color.sweeplyDestructive
        }
    }
    private var timeStr: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: job.date)
    }
    private var amPm: String {
        let f = DateFormatter(); f.dateFormat = "a"; return f.string(from: job.date).uppercased()
    }
    private var durationStr: String {
        let h = Int(job.duration)
        let m = Int((job.duration - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Dashboard Invoice Row

private struct DashInvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(dueDateText)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        invoice.status == .overdue ? Color.sweeplyDestructive : Color.sweeplyTextSub
                    )
            }
            Spacer()
            HStack(spacing: 10) {
                Text(invoice.amount.currency)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                InvoiceStatusBadge(status: invoice.status)
            }
        }
        .padding(.vertical, 13)
    }

    private var dueDateText: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let ds = f.string(from: invoice.dueDate)
        switch invoice.status {
        case .overdue: return "Overdue · \(ds)"
        case .unpaid:  return "Due \(ds)"
        case .paid:    return "Paid \(ds)"
        }
    }
}

// MARK: - Global shared components
// These are used across multiple screens — keep in DashboardView.swift.

struct InvoiceStatusBadge: View {
    let status: InvoiceStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(labelColor)
            .tracking(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(labelColor.opacity(0.10))
            .clipShape(Capsule())
    }

    private var labelColor: Color {
        switch status {
        case .paid:    return Color.sweeplyAccent
        case .unpaid:  return Color.sweeplyTextSub
        case .overdue: return Color.sweeplyDestructive
        }
    }
}

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(labelColor)
            .tracking(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(labelColor.opacity(0.10))
            .clipShape(Capsule())
    }

    private var labelColor: Color {
        switch status {
        case .scheduled:  return Color.sweeplyTextSub
        case .inProgress: return Color.primary
        case .completed:  return Color.sweeplyAccent
        case .cancelled:  return Color.sweeplyDestructive
        }
    }
}

// MARK: - Currency extension

extension Double {
    var currency: String {
        let f = NumberFormatter()
        f.numberStyle           = .currency
        f.currencyCode          = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}

#Preview {
    DashboardView()
        .environment(AppSession())
        .environment(ClientsStore())
}
