import SwiftUI

enum CleanerJobFilter: String, CaseIterable {
    case all = "All"
    case completed = "Completed"
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case cancelled = "Cancelled"
}

struct CleanerJobsHistoryView: View {
    @Environment(JobsStore.self) private var jobsStore
    
    let membership: TeamMembership
    
    @State private var selectedFilter: CleanerJobFilter = .all
    @State private var selectedJobId: UUID? = nil
    
    private var myJobs: [Job] {
        jobsStore.jobs.filter { $0.assignedMemberId == membership.id }
    }
    
    private var filteredJobs: [Job] {
        let filtered: [Job]
        switch selectedFilter {
        case .all:
            filtered = myJobs
        case .completed:
            filtered = myJobs.filter { $0.status == .completed }
        case .scheduled:
            filtered = myJobs.filter { $0.status == .scheduled }
        case .inProgress:
            filtered = myJobs.filter { $0.status == .inProgress }
        case .cancelled:
            filtered = myJobs.filter { $0.status == .cancelled }
        }
        return filtered.sorted { $0.date > $1.date }
    }
    
    private var totalEarnings: Double {
        myJobs.filter { $0.status == .completed }.reduce(0) { $0 + $1.price }
    }
    
    private var completedCount: Int {
        myJobs.filter { $0.status == .completed }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statsHeader
                    filterPicker
                    jobsList
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jobs".translated())
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                    .frame(minHeight: 76, alignment: .center)
                    .padding(.top, 16)
                }
            }
            .navigationDestination(item: $selectedJobId) { jobId in
                CleanerJobDetailView(jobId: jobId, ownerId: membership.ownerId)
            }
        }
    }
    
    private var statsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Earnings".translated())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(totalEarnings.currency)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Jobs Completed".translated())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text("\(completedCount)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
    
    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CleanerJobFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }
    
    private var jobsList: some View {
        LazyVStack(spacing: 8) {
            if filteredJobs.isEmpty {
                emptyState
            } else {
                ForEach(filteredJobs) { job in
                    CleanerJobHistoryRow(job: job)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedJobId = job.id
                        }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            
            Text("No jobs found".translated())
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            
            Text("Try changing the filter".translated())
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.sweeplyAccent : Color.sweeplySurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CleanerJobHistoryRow: View {
    let job: Job
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: service type accent
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 8)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.clientName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Text(job.price.currency)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(job.status == .completed ? Color.sweeplyAccent : Color.sweeplyTextSub)
                }
                
                HStack(spacing: 8) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                    
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                    
                    Text(job.date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            
            // Right: status badge
            statusBadge
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
    
    private var statusBadge: some View {
        Text(job.status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch job.status {
        case .completed:  return Color.sweeplyAccent
        case .inProgress: return .orange
        case .scheduled:  return Color.sweeplyNavy
        case .cancelled:  return Color.sweeplyDestructive
        }
    }
}