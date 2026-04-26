import SwiftUI

struct JobFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var statusFilter: JobStatus?
    @Binding var typeFilter: String
    @Binding var enabledViewModes: Set<ScheduleViewMode>
    @Binding var showInvoices: Bool

    // Internal state to allow "Cancel"
    @State private var localStatus: JobStatus?
    @State private var localType: String = "All"
    @State private var localViewModes: Set<ScheduleViewMode> = [.day, .list, .map]
    @State private var localShowInvoices: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filters".translated())
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 32, height: 32)
                        .background(Color.sweeplyBorder.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Status Group
                    VStack(alignment: .leading, spacing: 16) {
                        FilterHeader(title: "JOB STATUS", subtitle: "Filter by current job progress".translated())
                        
                        ChipGroup(spacing: 8) {
                            FilterChip(label: "All Statuses", isSelected: localStatus == nil) {
                                localStatus = nil
                            }
                            
                            ForEach(JobStatus.allCases, id: \.self) { status in
                                FilterChip(
                                    label: status.rawValue,
                                    isSelected: localStatus == status,
                                    color: statusColor(for: status)
                                ) {
                                    localStatus = status
                                }
                            }
                        }
                    }
                    
                    // Job Type Group
                    VStack(alignment: .leading, spacing: 16) {
                        FilterHeader(title: "SCHEDULE TYPE", subtitle: "One-time or recurring jobs".translated())
                        
                        HStack(spacing: 12) {
                            TypeCard(label: "All", icon: "square.grid.2x2.fill", isSelected: localType == "All") {
                                localType = "All"
                            }
                            TypeCard(label: "Recurring", icon: "arrow.triangle.2.circlepath", isSelected: localType == "Recurring") {
                                localType = "Recurring"
                            }
                            TypeCard(label: "One-time", icon: "calendar", isSelected: localType == "One-time") {
                                localType = "One-time"
                            }
                        }
                    }
                    
                    // View Modes Group
                    VStack(alignment: .leading, spacing: 16) {
                         VStack(alignment: .leading, spacing: 4) {
                            Text("VIEW OPTIONS".translated())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .tracking(1.0)
                            Text("Select which tabs appear in the schedule".translated())
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        VStack(spacing: 1) {
                            ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                                ToggleRow(
                                    label: mode.rawValue,
                                    icon: iconFor(mode: mode),
                                    isOn: localViewModes.contains(mode)
                                ) {
                                    if localViewModes.contains(mode) {
                                        if localViewModes.count > 1 { // Prevent disabling all
                                            localViewModes.remove(mode)
                                        }
                                    } else {
                                        localViewModes.insert(mode)
                                    }
                                }

                                if mode != ScheduleViewMode.allCases.last {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color.sweeplyBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }

                    // Content Type Group
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SHOW CONTENT".translated())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                                .tracking(1.0)
                            Text("Choose what appears on your schedule".translated())
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }

                        VStack(spacing: 1) {
                            ToggleRow(
                                label: "Jobs",
                                icon: "briefcase.fill",
                                isOn: true,
                                enabled: false
                            ) { }

                            Divider().padding(.leading, 44)

                            ToggleRow(
                                label: "Invoices",
                                icon: "doc.text.fill",
                                isOn: localShowInvoices,
                                enabled: true
                            ) {
                                localShowInvoices.toggle()
                            }
                        }
                        .background(Color.sweeplyBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            
            // Footer Actions
            VStack(spacing: 12) {
                Button {
                    statusFilter = localStatus
                    typeFilter = localType
                    enabledViewModes = localViewModes
                    showInvoices = localShowInvoices
                    dismiss()
                } label: {
                    Text("Apply Changes".translated())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                
                Button("Cancel".translated()) { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .padding(.bottom, 8)
            }
            .padding(24)
            .background(Color.sweeplySurface)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
        }
        .background(Color.sweeplySurface)
        .onAppear {
            localStatus = statusFilter
            localType = typeFilter
            localViewModes = enabledViewModes
            localShowInvoices = showInvoices
        }
    }
    
    private func iconFor(mode: ScheduleViewMode) -> String {
        switch mode {
        case .day: return "calendar.badge.clock"
        case .list: return "list.bullet"
        case .month: return "calendar"
        case .map: return "map.fill"
        }
    }

    private func statusColor(for status: JobStatus) -> Color {
        switch status {
        case .completed:  return Color.sweeplyAccent
        case .inProgress: return .blue
        case .scheduled:  return Color.sweeplyNavy
        case .cancelled:  return Color.sweeplyDestructive
        }
    }
}

// MARK: - Subviews

struct FilterHeader: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
                .tracking(1.0)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = Color.sweeplyNavy
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? color : Color.sweeplyBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct TypeCard: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.sweeplyNavy : Color.sweeplyBackground)
            .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sweeplyBorder, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let label: String
    let icon: String
    let isOn: Bool
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.sweeplyNavy.opacity(0.05))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyNavy)
                }

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.4))

                Spacer()

                if !enabled {
                    Text("Always on".translated())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                } else {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isOn ? Color.sweeplyAccent : Color.sweeplyBorder)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout Helper
private struct FlowLayout: View {
    let spacing: CGFloat
    let content: [AnyView]
    
    init<Views: View>(spacing: CGFloat = 8, @ViewBuilder content: () -> Views) {
        self.spacing = spacing
        // Simplistic approach for this context; in a real app, use a proper FlowLayout implementation
        // For Brewster-style chips, a simple HStack/VStack combo or a LazyVGrid is often enough.
        // Here we'll use a LazyVGrid to mimic the flow if multiple lines.
        self.content = [AnyView(content())]
    }
    
    var body: some View {
        // Using a Flexible Grid as a proxy for FlowLayout for simplicity in this task
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 200), spacing: spacing)], spacing: spacing) {
            ForEach(0..<content.count, id: \.self) { index in
                content[index]
            }
        }
    }
}

// Re-implementing FlowLayout properly for the chips
struct ChipGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    
    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    var body: some View {
        // Using HStack for now as we have few statuses. If many, we'd need a real FlowLayout.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

