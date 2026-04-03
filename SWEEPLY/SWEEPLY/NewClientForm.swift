import SwiftUI

struct NewClientForm: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingClient == nil ? "New Client" : "Edit Client")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(24)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Contact
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CONTACT INFO").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        HStack(spacing: 12) {
                            FormTextField(label: "First Name *", text: $firstName, placeholder: "John")
                            FormTextField(label: "Last Name", text: $lastName, placeholder: "Doe")
                        }
                        FormTextField(label: "Email", text: $email, placeholder: "john@example.com", keyboard: .emailAddress)
                        FormTextField(label: "Phone", text: $phone, placeholder: "(555) 000-0000", keyboard: .phonePad)
                    }

                    // Preferences
                    VStack(alignment: .leading, spacing: 14) {
                        Text("PREFERENCES").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Preferred Service").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                            Menu {
                                Button("None") { preferredService = nil }
                                ForEach(ServiceType.allCases, id: \.self) { type in
                                    Button(type.rawValue) { preferredService = type }
                                }
                            } label: {
                                HStack {
                                    Text(preferredService?.rawValue ?? "Select Service...")
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
                        Text("SERVICE ADDRESS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        FormTextField(label: "Street Address", text: $street, placeholder: "123 Main St")
                        HStack(spacing: 12) {
                            FormTextField(label: "City", text: $city, placeholder: "Miami")
                            FormTextField(label: "State", text: $state, placeholder: "FL").frame(width: 70)
                            FormTextField(label: "ZIP", text: $zip, placeholder: "33101", keyboard: .numberPad).frame(width: 90)
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 14) {
                        Text("OPERATIONAL NOTES").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub).tracking(1.0)
                        FormTextField(label: "Entry Instructions", text: $entryInstructions, placeholder: "Gate code #1234...")
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
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
                .background(firstName.isEmpty || isSaving ? Color.sweeplyBorder : Color.sweeplyNavy)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(firstName.isEmpty || isSaving)
            .padding(24)
        }
        .background(Color.sweeplySurface)
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
        guard let uid = session.userId else { return }
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
            _ = await clientsStore.insert(newClient, userId: uid)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
            TextField(placeholder, text: $text)
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
