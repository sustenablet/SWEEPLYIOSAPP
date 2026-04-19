import SwiftUI
import MapKit

struct CleanerJobDetailView: View {
    let jobId: UUID

    @Environment(JobsStore.self) private var jobsStore
    @Environment(\.dismiss) private var dismiss

    @State private var isUpdatingStatus = false

    private var job: Job? {
        jobsStore.jobs.first(where: { $0.id == jobId })
    }

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            if let job {
                ScrollView {
                    VStack(spacing: 16) {
                        jobHeader(job)
                        detailsCard(job)
                        if !job.address.isEmpty {
                            navigateButton(job)
                        }
                        statusActions(job)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            } else {
                Text("Job not found")
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .navigationTitle("Job Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func jobHeader(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(job.clientName)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statusBadge(job.status)
                    if job.isRecurring {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                            Text(job.recurrenceFrequency?.displayName ?? "Recurring")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.sweeplyAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.sweeplyAccent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            Text(job.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.sweeplyTextSub)

            Text(job.price.currency)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .padding(.top, 2)
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func detailsCard(_ job: Job) -> some View {
        VStack(spacing: 0) {
            if !job.address.isEmpty {
                detailRow(icon: "mappin.circle.fill", label: "Address", value: job.address)
                Divider().padding(.leading, 44)
            }
            detailRow(icon: "clock.fill", label: "Duration", value: durationLabel(job.duration))
            Divider().padding(.leading, 44)
            detailRow(icon: "dollarsign.circle.fill", label: "Pay", value: job.price.currency)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            }
            Spacer()
        }
        .padding(14)
    }

    private func navigateButton(_ job: Job) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            openInMaps(address: job.address)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Navigate to Job")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.sweeplyNavy)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func statusActions(_ job: Job) -> some View {
        VStack(spacing: 10) {
            if job.status == .scheduled {
                actionButton(label: "Start Job", icon: "play.fill", color: .orange) {
                    updateStatus(id: job.id, status: .inProgress)
                }
            }
            if job.status == .scheduled || job.status == .inProgress {
                actionButton(label: "Mark Complete", icon: "checkmark.circle.fill", color: .green) {
                    updateStatus(id: job.id, status: .completed)
                }
            }
            if job.status == .completed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Job Completed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func actionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if isUpdatingStatus {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isUpdatingStatus)
    }

    private func statusBadge(_ status: JobStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .scheduled:  return Color.sweeplyAccent
        case .inProgress: return .orange
        case .completed:  return .green
        case .cancelled:  return Color.sweeplyTextSub
        }
    }

    private func durationLabel(_ hours: Double) -> String {
        if hours == 1 { return "1 hour" }
        if hours == floor(hours) { return "\(Int(hours)) hours" }
        return String(format: "%.1f hours", hours)
    }

    private func updateStatus(id: UUID, status: JobStatus) {
        isUpdatingStatus = true
        Task {
            _ = await jobsStore.updateStatus(id: id, status: status)
            isUpdatingStatus = false
        }
    }

    private func openInMaps(address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}
