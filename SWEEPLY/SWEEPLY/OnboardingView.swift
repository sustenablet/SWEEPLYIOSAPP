import SwiftUI

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session

    @State private var step = 0
    @State private var fullName = ""
    @State private var businessName = ""
    @State private var serviceAreas: String = ""
    @State private var selectedServices: Set<String> = Set(AppSettings.defaultServiceCatalog.map { $0.name })
    @State private var isSaving = false
    
    // Animation states
    @State private var animateProgress = false
    @State private var contentOffset: CGFloat = 0
    
    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar - visible on all steps except welcome
                if step > 0 {
                    progressBar
                } else {
                    Color.clear.frame(height: 1)
                }

                // Header with back/skip
                if step > 0 && step < totalSteps - 1 {
                    headerBar
                }

                TabView(selection: $step) {
                    stepWelcome.tag(0)
                    stepName.tag(1)
                    stepServiceArea.tag(2)
                    stepServices.tag(3)
                    stepAllSet.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .interactiveDismissDisabled(true)
        .onChange(of: step) { _, newStep in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                animateProgress = true
            }
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.sweeplyBorder.opacity(0.3))
                        .frame(height: 4)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.sweeplyAccent, Color.sweeplyAccent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animateProgress ? geo.size.width * CGFloat(step - 1) / CGFloat(totalSteps - 2) : 0, height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
                }
            }
            .frame(height: 4)
            
            Text("Step \(max(1, step)) of \(totalSteps - 1)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Header Bar (Back + Skip)
    private var headerBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.sweeplyNavy)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                saveAndFinish()
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Step 0: Welcome
    private var stepWelcome: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(1.0)
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .frame(width: 88, height: 88)
                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                }

                VStack(spacing: 16) {
                    Text("Run your cleaning\nbusiness from here")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .tracking(-0.6)

                    Text("Everything you need — from scheduling to\npayment — in one clean app.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                // Feature pills
                HStack(spacing: 12) {
                    FeaturePill(icon: "calendar", label: "Schedule")
                    FeaturePill(icon: "doc.text", label: "Invoice")
                    FeaturePill(icon: "chart.line.uptrend.xyaxis", label: "Grow")
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton(label: "Get started") {
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
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(2)
                    .tracking(-0.6)

                Text("This appears on your invoices and throughout the app.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                OnboardingField(
                    placeholder: "Your name",
                    text: $fullName,
                    icon: "person"
                )
                OnboardingField(
                    placeholder: "Business name (e.g. Sunrise Cleaning Co.)",
                    text: $businessName,
                    icon: "building.2"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            nextButton(label: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 2
            }
            .disabled(!nameStepValid)
            .padding(.bottom, 48)
        }
    }

    private var nameStepValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !businessName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step 2: Service Area
    private var stepServiceArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("Where do you\nprovide service?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(2)
                    .tracking(-0.6)

                Text("Enter the zip codes or cities you serve. You can add more later in Settings.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 32)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.sweeplyAccent)
                        .frame(width: 24)

                    TextField("Zip codes or cities (comma separated)", text: $serviceAreas)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.sweeplyNavy)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )

                Text("e.g., 90210, 90211, Beverly Hills")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 24)

            Spacer()

            nextButton(label: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 3
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: Services
    private var stepServices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("What services\ndo you offer?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(2)
                    .tracking(-0.6)

                Text("Select all that apply. You can add custom services anytime in Settings.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(AppSettings.defaultServiceCatalog) { service in
                        ServiceSelectionCard(
                            service: service,
                            isSelected: selectedServices.contains(service.name)
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selectedServices.contains(service.name) {
                                selectedServices.remove(service.name)
                            } else {
                                selectedServices.insert(service.name)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            nextButton(label: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = 4
            }
            .disabled(selectedServices.isEmpty)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 4: All Set
    private var stepAllSet: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated success
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.12))
                        .frame(width: 112, height: 112)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.sweeplyAccent)
                }

                VStack(spacing: 12) {
                    Text("You're all set\n\(firstName)!")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .tracking(-0.4)

                    Text("\(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s") configured")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                }

                // Dashboard preview card
                DashboardPreviewCard()
                    .padding(.horizontal, 8)
            }

            Spacer()

            nextButton(label: isSaving ? "Setting up..." : "Go to Dashboard") {
                saveAndFinish()
            }
            .padding(.bottom, 48)
        }
    }

    private var firstName: String {
        fullName.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "there"
    }

    // MARK: - Shared Button
    private func nextButton(label: String, action: @escaping () -> Void) -> some View {
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
            .background(Color.sweeplyNavy)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(isSaving)
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

            // Save service areas
            profile.settings.street = serviceAreas.trimmingCharacters(in: .whitespacesAndNewlines)

            // Save selected services
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

private struct ServiceSelectionCard: View {
    let service: BusinessService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.sweeplyAccent : Color.sweeplyAccent.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: isSelected ? "checkmark" : "")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    
                    Text(serviceDescription(for: service.name))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Text(service.price.currency)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isSelected ? Color.sweeplyAccent.opacity(0.06) : Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.sweeplyAccent.opacity(0.4) : Color.sweeplyBorder, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
    
    private func serviceDescription(for name: String) -> String {
        switch name.lowercased() {
        case let n where n.contains("standard"): return "Regular cleaning"
        case let n where n.contains("deep"): return "Thorough cleaning"
        case let n where n.contains("move"): return "Moving in/out"
        case let n where n.contains("construction"): return "Post-renovation"
        case let n where n.contains("office"): return "Commercial"
        case let n where n.contains("window"): return "Interior glass"
        case let n where n.contains("laundry"): return "Wash & fold"
        default: return "Cleaning service"
        }
    }
}

private struct DashboardPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your dashboard")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            // Mini preview
            HStack(spacing: 12) {
                PreviewStat(icon: "calendar", label: "Jobs", value: "0")
                PreviewStat(icon: "person.2", label: "Clients", value: "0")
                PreviewStat(icon: "dollarsign.circle", label: "Revenue", value: "$0")
            }

            // Next steps
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick actions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))

                HStack(spacing: 8) {
                    QuickActionPill(icon: "plus", label: "Add client")
                    QuickActionPill(icon: "calendar.badge.plus", label: "Book job")
                }
            }
        }
        .padding(20)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

private struct PreviewStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyAccent)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickActionPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.sweeplyNavy)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.sweeplyAccent.opacity(0.08))
        .clipShape(Capsule())
    }
}