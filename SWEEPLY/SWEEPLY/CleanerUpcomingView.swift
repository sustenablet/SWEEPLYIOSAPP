import SwiftUI

struct CleanerUpcomingView: View {
    @Environment(JobsStore.self) private var jobsStore

    @State private var selectedJobId: UUID? = nil

    private var upcomingJobs: [Job] {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let end   = start.addingTimeInterval(86400 * 7)
        return jobsStore.jobs
            .filter { $0.date >= start && $0.date < end && $0.status != .cancelled }
            .sorted { $0.date < $1.date }
    }

    private var groupedJobs: [(Date, [Job])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: upcomingJobs) { job in
            calendar.startOfDay(for: job.date)
        }
        return groups.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                if jobsStore.isLoading {
                    loadingView
                } else if upcomingJobs.isEmpty {
                    emptyState
                } else {
                    jobsList
                }
            }
            .navigationTitle("Upcoming")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId)
            }
        }
    }

    private var jobsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedJobs, id: \.0) { date, jobs in
                    Section {
                        VStack(spacing: 10) {
                            ForEach(jobs) { job in
                                CleanerJobCard(job: job)
                                    .padding(.horizontal, 20)
                                    .onTapGesture {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedJobId = job.id
                                    }
                            }
                        }
                        .padding(.bottom, 16)
                    } header: {
                        dateSectionHeader(date)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func dateSectionHeader(_ date: Date) -> some View {
        HStack {
            Text(agendaDateLabel(date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
    }

    private func agendaDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sweeplySurface)
                        .frame(height: 90)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.sweeplyAccent)

            VStack(spacing: 6) {
                Text("Nothing coming up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("No jobs in the next 7 days.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
