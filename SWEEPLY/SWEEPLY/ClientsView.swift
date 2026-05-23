import SwiftUI

// MARK: - Sort Order

enum ClientSortOrder: String, CaseIterable {
    case nameAZ = "Name A–Z"
    case mostActive = "Most Active"
}

// MARK: - Client Frequency

enum ClientFrequency {
    case none
    case oneTime
    case recurring
    case weekly
    case biweekly
    case monthly

    var label: String? {
        switch self {
        case .none:      return nil
        case .oneTime:   return "One-time".translated()
        case .recurring: return "Recurring".translated()
        case .weekly:    return "Weekly".translated()
        case .biweekly:  return "Biweekly".translated()
        case .monthly:   return "Monthly".translated()
        }
    }

    var icon: String {
        switch self {
        case .none, .oneTime: return "1.circle"
        default:              return "arrow.triangle.2.circlepath"
        }
    }

    var isRecurring: Bool { self != .none && self != .oneTime }

    var color: Color {
        switch self {
        case .none:      return Color.sweeplyTextSub.opacity(0.5)
        case .oneTime:   return Color.sweeplyTextSub
        case .recurring: return Color.sweeplyAccent
        case .weekly:    return Color(red: 0.25, green: 0.65, blue: 0.45)  // Soft sage green
        case .biweekly:  return Color.orange
        case .monthly:   return Color.blue
        }
    }
}

// MARK: - Clients List View

struct ClientsView: View {
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(AppSession.self) private var session

    @State private var search = ""
    @State private var showAddSheet = false
    @State private var editingClient: Client? = nil
    @State private var editSheetClient: Client? = nil
    @State private var deleteTarget: Client? = nil
    @State private var appeared = false
    @State private var showFilters = false
    @AppStorage("clientsShowArchived") private var showArchived = false
    @AppStorage("clientsSortOrderRaw") private var sortOrderRaw: String = ClientSortOrder.nameAZ.rawValue

    private var sortOrder: ClientSortOrder { ClientSortOrder(rawValue: sortOrderRaw) ?? .nameAZ }
    private var sortOrderBinding: Binding<ClientSortOrder> {
        Binding(get: { ClientSortOrder(rawValue: sortOrderRaw) ?? .nameAZ }, set: { sortOrderRaw = $0.rawValue })
    }
    @State private var archiveHaptic = false
    @State private var newJobForClient: Client? = nil
    @State private var viewingClientId: UUID? = nil

    private var filterIsActive: Bool {
        showArchived || sortOrder != .nameAZ
    }

    private var displayClients: [Client] {
        let base = clientsStore.clients.filter { $0.isActive || showArchived }
        switch sortOrder {
        case .nameAZ:
            return base.sorted { $0.name < $1.name }
        case .mostActive:
            return base.sorted { jobCount(for: $0) > jobCount(for: $1) }
        }
    }

    private var displayJobs: [Job] { jobsStore.jobs }

    private func jobCount(for client: Client) -> Int {
        displayJobs.filter { $0.clientId == client.id }.count
    }

    private struct ClientDerived: Identifiable {
        let id: UUID
        let client: Client
        let jobCount: Int
        let frequency: ClientFrequency
    }

    private var clientsWithDerived: [ClientDerived] {
        let jobs = displayJobs
        return displayClients.map { client in
            let clientJobs = jobs.filter { $0.clientId == client.id }
            let count = clientJobs.count
            let freq: ClientFrequency
            if count == 0 {
                freq = .none
            } else {
                let hasRecurring = clientJobs.contains { $0.isRecurring }
                if !hasRecurring {
                    freq = .oneTime
                } else {
                    let recurringDates = clientJobs
                        .filter { $0.isRecurring }
                        .map { $0.date }
                        .sorted()
                    if recurringDates.count < 2 {
                        freq = .recurring
                    } else {
                        let gaps = zip(recurringDates, recurringDates.dropFirst()).map {
                            Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 0
                        }
                        let avgGap = gaps.reduce(0, +) / gaps.count
                        switch avgGap {
                        case 0...9:  freq = .weekly
                        case 10...18: freq = .weekly
                        case 19...25: freq = .biweekly
                        case 26...35: freq = .monthly
                        default:      freq = .recurring
                        }
                    }
                }
            }
            return ClientDerived(id: client.id, client: client, jobCount: count, frequency: freq)
        }
    }

    private var filteredClients: [ClientDerived] {
        guard !search.isEmpty else { return clientsWithDerived }
        return clientsWithDerived.filter {
            $0.client.name.localizedCaseInsensitiveContains(search) ||
            $0.client.address.localizedCaseInsensitiveContains(search) ||
            $0.client.city.localizedCaseInsensitiveContains(search)
        }
    }

    // Stats for the summary strip
    private var recurringCount: Int { clientsWithDerived.filter { $0.frequency.isRecurring }.count }
    private var oneTimeCount: Int { clientsWithDerived.filter { $0.frequency == .oneTime }.count }
    private var avgJobsPerClient: Int {
        let total = clientsWithDerived.count
        guard total > 0 else { return 0 }
        let totalJobs = clientsWithDerived.reduce(0) { $0 + $1.jobCount }
        return totalJobs / total
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.bottom, 14)

                    VStack(spacing: 12) {
                        searchAndFilterRow
                        statsStrip
                    }
                    .padding(.horizontal, 20)

                    clientList
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $viewingClientId) { id in
                ClientDetailView(clientId: id)
            }
            .refreshable {
                await clientsStore.load(isAuthenticated: session.isAuthenticated)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .task {
            await clientsStore.load(isAuthenticated: session.isAuthenticated)
        }
        .sheet(isPresented: $showAddSheet) {
            NewClientForm()
        }
        .sheet(item: $editSheetClient) { client in
            NewClientForm(editingClient: client)
        }
        .sheet(isPresented: $showFilters) {
            ClientFiltersSheet(showArchived: $showArchived, sortOrder: sortOrderBinding)
                .presentationDetents([.medium])
        }
        .sheet(item: $newJobForClient) { client in
            NewJobForm(preselectClient: client)
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.name ?? "client")?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete".translated(), role: .destructive) {
                if let t = deleteTarget {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task {
                        _ = await clientsStore.delete(id: t.id)
                        await MainActor.run { deleteTarget = nil }
                    }
                }
            }
        } message: {
            Text("This will permanently remove this client. This action cannot be undone.".translated())
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(
                eyebrow: nil,
                title: "Clients".translated(),
                subtitle: showArchived
                    ? "%d total clients".translated(with: displayClients.count)
                    : "%d active clients".translated(with: displayClients.count)
            ) {
                HeaderIconButton(systemName: "plus", foregroundColor: .white, backgroundColor: .sweeplyNavy) {
                    showAddSheet = true
                }
            }

            if let err = clientsStore.lastError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyDestructive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Search + Filter Row
    private var searchAndFilterRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                TextField("Search by name or address...".translated(), text: $search)
                    .font(.system(size: 15))
                    .tint(Color.sweeplyAccent)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFilters = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.sweeplySurface)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                        )

                    if filterIsActive {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.sweeplyBackground, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats Strip
    private var statsStrip: some View {
        HStack(spacing: 0) {
            StatPill(value: "\(displayClients.count)", label: "Total".translated())
            statsDivider
            StatPill(value: "\(recurringCount)", label: "Recurring".translated())
            statsDivider
            StatPill(value: "\(oneTimeCount)", label: "One-time".translated())
            statsDivider
            StatPill(value: "\(avgJobsPerClient)", label: "Avg jobs".translated())
        }
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var statsDivider: some View {
        Rectangle()
            .fill(Color.sweeplyBorder)
            .frame(width: 1, height: 30)
    }

    // MARK: - Client List
    private var clientList: some View {
        Group {
            if clientsStore.isLoading && filteredClients.isEmpty {
                SkeletonList(count: 5)
                    .padding(.horizontal, 20)
            } else if filteredClients.isEmpty {
                emptyState
            } else {
                rosterCard
                    .padding(.horizontal, 20)
                    .sensoryFeedback(.impact(weight: .heavy), trigger: archiveHaptic)
            }
        }
    }

    private var rosterCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredClients.enumerated()), id: \.element.id) { index, item in
                NavigationLink(
                    destination: ClientDetailView(clientId: item.client.id)
                ) {
                    ClientRow(
                        client: item.client,
                        jobCount: item.jobCount,
                        frequency: item.frequency,
                        onView: { viewingClientId = item.client.id },
                        onEdit: { editSheetClient = item.client },
                        onDelete: { deleteTarget = item.client },
                        onToggleArchive: {
                            archiveHaptic.toggle()
                            Task {
                                var updated = item.client
                                updated.isActive.toggle()
                                _ = await clientsStore.update(updated)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        let digits = item.client.phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "tel://\(digits)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Call".translated(), systemImage: "phone.fill")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        newJobForClient = item.client
                    } label: {
                        Label("New Job".translated(), systemImage: "plus.circle.fill")
                    }
                    .tint(Color.sweeplyNavy)

                    Button {
                        let digits = item.client.phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "sms:\(digits)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Text".translated(), systemImage: "message.fill")
                    }
                    .tint(.blue)
                }

                if index < filteredClients.count - 1 {
                    Divider()
                        .padding(.leading, 82)
                        .background(Color.sweeplySurface)
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.08))
                    .frame(width: 96, height: 96)
                Image(systemName: search.isEmpty ? "person.2.fill" : "magnifyingglass")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent.opacity(0.75))
            }
            VStack(spacing: 10) {
                Text(search.isEmpty
                     ? "Your client roster starts here".translated()
                     : "No matches".translated())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .multilineTextAlignment(.center)
                Text(search.isEmpty
                     ? "Add your first client to start booking jobs and sending invoices.".translated()
                     : "Nothing matches \"\(search)\". Try a different name or address.".translated())
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
            }
            if search.isEmpty {
                Button {
                    editingClient = nil
                    showAddSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Add Your First Client".translated())
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(Color.sweeplyNavy)
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
                .tracking(-0.5)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Client Row

private struct ClientRow: View {
    let client: Client
    let jobCount: Int
    let frequency: ClientFrequency
    let onView: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleArchive: () -> Void

    @State private var isPressed = false

    private var secondaryText: String? {
        let addressParts = [client.address, client.city].filter { !$0.isEmpty }
        if !addressParts.isEmpty {
            return addressParts.joined(separator: ", ")
        }
        if !client.phone.isEmpty { return client.phone }
        if !client.email.isEmpty { return client.email }
        return nil
    }

    private var secondaryIcon: String {
        let hasAddress = !client.address.isEmpty || !client.city.isEmpty
        if hasAddress { return "mappin" }
        if !client.phone.isEmpty { return "phone" }
        return "envelope"
    }

    var body: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(client.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(client.isActive ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !client.isActive {
                        Text("ARCHIVED".translated())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.5)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.sweeplyBackground)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }

                if let secondary = secondaryText {
                    HStack(spacing: 4) {
                        Image(systemName: secondaryIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(secondary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(jobCount)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                        .tracking(-0.5)
                    Text("jobs".translated())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.5)
                        .textCase(.uppercase)
                }
                if let freqLabel = frequency.label {
                    HStack(spacing: 3) {
                        Image(systemName: frequency.icon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(frequency.color)
                        Text(freqLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(frequency.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(frequency.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Menu {
                Button { onView() } label: { Label("View Profile".translated(), systemImage: "person.fill") }
                Divider()
                Button { onEdit() } label: { Label("Edit Client".translated(), systemImage: "pencil") }
                Button { onToggleArchive() } label: {
                    Label(
                        client.isActive ? "Archive Client".translated() : "Unarchive Client".translated(),
                        systemImage: client.isActive ? "archivebox" : "archivebox.fill"
                    )
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete Client".translated(), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isPressed ? Color.sweeplyBackground.opacity(0.4) : Color.sweeplySurface)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onView()
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: client.isActive
                            ? [Color.sweeplyNavy, Color.sweeplyNavy.opacity(0.82)]
                            : [Color.sweeplyTextSub.opacity(0.35), Color.sweeplyTextSub.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
            Text(String(client.name.prefix(1)).uppercased())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Form Helpers Moved to NewClientForm.swift

// MARK: - Client Filters Sheet

private struct ClientFiltersSheet: View {
    @Binding var showArchived: Bool
    @Binding var sortOrder: ClientSortOrder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack {
                Text("Filter Clients".translated())
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Button("Done".translated()) { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Status section
            VStack(alignment: .leading, spacing: 12) {
                Text("STATUS".translated())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                    .padding(.horizontal, 20)

                Toggle(isOn: $showArchived) {
                    HStack(spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 20)
                        Text("Show archived clients".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                .tint(Color.sweeplyAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }

            // Sort section
            VStack(alignment: .leading, spacing: 12) {
                Text("SORT BY".translated())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(ClientSortOrder.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                sortOrder = option
                            }
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Spacer()
                                if sortOrder == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyAccent)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if option != ClientSortOrder.allCases.last {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }
}

// MARK: - Preview

#Preview {
    ClientsView()
        .environment(AppSession())
        .environment(ClientsStore())
}
