import Foundation
import WidgetKit

// MARK: - Widget Data Writer
// Called after stores load to push a snapshot into the shared App Group UserDefaults.
// The widget extension reads this data via WidgetSnapshot.load().
//
// If App Groups are enabled for the app + widget targets, this writer can push
// snapshots into the shared container. Without that capability, writes no-op.

struct WidgetDataWriter {

    private static let appGroupID  = "group.com.sweeply.app"
    private static let defaultsKey = "sweeply_widget_snapshot"

    // MARK: - Write

    static func write(jobs: [Job], invoices: [Invoice]) {
        let cal = Calendar.current

        // Today's jobs — sorted by time
        let todayJobs = jobs
            .filter { cal.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
            .map { WidgetJobData(from: $0) }

        // Next upcoming scheduled job (may or may not be today)
        let nextJob = jobs
            .filter { $0.date > Date() && $0.status == .scheduled }
            .sorted { $0.date < $1.date }
            .first
            .map { WidgetJobData(from: $0) }

        // Revenue collected in the last 7 days
        let weekStart = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekRevenue = invoices
            .filter { $0.status == .paid && $0.createdAt >= weekStart }
            .reduce(0.0) { $0 + $1.total }

        let snapshot = WidgetSnapshotData(
            nextJob: nextJob,
            todayJobs: todayJobs,
            weekRevenue: weekRevenue,
            updatedAt: Date()
        )

        guard
            let data = try? JSONEncoder().encode(snapshot),
            let defaults = UserDefaults(suiteName: appGroupID)
        else { return }

        defaults.set(data, forKey: defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Local Codable Data Structs
// Duplicated from WidgetModels.swift in the widget target.
// Widget target is a separate module — it cannot be imported here.

private struct WidgetSnapshotData: Codable {
    let nextJob:     WidgetJobData?
    let todayJobs:   [WidgetJobData]
    let weekRevenue: Double
    let updatedAt:   Date
}

private struct WidgetJobData: Codable {
    let clientName:  String
    let serviceType: String
    let date:        Date
    let statusRaw:   String
    let price:       Double

    init(from job: Job) {
        self.clientName  = job.clientName
        self.serviceType = job.serviceType.rawValue
        self.date        = job.date
        self.statusRaw   = job.status.rawValue.lowercased().replacingOccurrences(of: " ", with: "")
        self.price        = job.price
    }
}
