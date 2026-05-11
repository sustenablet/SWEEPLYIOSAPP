import SwiftUI

struct CleanerProfileMenuView: View {
    @Environment(AppSession.self)   private var session
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss)         private var dismiss

    let membership: TeamMembership
    @Binding var showSettings: Bool

    private var displayName: String {
        guard let name = profileStore.profile?.fullName, !name.isEmpty else { return "Team Member".translated() }
        return name
    }

    private var displayEmail: String {
        profileStore.profile?.email ?? ""
    }

    private var initials: String {
        displayName == "Team Member" ? "?" :
        displayName.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 32, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Identity row
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 50, height: 50)
                    if profileStore.profile == nil {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Text(initials)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(1)
                    if !displayEmail.isEmpty {
                        Text(displayEmail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(membership.businessName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.sweeplyAccent.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1))
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)

            Divider()

            menuRow(icon: "gearshape.fill", iconColor: Color.sweeplyNavy, label: "Settings") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSettings = true }
            }

            Divider().padding(.leading, 54)

            menuRow(icon: "arrow.left.arrow.right", iconColor: Color.sweeplyAccent, label: "Switch to My Business") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    session.switchToOwnBusiness()
                }
            }

            Divider()

            // Sign out removed - available in Settings page
        }
        .background(Color.sweeplyBackground)
    }

    @ViewBuilder
    private func menuRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                Text(label.translated())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
