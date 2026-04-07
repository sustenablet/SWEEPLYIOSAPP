import Foundation
import UserNotifications
import Observation

enum DeepLink {
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
                print("Error requesting notification authorization: \(error)")
            }
            DispatchQueue.main.async {
                self.isAuthorized = granted
                self.checkAuthorizationStatus()
            }
        }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Sweeply Notification"
        content.body = "This is a test notification to confirm everything is working!"
        content.sound = .default
        content.badge = 1
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error adding test notification: \(error)") }
        }
    }

    // MARK: - Job Reminders

    func scheduleJobReminder(for job: Job) {
        // 1 hour before
        scheduleAt(timeInterval: -3600, job: job, suffix: "hour",
                   title: "Job in 1 Hour",
                   body: "\(job.serviceType.rawValue) at \(job.clientName) — \(job.address)")
        // 8am the day before
        scheduleCalendar(hour: 8, minute: 0, dayOffset: -1, job: job, suffix: "dayBefore",
                         title: "Job Tomorrow",
                         body: "\(job.serviceType.rawValue) at \(job.clientName)")
        // 7am morning of
        scheduleCalendar(hour: 7, minute: 0, dayOffset: 0, job: job, suffix: "morning",
                         title: "Job Today",
                         body: "\(job.serviceType.rawValue) at \(job.clientName) — \(job.address)")
    }

    func cancelJobReminders(for jobId: UUID) {
        let ids = ["\(jobId)-hour", "\(jobId)-dayBefore", "\(jobId)-morning"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Invoice Reminders

    func scheduleInvoiceReminder(for invoice: Invoice) {
        let content3Day = UNMutableNotificationContent()
        content3Day.title = "Invoice Due Soon"
        content3Day.body = "\(invoice.invoiceNumber) for \(invoice.clientName) is due in 3 days — \(invoice.subtotal.formatted(.currency(code: "USD")))"
        content3Day.sound = .default
        content3Day.userInfo = ["invoiceId": invoice.id.uuidString]

        let contentDayOf = UNMutableNotificationContent()
        contentDayOf.title = "Invoice Due Today"
        contentDayOf.body = "\(invoice.invoiceNumber) for \(invoice.clientName) is due today — \(invoice.subtotal.formatted(.currency(code: "USD")))"
        contentDayOf.sound = .default
        contentDayOf.userInfo = ["invoiceId": invoice.id.uuidString]

        // 3 days before at 9am
        if let threeDayBefore = Calendar.current.date(byAdding: .day, value: -3, to: invoice.dueDate) {
            var comp = Calendar.current.dateComponents([.year, .month, .day], from: threeDayBefore)
            comp.hour = 9
            comp.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: "\(invoice.id)-due3day", content: content3Day, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }

        // Day of at 9am
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: invoice.dueDate)
        comp.hour = 9
        comp.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        let req = UNNotificationRequest(identifier: "\(invoice.id)-dueToday", content: contentDayOf, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancelInvoiceReminders(for invoiceId: UUID) {
        let ids = ["\(invoiceId)-due3day", "\(invoiceId)-dueToday"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Private Helpers

    private func scheduleCalendar(hour: Int, minute: Int, dayOffset: Int, job: Job, suffix: String, title: String, body: String) {
        guard let triggerDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: job.date) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: triggerDate)
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["jobId": job.id.uuidString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "\(job.id)-\(suffix)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func scheduleAt(timeInterval: TimeInterval, job: Job, suffix: String, title: String, body: String) {
        let fireDate = job.date.addingTimeInterval(timeInterval)
        guard fireDate > Date() else { return }
        let interval = fireDate.timeIntervalSinceNow
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["jobId": job.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "\(job.id)-\(suffix)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let jobIdString = userInfo["jobId"] as? String, let jobId = UUID(uuidString: jobIdString) {
            DispatchQueue.main.async {
                self.pendingDeepLink = .job(jobId)
            }
        } else if let invoiceIdString = userInfo["invoiceId"] as? String, let invoiceId = UUID(uuidString: invoiceIdString) {
            DispatchQueue.main.async {
                self.pendingDeepLink = .invoice(invoiceId)
            }
        }
        completionHandler()
    }
}
