import SwiftUI

// MARK: - Sort Order

enum ClientSortOrder: String, CaseIterable {
    case nameAZ = "Name A–Z"
    case mostActive = "Most Active"
}

// MARK: - Clients List View

struct ClientsView: View {
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(JobsStore.self) private var jobsStore
    @Environment(AppSession.self) private var session

    @State private var search = ""
    @State private var showAddSheet = false
    @State private var editingClient: Client? = nil
    @State private var deleteTarget: Client? = nil
    @State private var appeared = false
    @State private var showFilters = false
    @State private var showArchived = false
    @State private var sortOrder: ClientSortOrder = .nameAZ
    @State private var archiveHaptic = false
    @State private var newJobForClient: Client? = nil

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

    private var filtered: [Client] {
        guard !search.isEmpty else { return displayClients }
        return displayClients.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.address.localizedCaseInsensitiveContains(search) ||
            $0.city.localizedCaseInsensitiveContains(search)
        }
    }

    private func jobCount(for client: Client) -> Int {
        displayJobs.filter { $0.clientId == client.id }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    clientList
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarHidden(true)
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
            NewClientForm(editingClient: editingClient)
        }
        .sheet(isPresented: $showFilters) {
            ClientFiltersSheet(showArchived: $showArchived, sortOrder: $sortOrder)
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
            Button("Delete", role: .destructive) {
                if let t = deleteTarget {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task {
                        _ = await clientsStore.delete(id: t.id)
                        await MainActor.run { deleteTarget = nil }
                    }
                }
            }
        } message: {
            Text("This will permanently remove this client. This action cannot be undone.")
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(
                eyebrow: nil,
                title: "Clients",
                subtitle: "\(displayClients.count) \(showArchived ? "total" : "active") clients"
            ) {
                HStack(spacing: 8) {
                    HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                        showFilters = true
                    }
                    HeaderIconButton(systemName: "plus", foregroundColor: .white, backgroundColor: .sweeplyNavy) {
                        editingClient = nil
                        showAddSheet = true
                    }
                }
            }

            if let err = clientsStore.lastError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyDestructive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyTextSub)
            TextField("Search by name or address...", text: $search)
                .font(.system(size: 15))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    // MARK: - Client List
    private var clientList: some View {
        LazyVStack(spacing: 10) {
            if clientsStore.isLoading && filtered.isEmpty {
                SkeletonList(count: 5)
            } else if filtered.isEmpty {
                emptyState
            } else {
                ForEach(filtered) { client in
                    NavigationLink(
                        destination: ClientDetailView(
                            clientId: client.id
                        )
                    ) {
                        ClientCard(
                            client: client,
                            jobCount: jobCount(for: client),
                            onEdit: {
                                editingClient = client
                                showAddSheet = true
                            },
                            onDelete: { deleteTarget = client },
                            onToggleArchive: {
                                archiveHaptic.toggle()
                                Task {
                                    var updated = client
                                    updated.isActive.toggle()
                                    _ = await clientsStore.update(updated)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            let digits = client.phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel://\(digits)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            newJobForClient = client
                        } label: {
                            Label("New Job", systemImage: "plus.circle.fill")
                        }
                        .tint(Color.sweeplyNavy)

                        Button {
                            let digits = client.phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "sms:\(digits)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Text", systemImage: "message.fill")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.impact(weight: .heavy), trigger: archiveHaptic)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: search.isEmpty ? "person.2.fill" : "magnifyingglass")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent.opacity(0.7))
            }
            VStack(spacing: 8) {
                Text(search.isEmpty ? "No clients yet" : "No clients found")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(search.isEmpty
                     ? "Add your first client to start booking\njobs and sending invoices."
                     : "No clients match \"\(search)\".\nTry a different name or address.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            if search.isEmpty {
                Button {
                    editingClient = nil
                    showAddSheet = true
                } label: {
                    Text("Add Your First Client")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.sweeplyNavy)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - Client Card

private struct ClientCard: View {
    let client: Client
    let jobCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleArchive: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color.sweeplySurface

            Capsule()
                .fill(client.isActive ? Color.sweeplyAccent : Color.sweeplyBorder)
                .frame(width: 3)
                .padding(.vertical, 12)

            HStack(spacing: 14) {
                Color.clear.frame(width: 3)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(client.isActive ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.25))
                        .frame(width: 46, height: 46)
                    Text(String(client.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(client.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(client.isActive ? Color.sweeplyNavy : Color.sweeplyTextSub)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !client.isActive {
                            Text("ARCHIVED")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.sweeplyBackground)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Text("\(jobCount)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("jobs")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }

                    if let service = client.preferredService {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text(service.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    } else if !client.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text([client.address, client.city].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if !client.phone.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "phone")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text(client.phone)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    } else if !client.email.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Text(client.email)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                Menu {
                    Button { onEdit() } label: { Label("Edit Client", systemImage: "pencil") }
                    Button { onToggleArchive() } label: {
                        Label(
                            client.isActive ? "Archive Client" : "Unarchive Client",
                            systemImage: client.isActive ? "archivebox" : "archivebox.fill"
                        )
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Client", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
                Text("Filter Clients")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Status section
            VStack(alignment: .leading, spacing: 12) {
                Text("STATUS")
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
                        Text("Show archived clients")
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
                Text("SORT BY")
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
