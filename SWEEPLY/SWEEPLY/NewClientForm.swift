import SwiftUI
import Contacts
import ContactsUI

struct NewClientForm: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self)    private var session

    // Edit mode
    var editingClient: Client? = nil
    var onSave: ((Client) -> Void)? = nil

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
    @State private var showContactPicker = false
    @State private var showValidationErrors = false
    @State private var selectedAvatarTone: ClientAvatarTone = .slate
    @State private var didManuallySelectAvatarTone = false
    @State private var showingCreatePreview = false
    @State private var showAvatarTonePicker = false

    private var fallbackSettings: AppSettings {
        var settings = AppSettings()
        settings.services = AppSettings.defaultServiceCatalog.filter { !$0.isAddon }
        return settings
    }

    private var serviceCatalog: [BusinessService] {
        let settings = profileStore.profile?.settings ?? fallbackSettings
        let allServices = settings.hydratedServiceCatalog
        return allServices.filter { !$0.isAddon }
    }

    private var isEmailValid: Bool {
        guard !email.isEmpty else { return true }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private var isPhoneValid: Bool {
        guard !phone.isEmpty else { return true }
        return phone.filter(\.isNumber).count >= 10
    }

    private var preferredServiceLabel: String {
        guard let preferredService else { return "Select Service...".translated() }
        if let service = serviceCatalog.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(preferredService.rawValue) == .orderedSame
        }) {
            return "\(service.name) · \(service.price.currency)"
        }
        return preferredService.rawValue
    }

    private var previewName: String {
        let combined = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))"
            .trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "Client Preview".translated() : combined
    }

    private var previewInitials: String {
        let parts = previewName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        switch parts.count {
        case 0:
            return "C"
        case 1:
            return String(parts[0].prefix(1)).uppercased()
        default:
            let first = parts.first?.prefix(1) ?? ""
            let last = parts.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        }
    }

    private var previewAddress: String {
        [street, city, state].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var previewPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var previewEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var previewPreferredService: String? {
        guard let preferredService else { return nil }
        return preferredService.rawValue
    }

    private var previewEntryInstructions: String? {
        let trimmed = entryInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var previewNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(editingClient == nil ? "New Client" : "Edit Client")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("Cancel".translated()) { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(24)

                ScrollView {
                    VStack(spacing: 24) {
                        // Import from Contacts button (new client only)
                        if editingClient == nil {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showContactPicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Import from Contacts".translated())
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(Color.sweeplyNavy)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.sweeplyNavy.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyNavy.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        if editingClient != nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("AVATAR".translated())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .tracking(1.0)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAvatarTonePicker.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(selectedAvatarTone.backgroundColor)
                                                .frame(width: 56, height: 56)

                                            Text(editingClient?.avatarInitials ?? previewInitials)
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundStyle(selectedAvatarTone.foregroundColor)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Client Avatar".translated())
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.sweeplyNavy)
                                            Text("Tap the avatar to change the color.".translated())
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                        }

                                        Spacer()

                                        Image(systemName: showAvatarTonePicker ? "chevron.up" : "paintpalette")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }
                                    .padding(14)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)

                                if showAvatarTonePicker {
                                    avatarTonePicker
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }

                        // Contact
                        VStack(alignment: .leading, spacing: 14) {
                            Text("CONTACT INFO".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                            HStack(spacing: 12) {
                                FormTextField(
                                    label: "First Name *".translated(),
                                    text: $firstName,
                                    placeholder: "John".translated(),
                                    errorMessage: showValidationErrors && firstName.isEmpty ? "First name is required".translated() : nil
                                )
                                FormTextField(label: "Last Name".translated(), text: $lastName, placeholder: "Doe".translated())
                            }
                            FormTextField(
                                label: "Email".translated(),
                                text: $email,
                                placeholder: "john@example.com".translated(),
                                keyboard: .emailAddress,
                                errorMessage: showValidationErrors && !isEmailValid ? "Enter a valid email address".translated() : nil
                            )
                            FormTextField(
                                label: "Phone".translated(),
                                text: $phone,
                                placeholder: "(555) 000-0000".translated(),
                                keyboard: .phonePad,
                                errorMessage: showValidationErrors && !isPhoneValid ? "Phone number must be at least 10 digits".translated() : nil
                            )
                        }

                        // Preferences
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PREFERENCES".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preferred Service".translated()).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                                Menu {
                                    Button("None".translated()) { preferredService = nil }
                                    ForEach(serviceCatalog) { service in
                                        if !service.isAddon {
                                            Button("\(service.name) · \(service.price.currency)") {
                                                preferredService = ServiceType(rawValue: service.name)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(preferredServiceLabel)
                                            .foregroundStyle(preferredService == nil ? Color.sweeplyTextSub : .primary)
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.system(size: 12))
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(Color.sweeplyBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
                                }
                            }
                        }

                        // Address
                        VStack(alignment: .leading, spacing: 14) {
                            Text("SERVICE ADDRESS".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                            AddressAutocompleteTF(
                                label: "Street Address".translated(),
                                street: $street,
                                city: $city,
                                state: $state,
                                zip: $zip
                            )
                            HStack(spacing: 12) {
                                FormTextField(label: "City".translated(), text: $city, placeholder: "Miami".translated())
                                StatePickerField(label: "State".translated(), state: $state).frame(width: 90)
                                FormTextField(label: "ZIP".translated(), text: $zip, placeholder: "33101".translated(), keyboard: .numberPad).frame(width: 90)
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 14) {
                            Text("OPERATIONAL NOTES".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                            FormTextField(label: "Entry Instructions".translated(), text: $entryInstructions, placeholder: "Gate code #1234...".translated())

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes".translated()).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                                TextEditor(text: $notes)
                                    .frame(minHeight: 100)
                                    .padding(12)
                                    .background(Color.sweeplyBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Save
                Button {
                    handlePrimaryAction()
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white).padding(.trailing, 8) }
                        Text(isSaving ? "Saving..." : (editingClient == nil ? "Create Client" : "Update Client"))
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isSaving ? Color.sweeplyBorder : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaving)
                .padding(24)
            }

            if showingCreatePreview {
                createPreviewOverlay
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done".translated()) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            }
        }
        .background(Color.sweeplySurface)
        .sheet(isPresented: $showContactPicker) {
            ContactPickerView { contact in
                if let first = contact.givenName.isEmpty ? nil : contact.givenName {
                    firstName = first
                }
                if let last = contact.familyName.isEmpty ? nil : contact.familyName {
                    lastName = last
                }
                if let emailAddr = contact.emailAddresses.first {
                    email = String(emailAddr.value)
                }
                if let phoneNum = contact.phoneNumbers.first {
                    phone = phoneNum.value.stringValue
                }
                if let postalAddr = contact.postalAddresses.first {
                    let addr = postalAddr.value
                    street = addr.street
                    city = addr.city
                    state = addr.state
                    zip = addr.postalCode
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .onAppear {
            if let c = editingClient {
                let parts = c.name.split(separator: " ", maxSplits: 1)
                firstName = parts.first.map(String.init) ?? ""
                lastName  = parts.dropFirst().first.map(String.init) ?? ""
                email = c.email
                phone = c.phone
                preferredService = c.preferredService
                street = c.address
                city = c.city
                state = c.state
                zip = c.zip
                entryInstructions = c.entryInstructions
                notes = c.notes
                selectedAvatarTone = ClientAvatarStyle.tone(for: c)
                didManuallySelectAvatarTone = true
                showAvatarTonePicker = false
            } else {
                selectedAvatarTone = ClientAvatarStyle.defaultTone(for: previewName)
            }
        }
        .onChange(of: previewName) { _, newValue in
            guard !didManuallySelectAvatarTone, editingClient == nil else { return }
            selectedAvatarTone = ClientAvatarStyle.defaultTone(for: newValue)
        }
        .animation(.easeInOut(duration: 0.2), value: showingCreatePreview)
        .animation(.easeInOut(duration: 0.2), value: showAvatarTonePicker)
    }

    private func handlePrimaryAction() {
        showValidationErrors = true
        guard !firstName.isEmpty, isEmailValid, isPhoneValid else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        guard editingClient == nil else {
            Task { await saveClient() }
            return
        }

        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        showingCreatePreview = true
    }

    private func saveClient() async {
        guard let userId = session.userId else { return }
        isSaving = true
        let fullName = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))".trimmingCharacters(in: .whitespaces)

        let savedClient: Client
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
            updated.avatarToneRaw = selectedAvatarTone.rawValue
            let success = await clientsStore.update(updated)
            guard success else {
                isSaving = false
                return
            }
            ClientAvatarStyle.save(selectedAvatarTone, for: updated.id)
            savedClient = updated
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
                notes: notes,
                avatarToneRaw: selectedAvatarTone.rawValue
            )
            let success = await clientsStore.insert(newClient, userId: userId)
            guard success else {
                isSaving = false
                return
            }
            ClientAvatarStyle.save(selectedAvatarTone, for: newClient.id)
            savedClient = newClient
        }

        isSaving = false
        onSave?(savedClient)
        dismiss()
    }

    private var createPreviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    showingCreatePreview = false
                }

            VStack(spacing: 18) {
                Text("Preview Client".translated())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)

                previewCardContent
                avatarTonePicker

                HStack(spacing: 12) {
                    Button {
                        showingCreatePreview = false
                    } label: {
                        Text("Cancel".translated())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.sweeplyBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await saveClient() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSaving ? "Saving..." : "Confirm".translated())
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(isSaving ? Color.sweeplyBorder : Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
            .padding(22)
            .frame(maxWidth: 356)
            .background(Color.sweeplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 24)
        }
    }

    private var previewCardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selectedAvatarTone.backgroundColor)
                        .frame(width: 58, height: 58)
                    Text(previewInitials)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(selectedAvatarTone.foregroundColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(previewName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(1)

                    if let preferredService = previewPreferredService {
                        Text(preferredService)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.sweeplyAccent.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !previewAddress.isEmpty {
                    previewInfoRow(icon: "mappin.and.ellipse", text: previewAddress)
                }
                if let previewPhone {
                    previewInfoRow(icon: "phone", text: previewPhone)
                }
                if let previewEmail {
                    previewInfoRow(icon: "envelope", text: previewEmail)
                }
                if let previewEntryInstructions {
                    previewInfoRow(icon: "key.horizontal", text: previewEntryInstructions)
                }
                if let previewNotes {
                    previewInfoRow(icon: "note.text", text: previewNotes, lineLimit: 3)
                }
            }
        }
        .padding(16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var avatarTonePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Avatar Color".translated())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Text(selectedAvatarTone.label.translated())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ClientAvatarTone.allCases, id: \.rawValue) { tone in
                        avatarToneSwatch(tone)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func avatarToneSwatch(_ tone: ClientAvatarTone) -> some View {
        let isSelected = selectedAvatarTone == tone

        return Button {
            selectedAvatarTone = tone
            didManuallySelectAvatarTone = true
        } label: {
            VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(tone.backgroundColor)
                            .frame(width: 38, height: 38)

                    Text(previewInitials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tone.foregroundColor)

                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(tone.backgroundColor)
                            )
                            .offset(x: 14, y: -14)
                    }
                }

                Text(tone.label.translated())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
                    .lineLimit(1)
            }
            .frame(width: 54)
            .padding(.vertical, 6)
            .background(isSelected ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.sweeplyAccent.opacity(0.35) : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func previewInfoRow(icon: String, text: String, lineLimit: Int = 2) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.75))
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineLimit(lineLimit)

            Spacer(minLength: 0)
        }
    }
}

private struct FormTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var errorMessage: String? = nil

    @FocusState private var isFocused: Bool

    private var hasError: Bool { errorMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(hasError ? Color.sweeplyDestructive : isFocused ? Color.sweeplyAccent : Color.sweeplyTextSub)
                .animation(.easeOut(duration: 0.15), value: isFocused)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            hasError ? Color.sweeplyDestructive : isFocused ? Color.sweeplyAccent : Color.sweeplyBorder,
                            lineWidth: hasError || isFocused ? 1.5 : 1
                        )
                        .animation(.easeOut(duration: 0.15), value: isFocused)
                )
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Contact Picker (CNContactPickerViewController)

private struct ContactPickerView: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(value: true)
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        init(onSelect: @escaping (CNContact) -> Void) { self.onSelect = onSelect }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
    }
}
