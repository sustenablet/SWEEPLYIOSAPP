import WidgetKit
import SwiftUI

// MARK: - Colors (hardcoded — widget can't import main app DesignSystem)

private extension Color {
    static let teal        = Color(red: 0.157, green: 0.325, blue: 0.420)     // #28536B light mode
    static let tealLight   = Color(red: 0.302, green: 0.561, blue: 0.659)     // #4DFA8 dark mode
    static let charcoal    = Color(red: 0.15,  green: 0.15,  blue: 0.18)
    static let stone       = Color(red: 0.965, green: 0.961, blue: 0.945)
    static let amber       = Color(red: 0.72,  green: 0.55,  blue: 0.35)
    static let coral       = Color(red: 0.70,  green: 0.25,  blue: 0.25)
    static let mutedText   = Color(red: 0.45,  green: 0.45,  blue: 0.48)

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
    f.dateFormat = "EEEE"
    return f.string(from: date)
}

private func statusColor(_ statusRaw: String) -> Color {
    switch statusRaw.lowercased() {
    case "completed":   return .teal
    case "inprogress":  return .amber
    case "cancelled":   return .coral
    default:            return Color(red: 0.6, green: 0.6, blue: 0.62)
    }
}

private func formattedCurrency(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = .current
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: amount)) ?? "$0"
}

// MARK: - Next Job Widget (systemSmall)

struct NextJobEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { scheme == .dark ? .tealLight : .teal }

    private var deepLinkURL: URL {
        if let job = entry.snapshot.nextJob {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            let dateStr = f.string(from: job.date)
            return URL(string: "sweeply://schedule?date=\(dateStr)") ?? URL(string: "sweeply://schedule")!
        }
        return URL(string: "sweeply://schedule")!
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if let job = entry.snapshot.nextJob {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NEXT JOB")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.charcoal.opacity(0.45))
                        .tracking(1.4)

                    Spacer(minLength: 8)

                    Text(job.clientName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.charcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(job.serviceType)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.charcoal.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 10)

                    Text(formattedCurrency(job.price))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.charcoal)

                    Spacer(minLength: 6)

                    HStack(spacing: 0) {
                        Text(relativeDay(for: job.date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.charcoal.opacity(0.5))
                        Text("  ·  ")
                            .foregroundStyle(Color.charcoal.opacity(0.25))
                        Text(timeString(from: job.date))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.charcoal)
                        Spacer()
                    }
                }
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCHEDULE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.charcoal.opacity(0.45))
                        .tracking(1.4)

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.charcoal.opacity(0.7))
                        .padding(.bottom, 6)

                    Text("All caught up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.charcoal)

                    Text("No upcoming jobs")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.charcoal.opacity(0.5))
                        .padding(.top, 2)

                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(deepLinkURL)
    }
}

struct NextJobWidget: Widget {
    let kind = "SweeplyNextJob"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            NextJobEntryView(entry: entry)
                .containerBackground(Color.white, for: .widget)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY'S SCHEDULE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .tracking(1.2)
                Spacer()
                let count = entry.snapshot.todayJobs.count
                Text("\(count) job\(count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.7))
            }
            .padding(.bottom, 10)

            if jobs.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(accent.opacity(0.5))
                        Text("All clear today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                        TodayJobRow(job: job, accent: accent)
                    }
                }
                Spacer(minLength: 8)
                if entry.snapshot.weekRevenue > 0 {
                    Divider().padding(.bottom, 5)
                    HStack {
                        Text("7-day revenue")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.mutedText)
                        Spacer()
                        Text(formattedCurrency(entry.snapshot.weekRevenue))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(14)
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
                .foregroundStyle(Color.mutedText)
                .frame(width: 52, alignment: .leading)

            Text(job.clientName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                .lineLimit(1)

            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Color.mutedText)

            Text(job.serviceType)
                .font(.system(size: 10))
                .foregroundStyle(Color.mutedText)
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

// MARK: - Large Schedule Widget (systemLarge)

struct LargeScheduleEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { scheme == .dark ? .tealLight : .teal }
    private var jobs: [WidgetJob] { Array(entry.snapshot.todayJobs.prefix(6)) }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SWEEPLY")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                        .tracking(1.4)
                    Text(todayLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    let count = entry.snapshot.todayJobs.count
                    Text("\(count)")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("job\(count == 1 ? "" : "s") today")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.mutedText)
                }
            }
            .padding(.bottom, 12)

            Divider().padding(.bottom, 10)

            if jobs.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(accent.opacity(0.45))
                        Text("No jobs today")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.offset) { idx, job in
                        LargeJobRow(job: job, accent: accent)
                        if idx < jobs.count - 1 {
                            Divider()
                                .padding(.leading, 14)
                                .padding(.vertical, 1)
                        }
                    }
                }
                let overflow = entry.snapshot.todayJobs.count - jobs.count
                if overflow > 0 {
                    Text("+ \(overflow) more job\(overflow == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.mutedText)
                        .padding(.top, 6)
                }
            }

            Spacer(minLength: 8)

            Divider().padding(.bottom, 8)
            HStack(spacing: 0) {
                statPill(label: "7-day rev.", value: formattedCurrency(entry.snapshot.weekRevenue), accent: accent)
                Spacer()
                let completed = entry.snapshot.todayJobs.filter { $0.isCompleted }.count
                statPill(label: "done today", value: "\(completed)/\(entry.snapshot.todayJobs.count)", accent: accent)
                Spacer()
                if let next = entry.snapshot.nextJob, !Calendar.current.isDateInToday(next.date) {
                    statPill(label: "next job", value: relativeDay(for: next.date), accent: accent)
                } else {
                    statPill(label: "updated", value: shortTime(entry.snapshot.updatedAt), accent: accent)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func statPill(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.mutedText)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

private struct LargeJobRow: View {
    let job: WidgetJob
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(job.statusRaw))
                .frame(width: 7, height: 7)

            Text(timeString(from: job.date))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.mutedText)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(job.clientName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                    .lineLimit(1)
                Text(job.serviceType)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Text(formattedCurrency(job.price))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(job.isCompleted ? accent : Color(red: 0.15, green: 0.15, blue: 0.18))
        }
        .padding(.vertical, 7)
    }
}

struct LargeScheduleWidget: Widget {
    let kind = "SweeplyLargeSchedule"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            LargeScheduleEntryView(entry: entry)
                .containerBackground(Color.stone, for: .widget)
        }
        .configurationDisplayName("Full Day Schedule")
        .description("Your complete today schedule with up to 6 jobs and revenue stats.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Lock Screen Shared Helpers

private func formattedLockScreen(_ amount: Double) -> String {
    if amount >= 1000 { return String(format: "$%.1fk", amount / 1000) }
    return "$\(Int(amount))"
}

// MARK: - Revenue This Week Widget (accessoryCircular + accessoryRectangular)

struct WeekRevenueEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Text(formattedLockScreen(entry.snapshot.weekRevenue))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .widgetAccentable()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("THIS WK")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.65)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WEEK REVENUE")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
            Text(formattedCurrency(entry.snapshot.weekRevenue))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .widgetAccentable()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("7-day earnings")
                .font(.system(size: 10))
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeekRevenueWidget: Widget {
    let kind = "SweeplyWeekRevenue"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            WeekRevenueEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Week Revenue")
        .description("Your earnings over the past 7 days.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Jobs Today Widget (accessoryCircular + accessoryRectangular)

struct JobsTodayEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int { entry.snapshot.todayJobs.count }
    private var completedCount: Int { entry.snapshot.todayJobs.filter { $0.isCompleted }.count }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .widgetAccentable()
            Text("TODAY")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.65)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("JOBS TODAY")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
            Text("\(count) \(count == 1 ? "job" : "jobs")")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .widgetAccentable()
                .lineLimit(1)
            Text(completedCount > 0 ? "\(completedCount) completed" : "none completed yet")
                .font(.system(size: 10))
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JobsTodayWidget: Widget {
    let kind = "SweeplyJobsToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            JobsTodayEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Jobs Today")
        .description("How many jobs you have scheduled for today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Revenue Today Widget (accessoryCircular + accessoryRectangular)

struct TodayRevenueEntryView: View {
    let entry: SweeplyEntry
    @Environment(\.widgetFamily) private var family

    private var jobCount: Int { entry.snapshot.todayJobs.count }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Text(formattedLockScreen(entry.snapshot.todayRevenue))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .widgetAccentable()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("TODAY")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.65)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TODAY'S VALUE")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
            Text(formattedCurrency(entry.snapshot.todayRevenue))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .widgetAccentable()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("\(jobCount) \(jobCount == 1 ? "job" : "jobs") on schedule")
                .font(.system(size: 10))
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayRevenueWidget: Widget {
    let kind = "SweeplyTodayRevenue"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SweeplyProvider()) { entry in
            TodayRevenueEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today's Revenue")
        .description("Total value of all jobs scheduled for today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}