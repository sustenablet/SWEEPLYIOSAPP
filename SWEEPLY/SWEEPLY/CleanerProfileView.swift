import SwiftUI

struct CleanerProfileView: View {
    @Environment(AppSession.self) private var session

    let membership: TeamMembership

    @State private var showSignOutAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        avatarSection
                        infoSection
                        switchBusinessButton
                        signOutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
            }

            VStack(spacing: 4) {
                Text("Team Member")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Viewing as \(membership.role.capitalized)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(icon: "building.2.fill", label: "Team", value: membership.businessName)
            Divider().padding(.leading, 44)
            infoRow(icon: "person.badge.key.fill", label: "Role", value: membership.role.capitalized)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
        }
        .padding(14)
    }

    private var switchBusinessButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            session.switchToOwnBusiness()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Switch to My Business")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.sweeplyNavy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.sweeplyAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var signOutSection: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showSignOutAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
