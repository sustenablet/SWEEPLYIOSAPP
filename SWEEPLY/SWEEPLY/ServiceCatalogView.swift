import SwiftUI

// MARK: - Service Tab
private enum ServiceTab {
    case services
    case extras
}

// MARK: - Service Catalog View
// Standalone full-screen catalog management.
// Presented as a sheet from BusinessView ("View All") and SettingsView (Business tab).

struct ServiceCatalogView: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)   private var session

    var addonsOnly: Bool = false

    @State private var selectedTab: ServiceTab = .services
    @State private var serviceEditorState: ServiceCatalogEditorState?

    // Only show tabs if not in addonsOnly mode
    private var showTabs: Bool { !addonsOnly }

    @State private var feedbackMessage: String?
    @State private var feedbackIsSuccess = false

    private var currentTabIsAddon: Bool {
        selectedTab == .extras
    }

    private var services: [BusinessService] {
        (profileStore.profile ?? MockData.profile).settings.hydratedServiceCatalog
            .filter { $0.isAddon == currentTabIsAddon }
    }

    private var servicesCount: Int {
        (profileStore.profile ?? MockData.profile).settings.hydratedServiceCatalog
            .filter { !$0.isAddon }.count
    }

    private var extrasCount: Int {
        (profileStore.profile ?? MockData.profile).settings.hydratedServiceCatalog
            .filter { $0.isAddon }.count
    }

    private var navTitle: String { addonsOnly ? "Job Extras" : "Service Catalog" }
    private var sectionTitle: String {
        if addonsOnly { return "Extras".translated() }
        return selectedTab == .extras ? "Extras" : "Services"
    }
    private var sectionSubtitle: String {
        if addonsOnly || selectedTab == .extras {
            return "Add-ons charged on top of the main service".translated()
        }
        return "Primary services offered".translated()
    }
    private var emptyTitle: String {
        if addonsOnly || selectedTab == .extras {
            return "No extras yet".translated()
        }
        return "No services yet".translated()
    }
    private var emptyBody: String {
        if addonsOnly || selectedTab == .extras {
            return "Add small add-ons like laundry, dishes, or window cleaning — these appear as extras when booking a job.".translated()
        }
        return "Create your service catalog — these appear\nin new job and invoice pickers."
    }
    private var emptyButtonLabel: String {
        if addonsOnly || selectedTab == .extras {
            return "Add First Extra".translated()
        }
        return "Add First Service".translated()
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 4) {
            tabButton(.services, label: "Services", count: servicesCount)
            tabButton(.extras, label: "Extras", count: extrasCount)
        }
    }

    private func tabButton(_ tab: ServiceTab, label: String, count: Int) -> some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: selectedTab == tab ? .bold : .medium))
                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyTextSub)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Color.sweeplyNavy : Color.clear)
            .foregroundStyle(selectedTab == tab ? .white : Color.sweeplyNavy)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selectedTab == tab ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showTabs {
                        tabPicker
                    }

                    if let msg = feedbackMessage {
                        feedbackBanner(message: msg, isSuccess: feedbackIsSuccess)
                    }

                    if services.isEmpty {
                        emptyState
                    } else {
                        catalogSection(
                            title: sectionTitle,
                            subtitle: sectionSubtitle,
                            services: services
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 24)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let isAddon = addonsOnly || selectedTab == .extras
                        serviceEditorState = ServiceCatalogEditorState(defaultAddon: isAddon, lockedAddon: addonsOnly)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("Add".translated())
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                }
            }
            .sheet(item: $serviceEditorState) { state in
                ServiceCatalogEditorSheet(state: state) { result in
                    Task { await saveChange(from: result) }
                }
            }
        }
    }

    // MARK: - Section Builder

    private func catalogSection(title: String, subtitle: String, services: [BusinessService]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .tracking(0.3)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            ForEach(services) { service in
                ServiceCatalogRow(
                    service: service,
                    onEdit: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        serviceEditorState = ServiceCatalogEditorState(service: service, lockedAddon: addonsOnly)
                    },
                    onDelete: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await deleteService(service.id) }
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.sweeplyAccent.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.sweeplyAccent)
                }

                VStack(spacing: 8) {
                    Text(emptyTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(emptyBody)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    serviceEditorState = ServiceCatalogEditorState(defaultAddon: addonsOnly, lockedAddon: addonsOnly)
                } label: {
                    Label(emptyButtonLabel, systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .background(Color.sweeplyNavy)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Feedback Banner

    @ViewBuilder
    private func feedbackBanner(message: String, isSuccess: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSuccess ? Color.sweeplyAccent : Color.sweeplyWarning)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
        }
        .padding(13)
        .background((isSuccess ? Color.sweeplyAccent : Color.sweeplyWarning).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    private func saveChange(from state: ServiceCatalogEditorState) async {
        guard let userId = session.userId else { return }
        var profile = profileStore.profile ?? MockData.profile
        var list = profile.settings.hydratedServiceCatalog
        let name  = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = Double(state.priceText) ?? 0

        if let sid = state.serviceID, let idx = list.firstIndex(where: { $0.id == sid }) {
            list[idx].name    = name
            list[idx].price   = price
            list[idx].isAddon = state.isAddon
        } else {
            list.append(BusinessService(name: name, price: price, isAddon: state.isAddon))
        }

        profile.settings.services = list
        let success = await profileStore.save(profile, userId: userId)
        feedbackIsSuccess = success
        feedbackMessage   = success
            ? "\(state.isEditing ? "Service updated." : "Service added.")"
            : (profileStore.lastError ?? "Unable to save.")
    }

    private func deleteService(_ id: UUID) async {
        guard let userId = session.userId else { return }
        var profile = profileStore.profile ?? MockData.profile
        profile.settings.services = profile.settings.hydratedServiceCatalog.filter { $0.id != id }
        let success = await profileStore.save(profile, userId: userId)
        feedbackIsSuccess = success
        feedbackMessage   = success ? "Service removed." : (profileStore.lastError ?? "Unable to delete.")
    }
}
