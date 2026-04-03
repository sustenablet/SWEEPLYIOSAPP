import SwiftUI

struct BusinessView: View {
    @Environment(AppSession.self)   private var session
    @Environment(ProfileStore.self) private var profileStore

    @AppStorage("businessRemindersEnabled") private var remindersOn = true
    @AppStorage("businessJobConfirmations") private var jobConfirmationsOn = true
    @AppStorage("businessMarketingEmails")  private var marketingEmailsOn = false

    @State private var appeared = false
    @State private var showSignOutConfirm = false
    @State private var showEditProfile = false

    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                profileCard
                preferencesSection
                businessDetailsSection
                supportSection
                signOutSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { appeared = true }
            }
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .confirmationDialog(
            "Sign out of Sweeply?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(profile: profile) { updated in
                Task {
                    let uid = session.userId ?? profile.id
                    await profileStore.save(updated, userId: uid)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BUSINESS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.65))
                .tracking(1.4)
            Text("Your business")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text("Profile and preferences")
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private var profileCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.sweeplyNavy)
                        .frame(width: 64, height: 64)
                    Text(businessInitials)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.businessName.isEmpty ? "Your Business" : profile.businessName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(2)
                    Text(profile.fullName.isEmpty ? "Your Name" : profile.fullName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primary)
                    if !profile.email.isEmpty {
                        LabeledValueRow(icon: "envelope", text: profile.email)
                    }
                    if !profile.phone.isEmpty {
                        LabeledValueRow(icon: "phone", text: profile.phone)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            Divider()
                .background(Color.sweeplyBorder)
                .padding(.horizontal, 18)

            Button {
                showEditProfile = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Edit profile")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.sweeplyNavy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var businessInitials: String {
        let name = profile.businessName.isEmpty ? profile.fullName : profile.businessName
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    private var preferencesSection: some View {
        sectionCard(title: "Preferences") {
            toggleRow(title: "Visit reminders", subtitle: "Alerts before scheduled jobs", isOn: $remindersOn)
            Divider().background(Color.sweeplyBorder)
            toggleRow(title: "Job confirmations", subtitle: "When a job is booked or changed", isOn: $jobConfirmationsOn)
            Divider().background(Color.sweeplyBorder)
            toggleRow(title: "Product updates", subtitle: "Tips and occasional news", isOn: $marketingEmailsOn)
        }
    }

    private var businessDetailsSection: some View {
        sectionCard(title: "Details") {
            staticRow(title: "Service area", value: "Miami–Dade County")
            Divider().background(Color.sweeplyBorder)
            staticRow(title: "Timezone", value: TimeZone.current.identifier.split(separator: "/").last.map(String.init) ?? "Local")
            Divider().background(Color.sweeplyBorder)
            staticRow(title: "Tax ID", value: "—")
        }
    }

    private var supportSection: some View {
        sectionCard(title: "Support") {
            chevronRow(title: "Help center", icon: "questionmark.circle")
            Divider().background(Color.sweeplyBorder)
            chevronRow(title: "Contact support", icon: "bubble.left.and.bubble.right")
            Divider().background(Color.sweeplyBorder)
            chevronRow(title: "Privacy", icon: "hand.raised")
        }
    }

    private var signOutSection: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            Text("Sign out")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sweeplyDestructive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Row builders

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.65))
                .tracking(1.1)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.sweeplySuccess)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func staticRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func chevronRow(title: String, icon: String) -> some View {
        Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyAccent)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Profile Sheet

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile
    let onSave: (UserProfile) -> Void

    @State private var fullName: String
    @State private var businessName: String
    @State private var email: String
    @State private var phone: String
    @State private var isSaving = false

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _fullName     = State(initialValue: profile.fullName)
        _businessName = State(initialValue: profile.businessName)
        _email        = State(initialValue: profile.email)
        _phone        = State(initialValue: profile.phone)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    avatarBlock
                    formCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(Color.sweeplyNavy)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var avatarBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.sweeplyNavy)
                    .frame(width: 80, height: 80)
                Text(editedInitials)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Your initials are generated from your name")
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            fieldRow(
                label: "Full name",
                placeholder: "e.g. Maria Santos",
                text: $fullName,
                icon: "person",
                keyboard: .default
            )
            Divider().background(Color.sweeplyBorder).padding(.leading, 48)

            fieldRow(
                label: "Business name",
                placeholder: "e.g. Sparkle Clean Co.",
                text: $businessName,
                icon: "building.2",
                keyboard: .default
            )
            Divider().background(Color.sweeplyBorder).padding(.leading, 48)

            fieldRow(
                label: "Email",
                placeholder: "you@example.com",
                text: $email,
                icon: "envelope",
                keyboard: .emailAddress
            )
            Divider().background(Color.sweeplyBorder).padding(.leading, 48)

            fieldRow(
                label: "Phone",
                placeholder: "+1 (555) 000-0000",
                text: $phone,
                icon: "phone",
                keyboard: .phonePad
            )
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                TextField(placeholder, text: text)
                    .font(.system(size: 15))
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Helpers

    private var editedInitials: String {
        let source = businessName.isEmpty ? fullName : businessName
        let parts = source.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased().isEmpty ? "?" : letters.joined().uppercased()
    }

    private func save() {
        isSaving = true
        let updated = UserProfile(
            id: profile.id,
            fullName: fullName.trimmingCharacters(in: .whitespaces),
            businessName: businessName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces)
        )
        onSave(updated)
        isSaving = false
        dismiss()
    }
}

// MARK: - Supporting view

private struct LabeledValueRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
        }
    }
}

#Preview {
    BusinessView()
        .environment(AppSession())
        .environment(ProfileStore())
}
