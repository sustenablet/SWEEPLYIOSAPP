import SwiftUI

struct JobFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var statusFilter: JobStatus?
    @Binding var typeFilter: String
    @Binding var enabledViewModes: Set<ScheduleViewMode>
    
    // Internal state to allow "Cancel"
    @State private var localStatus: JobStatus?
    @State private var localType: String = "All"
    @State private var localViewModes: Set<ScheduleViewMode> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filters")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Clear") {
                    localStatus = nil
                    localType = "All"
                    localViewModes = Set(ScheduleViewMode.allCases)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(24)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Status Group
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STATUS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(1.0)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            FilterTile(label: "Any", isSelected: localStatus == nil) {
                                localStatus = nil
                            }
                            
                            ForEach(JobStatus.allCases, id: \.self) { status in
                                FilterTile(label: status.rawValue.capitalized, isSelected: localStatus == status) {
                                    localStatus = status
                                }
                            }
                        }
                    }
                    
                    // Job Type Group
                    VStack(alignment: .leading, spacing: 12) {
                        Text("JOB TYPE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(1.0)
                        
                        VStack(spacing: 8) {
                            TypeRow(label: "All Jobs", icon: "square.grid.2x2", isSelected: localType == "All") {
                                localType = "All"
                            }
                            TypeRow(label: "Recurring", icon: "arrow.triangle.2.circlepath", isSelected: localType == "Recurring") {
                                localType = "Recurring"
                            }
                            TypeRow(label: "One-time", icon: "calendar", isSelected: localType == "One-time") {
                                localType = "One-time"
                            }
                        }
                    }
                    
                    // View Modes Group
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VIEW MODES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(1.0)
                        
                        VStack(spacing: 8) {
                            ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                                ViewModeRow(
                                    label: mode.rawValue,
                                    icon: iconFor(mode: mode),
                                    isSelected: localViewModes.contains(mode)
                                ) {
                                    if localViewModes.contains(mode) {
                                        localViewModes.remove(mode)
                                    } else {
                                        localViewModes.insert(mode)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Apply Button
            Button {
                statusFilter = localStatus
                typeFilter = localType
                enabledViewModes = localViewModes
                dismiss()
            } label: {
                Text("Apply Filters")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
        .background(Color.sweeplySurface)
        .onAppear {
            localStatus = statusFilter
            localType = typeFilter
            localViewModes = enabledViewModes
        }
    }
    
    private func iconFor(mode: ScheduleViewMode) -> String {
        switch mode {
        case .day: return "calendar"
        case .list: return "list.bullet"
        case .month: return "calendar.badge.month"
        case .map: return "map"
        }
    }
}

private struct FilterTile: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.sweeplyNavy : Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct TypeRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                Text(label)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.sweeplyNavy : Color.sweeplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ViewModeRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                Text(label)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.sweeplyNavy : Color.sweeplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}
