import SwiftUI

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session

    @State private var step = 0
    @State private var businessName = ""
    @State private var selectedServices: Set<String> = Set(AppSettings.defaultServiceCatalog.map { $0.name })
    @State private var isSaving = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.sweeplyBorder.opacity(0.4)).frame(height: 3)
                        Rectangle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps), height: 3)
                            .animation(.easeInOut(duration: 0.35), value: step)
                    }
                }
                .frame(height: 3)

                // Step content
                TabView(selection: $step) {
                    stepOne.tag(0)
                    stepTwo.tag(1)
                    stepThree.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Step 1: Business Name

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("What's your\nbusiness called?")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(4)

                Text("This appears on your invoices and throughout the app.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 48)

            TextField("e.g. Sunrise Cleaning Co.", text: $businessName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                .padding(.horizontal, 24)
                .submitLabel(.next)
                .onSubmit { if !businessName.trimmingCharacters(in: .whitespaces).isEmpty { step = 1 } }

            Spacer()

            nextButton(label: "Next", enabled: !businessName.trimmingCharacters(in: .whitespaces).isEmpty) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 1
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Services

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("What services\ndo you offer?")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(4)

                Text("Select all that apply. You can always add more in Settings.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 36)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(AppSettings.defaultServiceCatalog) { service in
                        let isSelected = selectedServices.contains(service.name)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if isSelected { selectedServices.remove(service.name) }
                            else { selectedServices.insert(service.name) }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyBorder)

                                Text(service.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)

                                Spacer()

                                Text(service.price.currency)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
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
            }

            Spacer()

            nextButton(label: "Next", enabled: !selectedServices.isEmpty) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 2
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: All Set

    private var stepThree: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.sweeplyAccent)
                }

                VStack(spacing: 12) {
                    Text("You're all set,\n\(businessName)!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("\(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s") ready to go.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()

            nextButton(label: isSaving ? "Setting up…" : "Start using Sweeply", enabled: !isSaving) {
                saveAndFinish()
            }
            .padding(.bottom, 48)
        }
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
                fullName: "",
                businessName: businessName,
                email: "",
                phone: "",
                settings: AppSettings()
            )
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
