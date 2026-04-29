import Foundation
import UserNotifications
import Observation

enum DeepLink: Equatable {
    case job(UUID)
    case invoice(UUID)
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
            title: "Mark Complete",
            options: [.authenticationRequired]
        )
        let viewJobAction = UNNotificationAction(
            identifier: "VIEW_JOB",
            title: "View Job",
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
            title: "Mark Paid",
            options: [.authenticationRequired]
        )
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_INVOICE_LATER",
            title: "Remind in 3 Days",
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

    func fireInstantBanner(title: String, body: String) {
        guard isAuthorized else { return }
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
        content.title = "Sweeply Notifications"
        content.body = "Everything is working — you'll get reminders for jobs and invoices here."
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
        content.title = "Starting in 1 Hour"
        var body = "\(job.serviceType.rawValue) for \(job.clientName) at \(shortTime(job.date))"
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
                title: "Job Reminder",
                message: "\(job.serviceType.rawValue) for \(job.clientName) starts at \(shortTime(job.date))",
                kind: "schedule"
            )
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
        }
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
            content.title = "Job Today"
            content.body = "\(job.serviceType.rawValue) for \(job.clientName) at \(shortTime(job.date))"
            if !job.address.isEmpty { content.body += " — \(cityFromAddress(job.address))" }
            content.userInfo = ["jobId": job.id.uuidString]
        case 2:
            content.title = "2 Jobs Today"
            content.body = "\(jobs[0].clientName) at \(shortTime(jobs[0].date)), then \(jobs[1].clientName) at \(shortTime(jobs[1].date))"
        default:
            let first = jobs[0]
            content.title = "\(jobs.count) Jobs Today"
            content.body = "Starting at \(shortTime(first.date)) with \(first.clientName) — tap to see your full schedule"
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
            content.title = "Tomorrow: 1 Job"
            content.body = "\(job.serviceType.rawValue) for \(job.clientName) at \(shortTime(job.date))"
            content.userInfo = ["jobId": job.id.uuidString]
        case 2:
            content.title = "Tomorrow: 2 Jobs"
            content.body = "\(jobs[0].clientName) at \(shortTime(jobs[0].date)) and \(jobs[1].clientName) at \(shortTime(jobs[1].date))"
        default:
            let first = jobs[0]
            let last = jobs[jobs.count - 1]
            content.title = "Tomorrow: \(jobs.count) Jobs"
            content.body = "\(shortTime(first.date))–\(shortTime(last.date)) — starting with \(first.clientName)"
        }

        var comp = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        comp.hour = 18; comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        let request = UNNotificationRequest(identifier: "evening-preview-\(dateId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Weekly Earnings Digest (every Monday 9am)

    /// Call once after authorization is granted. Schedules a recurring Monday morning digest.
    func scheduleWeeklyEarningsSummary() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["weekly-earnings-summary"]
        )
        let content = UNMutableNotificationContent()
        content.title = "Weekly Earnings Summary"
        content.body = "Open Finance to see what you earned last week and what's coming up."
        content.sound = .default

        var comp = DateComponents()
        comp.weekday = 2  // Monday (1 = Sun)
        comp.hour = 9
        comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)
        let request = UNNotificationRequest(
            identifier: "weekly-earnings-summary",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
                    content.title = "Time to Pay \(member.name)"
                    content.body = "\(member.name) is owed \(member.payRateAmount.currency) today. Open Sweeply to record the payment."
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
        content.title = "It's Pay Day!"
        content.body = "Your \(membership.payRateAmount.currency) from \(membership.businessName) should be processed today."
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
            content.title = "Invoice Due in 3 Days"
            content.body = "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.currency) due \(shortDate(invoice.dueDate))"
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
                    title: "Invoice Due in 3 Days",
                    message: "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.currency) due \(shortDate(invoice.dueDate))",
                    kind: "billing"
                )
            }
        }

        // Day of due at 9am
        if Calendar.current.startOfDay(for: invoice.dueDate) >= Calendar.current.startOfDay(for: Date()) {
            let content = UNMutableNotificationContent()
            content.title = "Invoice Due Today"
            content.body = "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.currency) is due today"
            content.sound = .default
            content.userInfo = ["invoiceId": invoice.id.uuidString]
            content.categoryIdentifier = "INVOICE_REMINDER"

            var comp = Calendar.current.dateComponents([.year, .month, .day], from: invoice.dueDate)
            comp.hour = 9; comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: "\(invoice.id)-dueToday", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

            Task {
                await NotificationHelper.insert(
                    title: "Invoice Due Today",
                    message: "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.currency) is due today",
                    kind: "billing"
                )
            }
        }

        // 1 day overdue at 9am — escalation
        if let dayAfterDue = Calendar.current.date(byAdding: .day, value: 1, to: invoice.dueDate),
           dayAfterDue > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Invoice Overdue"
            content.body = "\(invoice.invoiceNumber) for \(invoice.clientName) was due yesterday — \(invoice.subtotal.currency) still unpaid"
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
                    title: "Invoice Overdue",
                    message: "\(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.currency) still unpaid",
                    kind: "billing"
                )
            }
        }
    }

    func cancelInvoiceReminders(for invoiceId: UUID) {
        let ids = ["\(invoiceId)-due3day", "\(invoiceId)-dueToday", "\(invoiceId)-overdue"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Helpers

    /// Extracts just the city from a full address ("123 Main St, Miami, FL 33101" → "Miami")
    private func cityFromAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count >= 2 ? parts[1] : (parts.first ?? address)
    }

    private func dayIdentifier(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
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
                content.title = "Invoice Reminder"
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
            }
        }

        completionHandler()
    }
}
