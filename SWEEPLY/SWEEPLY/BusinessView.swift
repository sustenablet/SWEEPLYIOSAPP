import SwiftUI

struct BusinessView: View {
    @Environment(AppSession.self) private var session

    private let profile = MockData.profile

    @AppStorage("businessRemindersEnabled") private var remindersOn = true
    @AppStorage("businessJobConfirmations") private var jobConfirmationsOn = true
    @AppStorage("businessMarketingEmails") private var marketingEmailsOn = false

    @State private var appeared = false
    @State private var showSignOutConfirm = false

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
    }

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
                Text(profile.businessName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(2)
                Text(profile.fullName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary)
                LabeledValueRow(icon: "envelope", text: profile.email)
                LabeledValueRow(icon: "phone", text: profile.phone)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private var businessInitials: String {
        let parts = profile.businessName.split(separator: " ")
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

    // MARK: - Section builder

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
}
