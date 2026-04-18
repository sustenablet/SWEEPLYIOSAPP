import SwiftUI

struct CleanerHomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(JobsStore.self)  private var jobsStore

    @State private var selectedJobId: UUID? = nil

    private var todaysJobs: [Job] {
        jobsStore.jobs
            .filter { Calendar.current.isDateInToday($0.date) && $0.status != .cancelled }
            .sorted { $0.date < $1.date }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        jobsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
        }
        .padding(.top, 8)
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Jobs")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                if !todaysJobs.isEmpty {
                    Text("\(todaysJobs.count) job\(todaysJobs.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            if jobsStore.isLoading {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.sweeplySurface)
                            .frame(height: 90)
                    }
                }
            } else if todaysJobs.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(todaysJobs) { job in
                        CleanerJobCard(job: job)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedJobId = job.id
                            }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.sweeplyAccent)

            VStack(spacing: 6) {
                Text("You're all clear today")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("No jobs scheduled. Enjoy the day!")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct CleanerJobCard: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(job.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Rectangle()
                    .fill(statusColor(job.status).opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.clientName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(job.serviceType.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                if !job.address.isEmpty {
                    Label(job.address, systemImage: "mappin")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusPill(job.status)
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func statusPill(_ status: JobStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .scheduled:   return Color.sweeplyAccent
        case .inProgress:  return .orange
        case .completed:   return .green
        case .cancelled:   return Color.sweeplyTextSub
        }
    }
}
