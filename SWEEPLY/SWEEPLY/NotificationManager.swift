import Foundation
import UserNotifications
import Observation

enum DeepLink: Equatable {
    case job(UUID)
    case invoice(UUID)
    case schedule
    case finances
}

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    var isAuthorized = false
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var pendingDeepLink: DeepLink? = nil

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("[NotificationManager] Authorization error: \(error)")
            }
            DispatchQueue.main.async {
                self.isAuthorized = granted
                self.checkAuthorizationStatus()
                if granted { self.scheduleWeeklyEarningsSummary() }
            }
        }
        registerNotificationCategories()
    }

    func registerNotificationCategories() {
        let markCompleteAction = UNNotificationAction(
            identifier: "MARK_JOB_COMPLETE",
            title: "Mark Complete".translated(),
            options: [.authenticationRequired]
        )
        let viewJobAction = UNNotificationAction(
            identifier: "VIEW_JOB",
            title: "View Job".translated(),
            options: [.foreground]
        )
        let jobCategory = UNNotificationCategory(
            identifier: "JOB_REMINDER",
            actions: [markCompleteAction, viewJobAction],
            intentIdentifiers: [],
            options: []
        )

        let markPaidAction = UNNotificationAction(
            identifier: "MARK_INVOICE_PAID",
            title: "Mark as Paid".translated(),
            options: [.authenticationRequired]
        )
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_INVOICE_LATER",
            title: "Remind in 3 days".translated(),
            options: []
        )
        let invoiceCategory = UNNotificationCategory(
            identifier: "INVOICE_REMINDER",
            actions: [markPaidAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([jobCategory, invoiceCategory])
    }

    // MARK: - Instant Banner

    private var lastBannerFiredAt: Date?

    func fireInstantBanner(title: String, body: String) {
        guard isAuthorized else { return }
        // Rate limit: skip if a banner fired within the last 3 seconds
        if let last = lastBannerFiredAt, Date().timeIntervalSince(last) < 3 { return }
        lastBannerFiredAt = Date()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "instant-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationManager] fireInstantBanner error: \(error)") }
        }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Sweeply Notifications".translated()
        content.body = "Everything is working — you'll get reminders for jobs and invoices here.".translated()
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationManager] sendTestNotification error: \(error)") }
        }
    }

    // MARK: - Per-Job Countdown (1 hour before — always individual)

    /// Schedules only the 60-minute countdown for a specific job.
    /// Daily morning and evening digests are handled separately by `refreshDailyDigests(jobs:)`.
    func scheduleJobReminder(for job: Job) {
        guard job.status == .scheduled || job.status == .inProgress else { return }
        let fireDate = job.date.addingTimeInterval(-3600)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Starting in 1 Hour".translated()
        var body = "%@ for %@ at %@".translated(with: job.serviceType.rawValue.translated(), job.clientName, shortTime(job.date))
        if !job.address.isEmpty { body += " — \(cityFromAddress(job.address))" }
        content.body = body
        content.sound = .default
        content.userInfo = ["jobId": job.id.uuidString]
        content.categoryIdentifier = "JOB_REMINDER"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        let request = UNNotificationRequest(identifier: "\(job.id)-hour", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        Task {
            await NotificationHelper.insert(
                title: "Job Reminder".translated(),
                message: "%@ for %@ starts at %@".translated(with: job.serviceType.rawValue.translated(), job.clientName, shortTime(job.date)),
                kind: "schedule"
            )
        }
    }

    /// Rebuilds the grouped invoice reminder banner for each due day.
    /// This mirrors the job digest pattern so multiple invoices due the same day
    /// produce one banner instead of a separate notification per invoice.
    func refreshInvoiceDigests(invoices: [Invoice]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let digestIds = requests
                .filter { $0.identifier.hasPrefix("invoice-today-") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: digestIds)

            let today = Calendar.current.startOfDay(for: Date())
            let upcoming = invoices.filter {
                $0.status == .unpaid &&
                Calendar.current.startOfDay(for: $0.dueDate) >= today
            }

            let grouped = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.dueDate) }
            for (day, dayInvoices) in grouped {
                let sorted = dayInvoices.sorted { $0.dueDate < $1.dueDate }
                self.scheduleInvoiceDayDigest(for: day, invoices: sorted)
            }
        }
    }

    func cancelJobReminders(for jobId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(jobId)-hour"]
        )
    }

    // MARK: - Daily Digest (grouped per-day morning + evening)

    /// Call after any jobs mutation (insert, update, delete, status change).
    /// Cancels all existing daily digest notifications and rebuilds them from the current job list.
    func refreshDailyDigests(jobs: [Job]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let digestIds = requests
                .filter {
                    $0.identifier.hasPrefix("daily-morning-") ||
                    $0.identifier.hasPrefix("evening-preview-")
                }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: digestIds)

            let today = Calendar.current.startOfDay(for: Date())
            let upcoming = jobs.filter {
                ($0.status == .scheduled || $0.status == .inProgress) &&
                Calendar.current.startOfDay(for: $0.date) >= today
            }

            let grouped = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
            for (day, dayJobs) in grouped {
                let sorted = dayJobs.sorted { $0.date < $1.date }
                self.scheduleMorningDigest(for: day, jobs: sorted)
                self.scheduleEveningPreview(for: day, jobs: sorted)
            }

            // Slow week warning: if no jobs at all this week, push on Monday 9am
            self.refreshSlowWeekWarning(upcomingThisWeek: upcoming)
        }
    }

    private func refreshSlowWeekWarning(upcomingThisWeek: [Job]) {
        let identifier = "slow-week-warning"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard upcomingThisWeek.isEmpty else { return }
        guard isAuthorized else { return }

        let calendar = Calendar.current
        let now = Date()
        // Find next Monday at 9am
        var comp = DateComponents()
        comp.weekday = 2; comp.hour = 9; comp.minute = 0
        guard let nextMonday9am = calendar.nextDate(after: now, matching: comp, matchingPolicy: .nextTime),
              nextMonday9am > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Quiet Week Ahead".translated()
        content.body = "No jobs scheduled this week. Great time to reach out to clients!".translated()
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: nextMonday9am.timeIntervalSinceNow, repeats: false
        )
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger),
            withCompletionHandler: nil
        )
    }

    // MARK: - Morning Digest (7am day-of)

    private func scheduleMorningDigest(for day: Date, jobs: [Job]) {
        guard !jobs.isEmpty else { return }
        let dateId = dayIdentifier(for: day)

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = "JOB_REMINDER"

        switch jobs.count {
        case 1:
            let job = jobs[0]
            content.title = "Job Today".translated()
            content.body = "%@ for %@ at %@".translated(with: job.serviceType.rawValue.translated(), job.clientName, shortTime(job.date))
            if !job.address.isEmpty { content.body += " — \(cityFromAddress(job.address))" }
            content.userInfo = ["jobId": job.id.uuidString]
        case 2:
            content.title = "2 Jobs Today".translated()
            content.body = "%@ at %@, then %@ at %@".translated(with: jobs[0].clientName, shortTime(jobs[0].date), jobs[1].clientName, shortTime(jobs[1].date))
            content.userInfo = ["openTab": "schedule", "digestDate": dateId]
        default:
            let first = jobs[0]
            content.title = "%d Jobs Today".translated(with: jobs.count)
            content.body = "Starting at %@ with %@ — tap to see your full schedule".translated(with: shortTime(first.date), first.clientName)
            content.userInfo = ["openTab": "schedule", "digestDate": dateId]
        }

        var comp = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comp.hour = 7; comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        let request = UNNotificationRequest(identifier: "daily-morning-\(dateId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Evening Preview (6pm day before)

    private func scheduleEveningPreview(for day: Date, jobs: [Job]) {
        guard !jobs.isEmpty else { return }
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return }
        // Don't schedule if the evening window has already passed
        guard dayBefore >= Calendar.current.startOfDay(for: Date()) else { return }

        let dateId = dayIdentifier(for: day)

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = "JOB_REMINDER"

        switch jobs.count {
        case 1:
            let job = jobs[0]
            content.title = "Tomorrow: 1 Job".translated()
            content.body = "%@ for %@ at %@".translated(with: job.serviceType.rawValue.translated(), job.clientName, shortTime(job.date))
            content.userInfo = ["jobId": job.id.uuidString]
        case 2:
            content.title = "Tomorrow: 2 Jobs".translated()
            content.body = "%@ at %@ and %@ at %@".translated(with: jobs[0].clientName, shortTime(jobs[0].date), jobs[1].clientName, shortTime(jobs[1].date))
            content.userInfo = ["openTab": "schedule", "digestDate": dateId]
        default:
            let first = jobs[0]
            let last = jobs[jobs.count - 1]
            content.title = "Tomorrow: %d Jobs".translated(with: jobs.count)
            content.body = "%@–%@ — starting with %@".translated(with: shortTime(first.date), shortTime(last.date), first.clientName)
            content.userInfo = ["openTab": "schedule", "digestDate": dateId]
        }

        var comp = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        comp.hour = 18; comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        let request = UNNotificationRequest(identifier: "evening-preview-\(dateId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Weekly Earnings Digest (every Monday 9am)

    /// Call after loading invoices. Rebuilds the Monday 9am summary with actual last-week revenue.
    func refreshWeeklyEarningsSummary(weeklyRevenue: Double) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["weekly-earnings-summary"]
        )
        let content = UNMutableNotificationContent()
        content.title = "Weekly Earnings Summary".translated()
        content.body = weeklyRevenue > 0
            ? "You earned %@ last week. Open Finance for your full breakdown.".translated(with: weeklyRevenue.currency)
            : "No earnings recorded last week. Open Finance to review your invoices.".translated()
        content.sound = .default

        var comp = DateComponents()
        comp.weekday = 2  // Monday (1 = Sun)
        comp.hour = 9
        comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "weekly-earnings-summary", content: content, trigger: trigger),
            withCompletionHandler: nil
        )
    }

    /// Legacy one-time call after authorization — schedules with generic body until revenue data loads.
    func scheduleWeeklyEarningsSummary() {
        refreshWeeklyEarningsSummary(weeklyRevenue: 0)
    }

    // MARK: - Pay Day Reminders (owner)

    /// Rebuilds per-member pay-day reminders from the current job list.
    /// Fires 1 hour after the last job ends on days when a member is due to be paid.
    func schedulePayReminders(jobs: [Job], members: [TeamMember]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let toRemove = requests
                .filter { $0.identifier.hasPrefix("pay-reminder-") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: toRemove)

            let today = Calendar.current.startOfDay(for: Date())
            let upcoming = jobs.filter {
                ($0.status == .scheduled || $0.status == .inProgress) &&
                Calendar.current.startOfDay(for: $0.date) >= today
            }
            let grouped = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }

            for (day, dayJobs) in grouped {
                let weekday = Calendar.current.component(.weekday, from: day)

                // Members who are due to be paid on this day
                let payDueMembers = members.filter { member in
                    guard member.payRateEnabled && member.payRateAmount > 0 else { return false }
                    switch member.payRateType {
                    case .perDay:  return true
                    case .perWeek: return member.payDayOfWeek == weekday
                    default:       return false
                    }
                }
                guard !payDueMembers.isEmpty else { continue }

                // Find the last job end time: start + duration hours
                let lastEndTime = dayJobs.map { $0.date.addingTimeInterval($0.duration * 3600) }.max()
                guard let endTime = lastEndTime else { continue }
                let reminderTime = endTime.addingTimeInterval(3600)  // 1 hour after last job ends
                guard reminderTime > Date() else { continue }

                for member in payDueMembers {
                    let content = UNMutableNotificationContent()
                    content.title = "Time to Pay %@".translated(with: member.name)
                    content.body = "%@ is owed %@ today. Open Sweeply to record the payment.".translated(with: member.name, member.payRateAmount.currency)
                    content.sound = .default

                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: reminderTime.timeIntervalSinceNow,
                        repeats: false
                    )
                    let request = UNNotificationRequest(
                        identifier: "pay-reminder-\(self.dayIdentifier(for: day))-\(member.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request, withCompletionHandler: nil)
                }
            }
        }
    }

    // MARK: - Member Pay Day Push Notification

    /// Schedules a recurring local push for the cleaner on their own pay day.
    /// Called from CleanerRootView when the member view loads.
    func scheduleMemberPayDayNotification(membership: TeamMembership) {
        let identifier = "member-payday-\(membership.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard membership.payRateEnabled && membership.payRateAmount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "It's Pay Day!".translated()
        content.body = "Your %@ from %@ should be processed today.".translated(with: membership.payRateAmount.currency, membership.businessName)
        content.sound = .default

        switch membership.payRateType {
        case .perDay:
            var comp = DateComponents()
            comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger),
                withCompletionHandler: nil
            )
        case .perWeek:
            guard let weekday = membership.payDayOfWeek else { return }
            var comp = DateComponents()
            comp.weekday = weekday; comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger),
                withCompletionHandler: nil
            )
        default:
            break
        }
    }

    // MARK: - Invoice Reminders

    func scheduleInvoiceReminder(for invoice: Invoice) {
        guard invoice.status == .unpaid else { return }

        // 3 days before due at 9am
        if let threeDayBefore = Calendar.current.date(byAdding: .day, value: -3, to: invoice.dueDate),
           threeDayBefore > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Invoice due in 3 days".translated()
            content.body = "%@ for %@ — %@ due on %@".translated(
                with: invoice.invoiceNumber,
                invoice.clientName,
                invoice.subtotal.currency,
                shortDate(invoice.dueDate)
            )
            content.sound = .default
            content.userInfo = ["invoiceId": invoice.id.uuidString]
            content.categoryIdentifier = "INVOICE_REMINDER"

            var comp = Calendar.current.dateComponents([.year, .month, .day], from: threeDayBefore)
            comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: "\(invoice.id)-due3day", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

            Task {
                await NotificationHelper.insert(
                    title: "Invoice due in 3 days".translated(),
                    message: "%@ for %@ — %@ due on %@".translated(
                        with: invoice.invoiceNumber,
                        invoice.clientName,
                        invoice.subtotal.currency,
                        shortDate(invoice.dueDate)
                    ),
                    kind: "billing"
                )
            }
        }

        // 1 day overdue at 9am — first escalation
        if let dayAfterDue = Calendar.current.date(byAdding: .day, value: 1, to: invoice.dueDate),
           dayAfterDue > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Invoice overdue".translated()
            content.body = "%@ for %@ was due yesterday — %@ still unpaid".translated(
                with: invoice.invoiceNumber,
                invoice.clientName,
                invoice.subtotal.currency
            )
            content.sound = .defaultCritical
            content.userInfo = ["invoiceId": invoice.id.uuidString]
            content.categoryIdentifier = "INVOICE_REMINDER"

            var comp = Calendar.current.dateComponents([.year, .month, .day], from: dayAfterDue)
            comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: "\(invoice.id)-overdue", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

            Task {
                await NotificationHelper.insert(
                    title: "Invoice overdue".translated(),
                    message: "%@ for %@ — %@ still unpaid".translated(
                        with: invoice.invoiceNumber,
                        invoice.clientName,
                        invoice.subtotal.currency
                    ),
                    kind: "billing"
                )
            }
        }

        // 7 days overdue at 9am — second escalation
        if let sevenDaysAfterDue = Calendar.current.date(byAdding: .day, value: 7, to: invoice.dueDate),
           sevenDaysAfterDue > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Invoice seriously overdue".translated()
            content.body = "%@ for %@ is 7 days overdue — %@ pending".translated(
                with: invoice.invoiceNumber,
                invoice.clientName,
                invoice.subtotal.currency
            )
            content.sound = .defaultCritical
            content.userInfo = ["invoiceId": invoice.id.uuidString]
            content.categoryIdentifier = "INVOICE_REMINDER"

            var comp = Calendar.current.dateComponents([.year, .month, .day], from: sevenDaysAfterDue)
            comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: "\(invoice.id)-overdue7day", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

            Task {
                await NotificationHelper.insert(
                    title: "Invoice seriously overdue".translated(),
                    message: "%@ for %@ — %@ — 7 days overdue".translated(
                        with: invoice.invoiceNumber,
                        invoice.clientName,
                        invoice.subtotal.currency
                    ),
                    kind: "billing"
                )
            }
        }
    }

    func cancelInvoiceReminders(for invoiceId: UUID) {
        let ids = ["\(invoiceId)-due3day", "\(invoiceId)-dueToday", "\(invoiceId)-overdue", "\(invoiceId)-overdue7day"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Helpers

    /// Extracts just the city from a full address ("123 Main St, Miami, FL 33101" → "Miami")
    private func cityFromAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count >= 2 ? parts[1] : (parts.first ?? address)
    }

    private func scheduleInvoiceDayDigest(for day: Date, invoices: [Invoice]) {
        guard !invoices.isEmpty else { return }
        let dateId = dayIdentifier(for: day)

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = "INVOICE_REMINDER"

        switch invoices.count {
        case 1:
            let invoice = invoices[0]
            content.title = "Invoice Due Today".translated()
            content.body = "%@ for %@ — due today".translated(with: invoice.invoiceNumber, invoice.clientName)
            content.userInfo = ["invoiceId": invoice.id.uuidString]
        case 2:
            content.title = "2 Invoices Due Today".translated()
            content.body = "%@ for %@ and %@ for %@ — due today".translated(
                with: invoices[0].invoiceNumber,
                invoices[0].clientName,
                invoices[1].invoiceNumber,
                invoices[1].clientName
            )
            content.userInfo = ["openTab": "finances", "digestDate": dateId]
        default:
            let first = invoices[0]
            content.title = "%d Invoices Due Today".translated(with: invoices.count)
            content.body = "%d invoices due today — starting with %@".translated(
                with: invoices.count,
                first.clientName
            )
            content.userInfo = ["openTab": "finances", "digestDate": dateId]
        }

        var comp = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comp.hour = 9; comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        let request = UNNotificationRequest(identifier: "invoice-today-\(dateId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func dayIdentifier(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private var appLocale: Locale {
        UserDefaults.standard.string(forKey: "appLanguage") == "pt-BR"
            ? Locale(identifier: "pt_BR")
            : Locale.current
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.locale = appLocale
        return f.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(appLocale).month(.abbreviated).day())
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "MARK_JOB_COMPLETE":
            if let jobIdString = userInfo["jobId"] as? String,
               let jobId = UUID(uuidString: jobIdString) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MarkJobComplete"),
                    object: nil,
                    userInfo: ["jobId": jobId]
                )
            }

        case "MARK_INVOICE_PAID":
            if let invoiceIdString = userInfo["invoiceId"] as? String,
               let invoiceId = UUID(uuidString: invoiceIdString) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MarkInvoicePaid"),
                    object: nil,
                    userInfo: ["invoiceId": invoiceId]
                )
            }

        case "REMIND_INVOICE_LATER":
            if let invoiceIdString = userInfo["invoiceId"] as? String,
               let invoiceId = UUID(uuidString: invoiceIdString) {
                let content = UNMutableNotificationContent()
                content.title = "Invoice Reminder".translated()
                content.body = response.notification.request.content.body
                content.sound = .default
                content.categoryIdentifier = "INVOICE_REMINDER"
                content.userInfo = userInfo
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: 3 * 24 * 60 * 60,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "invoice-remind-later-\(invoiceId)",
                    content: content,
                    trigger: trigger
                )
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            }

        default:
            // Default tap — navigate via deep link
            if let jobIdString = userInfo["jobId"] as? String,
               let jobId = UUID(uuidString: jobIdString) {
                DispatchQueue.main.async { self.pendingDeepLink = .job(jobId) }
            } else if let invoiceIdString = userInfo["invoiceId"] as? String,
                      let invoiceId = UUID(uuidString: invoiceIdString) {
                DispatchQueue.main.async { self.pendingDeepLink = .invoice(invoiceId) }
            } else if let openTab = userInfo["openTab"] as? String {
                DispatchQueue.main.async {
                    switch openTab {
                    case "schedule":
                        self.pendingDeepLink = .schedule
                    case "finances":
                        self.pendingDeepLink = .finances
                    default:
                        break
                    }
                }
            }
        }

        completionHandler()
    }
}
