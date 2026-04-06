import Foundation
import UserNotifications
import Observation

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    var isAuthorized = false
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    
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
        content.body = "This is a test notification to confirm everything is working! 🧹✨"
        content.sound = .default
        content.badge = 1
        
        // Deliver in 5 seconds
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification request: \(error)")
            }
        }
    }
    
    func scheduleJobReminder(for job: Job) {
        scheduleAt(hour: 8, minute: 0, dayOffset: -1, job: job, suffix: "dayBefore",
                   body: "Tomorrow: \(job.serviceType.rawValue) at \(job.clientName)")
        scheduleAt(hour: 7, minute: 0, dayOffset: 0, job: job, suffix: "morning",
                   body: "Today: \(job.serviceType.rawValue) at \(job.clientName) — \(job.address)")
    }

    func cancelJobReminders(for jobId: UUID) {
        let ids = ["\(jobId)-dayBefore", "\(jobId)-morning"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func scheduleAt(hour: Int, minute: Int, dayOffset: Int, job: Job, suffix: String, body: String) {
        guard let triggerDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: job.date) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: triggerDate)
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Job"
        content.body = body
        content.sound = .default
        content.userInfo = ["jobId": job.id.uuidString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "\(job.id)-\(suffix)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification selection
        print("Notification tapped: \(response.notification.request.content.title)")
        completionHandler()
    }
}
