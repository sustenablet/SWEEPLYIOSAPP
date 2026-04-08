import WidgetKit
import SwiftUI

// MARK: - Colors (hardcoded — widget can't import main app DesignSystem)

private extension Color {
    static let teal        = Color(red: 0.157, green: 0.325, blue: 0.420)     // #28536B light mode
    static let tealLight   = Color(red: 0.302, green: 0.561, blue: 0.659)     // #4D8FA8 dark mode
    static let charcoal    = Color(red: 0.15,  green: 0.15,  blue: 0.18)
    static let stone       = Color(red: 0.965, green: 0.961, blue: 0.945)
    static let amber       = Color(red: 0.72,  green: 0.55,  blue: 0.35)
    static let coral       = Color(red: 0.70,  green: 0.25,  blue: 0.25)

    @available(iOSApplicationExtension 16.0, *)
    static func adaptiveTeal(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .tealLight : .teal
    }
}

// MARK: - Shared Timeline Entry

struct SweeplyEntry: TimelineEntry {
    let date:     Date
    let snapshot: WidgetSnapshot
}

// MARK: - Shared Provider

struct SweeplyProvider: TimelineProvider {

    func placeholder(in context: Context) -> SweeplyEntry {
        SweeplyEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SweeplyEntry) -> Void) {
        completion(SweeplyEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SweeplyEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry    = SweeplyEntry(date: Date(), snapshot: snapshot)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Helpers

private func timeString(from date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: date)
}

private func relativeDay(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date)     { return "Today" }
    if cal.isDateInTomorrow(date)  { return "Tomorrow" }
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    return f.string(from: date)
}

// MARK: - Status Dot Color

private func statusColor(_ statusRaw: String) -> Color {
    switch statusRaw {
    case "completed":   return .teal
    case "inprogress":  return .amber
    case "cancelled":   return .coral
    default:            return Color(red: 0.6, green: 0.6, blue: 0.62) // muted for scheduled
    }
}

// MARK: - Next Job Widget (systemSmall)

struct NextJobEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family

    private var accent: Color { scheme == .dark ? .tealLight : .teal }

    var body: some View {
        ZStack {
            Color.stone.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("SWEEPLY")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                        .tracking(1.2)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .padding(.bottom, 10)

                if let job = entry.snapshot.nextJob {
                    Text("Next Job")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.bottom, 4)

                    Text(job.clientName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.charcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(job.serviceType)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .padding(.bottom, 10)

                    Spacer()

                    // Day + time
                    HStack(spacing: 0) {
                        Text(relativeDay(for: job.date))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.charcoal)
                        Spacer()
                        Text(timeString(from: job.date))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                    }
                } else {
                    Spacer()

                    Text("No upcoming\njobs scheduled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)

                    Spacer()
                }
            }
            .padding(14)
        }
    }
}

struct NextJobWidget: Widget {
    let kind = "SweeplyNextJob"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            NextJobEntryView(entry: entry)
                .containerBackground(Color.stone, for: .widget)
        }
        .configurationDisplayName("Next Job")
        .description("Your next upcoming job at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Today Schedule Widget (systemMedium)

struct TodayScheduleEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { scheme == .dark ? .tealLight : .teal }

    private var jobs: [WidgetJob] { Array(entry.snapshot.todayJobs.prefix(3)) }

    var body: some View {
        ZStack {
            Color.stone.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack {
                    Text("SWEEPLY")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                        .tracking(1.2)

                    Text("·")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: 9))

                    Text("Today's Schedule")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    Spacer()

                    let count = entry.snapshot.todayJobs.count
                    Text("\(count) job\(count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                }
                .padding(.bottom, 10)

                if jobs.isEmpty {
                    Spacer()
                    Text("No jobs scheduled today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                            TodayJobRow(job: job, accent: accent)
                        }
                    }

                    Spacer()

                    // Revenue footer
                    if entry.snapshot.weekRevenue > 0 {
                        Divider().padding(.bottom, 6)
                        HStack {
                            Text("7-day revenue")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary)
                            Spacer()
                            Text(formattedRevenue(entry.snapshot.weekRevenue))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func formattedRevenue(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

private struct TodayJobRow: View {
    let job: WidgetJob
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(job.statusRaw))
                .frame(width: 6, height: 6)

            Text(timeString(from: job.date))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 52, alignment: .leading)

            Text(job.clientName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                .lineLimit(1)

            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)

            Text(job.serviceType)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)

            Spacer()
        }
    }
}

struct TodayScheduleWidget: Widget {
    let kind = "SweeplyTodaySchedule"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            TodayScheduleEntryView(entry: entry)
                .containerBackground(Color.stone, for: .widget)
        }
        .configurationDisplayName("Today's Schedule")
        .description("See all of today's jobs in one glance.")
        .supportedFamilies([.systemMedium])
    }
}
