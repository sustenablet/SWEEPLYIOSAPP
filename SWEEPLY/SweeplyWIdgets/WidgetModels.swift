import Foundation

// MARK: - Shared Widget Data Models
// These structs are written by the main app via WidgetDataWriter
// and read here by the widget timeline provider.

struct WidgetSnapshot: Codable {
    let nextJob: WidgetJob?
    let todayJobs: [WidgetJob]
    let weekRevenue: Double
    let updatedAt: Date

    static let appGroupID  = "group.com.sweeply.app"
    static let defaultsKey = "sweeply_widget_snapshot"

    static func load() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data     = defaults.data(forKey: defaultsKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            nextJob: WidgetJob(
                clientName: "Sarah Johnson",
                serviceType: "Standard Clean",
                date: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date(),
                statusRaw: "scheduled",
                price: 150
            ),
            todayJobs: [
                WidgetJob(clientName: "Sarah Johnson", serviceType: "Standard Clean",
                          date: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date(),
                          statusRaw: "completed", price: 120),
                WidgetJob(clientName: "Mike Torres", serviceType: "Deep Clean",
                          date: Calendar.current.date(bySettingHour: 11, minute: 30, second: 0, of: Date()) ?? Date(),
                          statusRaw: "scheduled", price: 200),
                WidgetJob(clientName: "Emma White", serviceType: "Move-Out Clean",
                          date: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date(),
                          statusRaw: "scheduled", price: 280),
            ],
            weekRevenue: 1240,
            updatedAt: Date()
        )
    }
}

struct WidgetJob: Codable {
    let clientName:  String
    let serviceType: String
    let date:        Date
    let statusRaw:   String   // "scheduled" | "inProgress" | "completed" | "cancelled"
    let price:       Double

    var isCompleted:  Bool { statusRaw == "completed" }
    var isInProgress: Bool { statusRaw == "inProgress" }
    var isCancelled:  Bool { statusRaw == "cancelled" }

    var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}
