import SwiftUI

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session

    @State private var step = 0
    @State private var fullName = ""
    @State private var businessName = ""
    @State private var selectedServices: Set<String> = Set(AppSettings.defaultServiceCatalog.map { $0.name })
    @State private var isSaving = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar — hidden on welcome screen
                if step > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.sweeplyBorder.opacity(0.4))
                                .frame(height: 3)
                            Rectangle()
                                .fill(Color.sweeplyAccent)
                                .frame(
                                    width: geo.size.width * CGFloat(step) / CGFloat(totalSteps - 1),
                                    height: 3
                                )
                                .animation(.easeInOut(duration: 0.35), value: step)
                        }
                    }
                    .frame(height: 3)
                } else {
                    Color.clear.frame(height: 3)
                }

                TabView(selection: $step) {
                    stepWelcome.tag(0)
                    stepName.tag(1)
                    stepServices.tag(2)
                    stepAllSet.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Step 0: Welcome

    private var stepWelcome: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Icon mark
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.sweeplyNavy)
                        .frame(width: 80, height: 80)
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color.sweeplyAccent)
                }

                VStack(spacing: 14) {
                    Text("Run your cleaning\nbusiness from here")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .tracking(-0.5)

                    Text("Everything you need — from scheduling to\npayment — in one clean app.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Feature pills
                HStack(spacing: 10) {
                    FeaturePill(icon: "calendar", label: "Schedule")
                    FeaturePill(icon: "doc.text", label: "Invoice")
                    FeaturePill(icon: "chart.line.uptrend.xyaxis", label: "Grow")
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton(label: "Get started", enabled: true) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 1
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 1: Name + Business

    private var stepName: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("Let's set up\nyour business")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(4)
                    .tracking(-0.5)

                Text("This appears on your invoices and throughout the app.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                OnboardingField(
                    placeholder: "Your name",
                    text: $fullName,
                    icon: "person"
                )
                OnboardingField(
                    placeholder: "Business name  (e.g. Sunrise Cleaning Co.)",
                    text: $businessName,
                    icon: "building.2"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            nextButton(label: "Next", enabled: nameStepValid) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 2
            }
            .padding(.bottom, 48)
        }
    }

    private var nameStepValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !businessName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step 2: Services

    private var stepServices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("What services\ndo you offer?")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(4)
                    .tracking(-0.5)

                Text("Select all that apply. You can add custom services anytime in Settings.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(AppSettings.defaultServiceCatalog) { service in
                        let isSelected = selectedServices.contains(service.name)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if isSelected { selectedServices.remove(service.name) }
                            else { selectedServices.insert(service.name) }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color.sweeplyAccent : Color.sweeplyAccent.opacity(0.08))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: isSelected ? "checkmark" : "")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                Text(service.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)

                                Spacer()

                                Text(service.price.currency)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .background(isSelected ? Color.sweeplyAccent.opacity(0.06) : Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? Color.sweeplyAccent.opacity(0.4) : Color.sweeplyBorder, lineWidth: 1)
                            )
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            nextButton(label: "Next", enabled: !selectedServices.isEmpty) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 3
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: All Set

    private var stepAllSet: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyAccent)
                }

                VStack(spacing: 10) {
                    Text("You're all set\n\(firstName)!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .tracking(-0.4)

                    Text("\(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s") configured and ready to go.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                }

                // Next steps preview
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your first 4 steps")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .padding(.bottom, 12)

                    VStack(spacing: 8) {
                        NextStepRow(icon: "person.badge.plus", label: "Add your first client")
                        NextStepRow(icon: "calendar.badge.plus", label: "Schedule your first job")
                        NextStepRow(icon: "doc.badge.plus", label: "Create your first invoice")
                        NextStepRow(icon: "building.2", label: "Set up business profile", isDone: true)
                    }
                }
                .padding(20)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }

            Spacer()

            nextButton(label: isSaving ? "Setting up…" : "Go to Dashboard", enabled: !isSaving) {
                saveAndFinish()
            }
            .padding(.bottom, 48)
        }
    }

    private var firstName: String {
        fullName.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? fullName
    }

    // MARK: - Shared button

    private func nextButton(label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSaving && label.contains("Setting") {
                    ProgressView().tint(.white)
                } else {
                    Text(label)
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(enabled ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(!enabled)
        .padding(.horizontal, 24)
    }

    // MARK: - Save

    private func saveAndFinish() {
        guard let userId = session.userId else { return }
        isSaving = true

        Task {
            var profile = profileStore.profile ?? UserProfile(
                id: userId,
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                businessName: businessName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: "",
                phone: "",
                settings: AppSettings()
            )
            profile.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.businessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)

            let chosenServices = AppSettings.defaultServiceCatalog.filter { selectedServices.contains($0.name) }
            profile.settings.services = chosenServices

            await profileStore.save(profile, userId: userId)
            await MainActor.run {
                isSaving = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Supporting Views

private struct FeaturePill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyAccent)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 24)

            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .submitLabel(.next)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

private struct NextStepRow: View {
    let icon: String
    let label: String
    var isDone: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.sweeplyAccent : Color.sweeplyAccent.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: isDone ? "checkmark" : icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isDone ? .white : Color.sweeplyAccent)
            }
            Text(label)
                .font(.system(size: 14, weight: isDone ? .regular : .medium))
                .foregroundStyle(isDone ? Color.sweeplyTextSub : Color.sweeplyNavy)
            Spacer()
            if isDone {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
            }
        }
        .opacity(isDone ? 0.7 : 1.0)
    }
}
