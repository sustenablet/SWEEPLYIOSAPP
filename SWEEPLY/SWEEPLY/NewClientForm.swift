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

    var body: some View {
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

                    // Contact
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CONTACT INFO".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        HStack(spacing: 12) {
                            FormTextField(
                                label: "First Name *",
                                text: $firstName,
                                placeholder: "John",
                                errorMessage: showValidationErrors && firstName.isEmpty ? "First name is required" : nil
                            )
                            FormTextField(label: "Last Name", text: $lastName, placeholder: "Doe")
                        }
                        FormTextField(
                            label: "Email",
                            text: $email,
                            placeholder: "john@example.com",
                            keyboard: .emailAddress,
                            errorMessage: showValidationErrors && !isEmailValid ? "Enter a valid email address" : nil
                        )
                        FormTextField(
                            label: "Phone",
                            text: $phone,
                            placeholder: "(555) 000-0000",
                            keyboard: .phonePad,
                            errorMessage: showValidationErrors && !isPhoneValid ? "Phone number must be at least 10 digits" : nil
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
                            label: "Street Address",
                            street: $street,
                            city: $city,
                            state: $state,
                            zip: $zip
                        )
HStack(spacing: 12) {
                             FormTextField(label: "City", text: $city, placeholder: "Miami")
                             StatePickerField(label: "State", state: $state).frame(width: 90)
                             FormTextField(label: "ZIP", text: $zip, placeholder: "33101", keyboard: .numberPad).frame(width: 90)
                         }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 14) {
                        Text("OPERATIONAL NOTES".translated()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        FormTextField(label: "Entry Instructions", text: $entryInstructions, placeholder: "Gate code #1234...")
                        
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
                showValidationErrors = true
                guard !firstName.isEmpty, isEmailValid, isPhoneValid else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
                Task { await saveClient() }
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
            }
        }
    }

    private func saveClient() async {
        guard let userId = session.userId else { return }
        isSaving = true
        let fullName = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))".trimmingCharacters(in: .whitespaces)
        
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
            _ = await clientsStore.update(updated)
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
            _ = await clientsStore.insert(newClient, userId: userId)
        }
        
        isSaving = false
        dismiss()
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
