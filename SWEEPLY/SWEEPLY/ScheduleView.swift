import SwiftUI

struct ScheduleView: View {
    @State private var jobs: [Job] = MockData.makeJobs()
    @State private var weekOffset: Int = 0
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var appeared = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }

    private var weekInterval: DateInterval {
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return calendar.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: Date(), end: Date())
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: weekInterval.start)
        }
    }

    private var jobsForSelectedDay: [Job] {
        jobs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
    }

    private var weekTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end
        return "\(f.string(from: weekInterval.start)) – \(f.string(from: end))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    weekStrip
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    jobsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onChange(of: weekOffset) { _, _ in
            if !weekDays.contains(where: { calendar.isDate($0, inSameDayAs: selectedDay) }) {
                selectedDay = calendar.startOfDay(for: weekInterval.start)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALENDAR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                .tracking(1.5)
            HStack(alignment: .center) {
                Text("Schedule")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .frame(width: 36, height: 36)
                    }
                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            Text(weekTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let dayNum = calendar.component(.day, from: day)
        let weekday = shortWeekday(day)

        return Button {
            selectedDay = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
                Text("\(dayNum)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.sweeplyAccent.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func shortWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayHeading)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Text("\(jobsForSelectedDay.count) visits")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            if jobsForSelectedDay.isEmpty {
                scheduleEmptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(jobsForSelectedDay) { job in
                        NavigationLink {
                            ScheduleJobDetailView(job: job)
                        } label: {
                            ScheduleJobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dayHeading: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: selectedDay)
    }

    private var scheduleEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.45))
            Text("Nothing scheduled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Jobs you add will show up here for this day.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Row

private struct ScheduleJobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                    .monospacedDigit()
                Text("\(durationText) · \(job.price.currency)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.clientName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
                if !job.address.isEmpty {
                    Text(job.address)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.9))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(status: job.status)
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let start = f.string(from: job.date)
        let endDate = job.date.addingTimeInterval(job.duration * 3600)
        return "\(start) – \(f.string(from: endDate))"
    }

    private var durationText: String {
        if job.duration == floor(job.duration) {
            return "\(Int(job.duration)) hr"
        }
        return String(format: "%.1f hr", job.duration)
    }
}

// MARK: - Detail

struct ScheduleJobDetailView: View {
    let job: Job

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.clientName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    StatusBadge(status: job.status)
                }

                detailRow(icon: "wrench.and.screwdriver", title: "Service", value: job.serviceType.rawValue)
                detailRow(icon: "clock", title: "Time", value: timeBlock)
                detailRow(icon: "dollarsign.circle", title: "Price", value: job.price.currency)
                detailRow(icon: "mappin.and.ellipse", title: "Location", value: job.address.isEmpty ? "—" : job.address)
                detailRow(icon: "arrow.triangle.2.circlepath", title: "Recurring", value: job.isRecurring ? "Yes" : "No")
            }
            .padding(20)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var timeBlock: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        return f.string(from: job.date)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    .tracking(0.8)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

#Preview {
    ScheduleView()
}
