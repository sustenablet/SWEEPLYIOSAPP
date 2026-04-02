import SwiftUI

// MARK: - Clients List View

struct ClientsView: View {
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(AppSession.self) private var session

    @State private var search = ""
    @State private var showAddSheet = false
    @State private var editingClient: Client? = nil
    @State private var deleteTarget: Client? = nil
    @State private var appeared = false

    private let allJobs     = MockData.makeJobs()
    private let allInvoices = MockData.makeInvoices()

    /// Live list from Supabase when present; otherwise mock clients so the screen is reviewable without SQL.
    private var displayClients: [Client] {
        let stored = clientsStore.clients
        if !stored.isEmpty { return stored }
        if clientsStore.isLoading { return [] }
        return MockData.clients
    }

    private var isShowingSampleClients: Bool {
        clientsStore.clients.isEmpty && !clientsStore.isLoading
    }

    private var filtered: [Client] {
        guard !search.isEmpty else { return displayClients }
        return displayClients.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.address.localizedCaseInsensitiveContains(search) ||
            $0.city.localizedCaseInsensitiveContains(search)
        }
    }

    private func jobCount(for client: Client) -> Int {
        allJobs.filter { $0.clientId == client.id }.count
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
            ClientFormSheet(
                clientsStore: clientsStore,
                userId: session.userId,
                editingClient: editingClient,
                onDismiss: { showAddSheet = false }
            )
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.name ?? "client")?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let t = deleteTarget {
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DIRECTORY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    .tracking(1.5)
                Text("Clients")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 20, height: 2)
                        .clipShape(Capsule())
                    Text("\(displayClients.count) total clients")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                if clientsStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .padding(.top, 4)
                }
                if let err = clientsStore.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyDestructive)
                        .padding(.top, 4)
                }
                if isShowingSampleClients {
                    Text("Sample data")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.sweeplyAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }
            }
            Spacer()
            Button {
                editingClient = nil
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 4)
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
            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(filtered) { client in
                    NavigationLink(
                        destination: ClientDetailView(
                            client: client,
                            allJobs: allJobs,
                            allInvoices: allInvoices
                        )
                    ) {
                        ClientCard(
                            client: client,
                            jobCount: jobCount(for: client),
                            onEdit: {
                                editingClient = client
                                showAddSheet = true
                            },
                            onDelete: { deleteTarget = client }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text(search.isEmpty ? "No clients yet" : "No clients found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(search.isEmpty ? "Add your first client to get started." : "Try a different search term.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                .multilineTextAlignment(.center)
            if search.isEmpty {
                Button {
                    editingClient = nil
                    showAddSheet = true
                } label: {
                    Text("Add Client")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.sweeplyNavy)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Client Card

private struct ClientCard: View {
    let client: Client
    let jobCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top row
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.sweeplyNavy)
                        .frame(width: 40, height: 40)
                    Text(String(client.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Name + notes
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    if !client.notes.isEmpty {
                        Text(client.notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Job count + menu
                HStack(spacing: 8) {
                    Text("\(jobCount) jobs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.sweeplyBackground)
                        .clipShape(Capsule())

                    Menu {
                        Button { onEdit() } label: {
                            Label("Edit Client", systemImage: "pencil")
                        }
                        Button(role: .destructive) { onDelete() } label: {
                            Label("Delete Client", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            // Contact details
            if !client.address.isEmpty || !client.phone.isEmpty || !client.email.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    if !client.address.isEmpty {
                        ClientInfoRow(icon: "mappin", text: "\(client.address), \(client.city), \(client.state)")
                    }
                    if !client.phone.isEmpty {
                        ClientInfoRow(icon: "phone", text: client.phone)
                    }
                    if !client.email.isEmpty {
                        ClientInfoRow(icon: "envelope", text: client.email)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 52) // align with name column
            }
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct ClientInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineLimit(1)
        }
    }
}

// MARK: - Client Form Sheet

struct ClientFormSheet: View {
    let clientsStore: ClientsStore
    let userId: UUID?
    let editingClient: Client?
    let onDismiss: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var preferredService: ServiceType? = nil
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var entryInstructions = ""
    @State private var notes = ""
    @State private var isSaving = false

    init(clientsStore: ClientsStore, userId: UUID?, editingClient: Client?, onDismiss: @escaping () -> Void) {
        self.clientsStore = clientsStore
        self.userId = userId
        self.editingClient = editingClient
        self.onDismiss = onDismiss

        if let c = editingClient {
            let parts = c.name.split(separator: " ", maxSplits: 1)
            _firstName = State(initialValue: parts.first.map(String.init) ?? "")
            _lastName  = State(initialValue: parts.dropFirst().first.map(String.init) ?? "")
            _email  = State(initialValue: c.email)
            _phone  = State(initialValue: c.phone)
            _preferredService = State(initialValue: c.preferredService)
            _street = State(initialValue: c.address)
            _city   = State(initialValue: c.city)
            _state  = State(initialValue: c.state)
            _zip    = State(initialValue: c.zip)
            _entryInstructions = State(initialValue: c.entryInstructions)
            _notes  = State(initialValue: c.notes)
        }
    }

    private var isValid: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    formSection("Contact Info") {
                        HStack(spacing: 12) {
                            formField("First Name *", text: $firstName, placeholder: "First")
                            formField("Last Name", text: $lastName, placeholder: "Last")
                        }
                        formField("Email", text: $email, placeholder: "email@example.com", keyboard: .emailAddress)
                        formField("Phone", text: $phone, placeholder: "(305) 555-0000", keyboard: .phonePad)
                    }

                    formSection("Service Preference") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Preferred Service")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                            Picker("Preferred Service", selection: $preferredService) {
                                Text("None").tag(Optional<ServiceType>.none)
                                ForEach(ServiceType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(Optional(type))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
                        }
                    }

                    formSection("Service Address") {
                        formField("Street", text: $street, placeholder: "123 Main St")
                        HStack(spacing: 12) {
                            formField("City", text: $city, placeholder: "City")
                            formField("State", text: $state, placeholder: "FL")
                                .frame(maxWidth: 70)
                            formField("ZIP", text: $zip, placeholder: "33101", keyboard: .numberPad)
                                .frame(maxWidth: 90)
                        }
                    }

                    formSection("Additional Info") {
                        formField("Entry Instructions", text: $entryInstructions, placeholder: "Gate code, key location...")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyTextSub)
                            TextEditor(text: $notes)
                                .font(.system(size: 15))
                                .frame(minHeight: 80)
                                .padding(10)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
                                .overlay(alignment: .topLeading) {
                                    if notes.isEmpty {
                                        Text("Pet info, special requests...")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 18)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }

                    // Bottom padding for safe area
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle(editingClient == nil ? "New Client" : "Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingClient == nil ? "Save" : "Update") {
                        Task { await saveClient() }
                    }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isValid && !isSaving ? Color.sweeplyNavy : Color.sweeplyTextSub)
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func saveClient() async {
        let fullName = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))".trimmingCharacters(in: .whitespaces)
        isSaving = true
        defer { isSaving = false }

        if let existing = editingClient {
            var updated = existing
            updated.name = fullName
            updated.email = email
            updated.phone = phone
            updated.preferredService = preferredService
            updated.address = street
            updated.city = city
            updated.state = state
            updated.zip = zip
            updated.entryInstructions = entryInstructions
            updated.notes = notes
            let ok = await clientsStore.update(updated)
            if ok { onDismiss() }
        } else {
            let newClient = Client(
                id: UUID(),
                name: fullName,
                email: email,
                phone: phone,
                address: street,
                city: city,
                state: state,
                zip: zip,
                preferredService: preferredService,
                entryInstructions: entryInstructions,
                notes: notes
            )
            let uid = userId ?? UUID()
            let ok = await clientsStore.insert(newClient, userId: uid)
            if ok { onDismiss() }
        }
    }

    // MARK: - Form Helpers
    @ViewBuilder
    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    .tracking(1.2)
                Rectangle()
                    .fill(Color.sweeplyBorder)
                    .frame(height: 1)
            }
            content()
        }
    }

    @ViewBuilder
    private func formField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }
}

// MARK: - Preview

#Preview {
    ClientsView()
        .environment(AppSession())
        .environment(ClientsStore())
}

