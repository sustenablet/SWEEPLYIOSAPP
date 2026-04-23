import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppSession.self) private var session

    @State private var step = 0
    @State private var goingForward = true

    // Step 1 fields
    @State private var fullName = ""
    @State private var businessName = ""
    @State private var phone = ""
    @FocusState private var focusedField: IdentityField?

    // Step 2 fields
    @State private var selectedServices: Set<String> = []

    // Step 3 state
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var checkmarkAppeared = false

    @State private var isSaving = false

    private let totalSteps = 4

    private enum IdentityField { case name, business, phone }

    private let mainServices = AppSettings.defaultServiceCatalog.filter { !$0.isAddon }
    private let addonServices = AppSettings.defaultServiceCatalog.filter { $0.isAddon }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading  : .trailing).combined(with: .opacity)
        )
    }

    private func advance() {
        focusedField = nil
        goingForward = true
        withAnimation(.easeInOut(duration: 0.28)) { step += 1 }
    }

    private func goBack() {
        focusedField = nil
        goingForward = false
        withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
    }

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 {
                    progressBar
                        .padding(.top, 16)
                }

                if step > 0 && step < totalSteps - 1 {
                    headerBar
                }

                ZStack {
                    switch step {
                    case 0: stepWelcome.transition(stepTransition).id(0)
                    case 1: stepIdentity.transition(stepTransition).id(1)
                    case 2: stepServices.transition(stepTransition).id(2)
                    case 3: stepAllSet.transition(stepTransition).id(3)
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sweeplyBorder.opacity(0.4))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sweeplyAccent)
                    .frame(width: geo.size.width * CGFloat(step) / CGFloat(totalSteps - 1), height: 3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 24)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                goBack()
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

            if step == 2 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    advance()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Step 0: Welcome

    private var stepWelcome: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.1))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 88, height: 88)
                    Text("S")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 14) {
                    Text("Your cleaning business,\nrun from your phone.")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .tracking(-0.6)

                    Text("Scheduling · Invoicing · AI assistant")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            primaryButton(label: "Get started") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                advance()
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 1: Identity

    private var stepIdentity: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Let's set up\nyour business")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(2)
                    .tracking(-0.6)

                Text("This shows on your invoices and throughout the app.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 36)

            VStack(spacing: 12) {
                OnboardingField(
                    placeholder: "Your name",
                    text: $fullName,
                    icon: "person",
                    keyboardType: .default,
                    submitLabel: .next
                ) { focusedField = .business }
                    .focused($focusedField, equals: .name)

                OnboardingField(
                    placeholder: "Business name (e.g. Sunrise Cleaning Co.)",
                    text: $businessName,
                    icon: "building.2",
                    keyboardType: .default,
                    submitLabel: .next
                ) { focusedField = .phone }
                    .focused($focusedField, equals: .business)

                OnboardingField(
                    placeholder: "Phone number (optional)",
                    text: $phone,
                    icon: "phone",
                    keyboardType: .phonePad,
                    submitLabel: .done
                ) { focusedField = nil }
                    .focused($focusedField, equals: .phone)
            }
            .padding(.horizontal, 24)

            Spacer()

            primaryButton(label: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                advance()
            }
            .disabled(!identityStepValid)
            .padding(.bottom, 48)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                focusedField = .name
            }
        }
    }

    private var identityStepValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !businessName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step 2: Services

    private var stepServices: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What services\ndo you offer?")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineSpacing(2)
                    .tracking(-0.6)

                Text("Select at least one. Prices are editable anytime in Settings.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    serviceSection(title: "MAIN SERVICES", services: mainServices)
                    serviceSection(title: "ADD-ONS & EXTRAS", services: addonServices)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }

            primaryButton(label: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                advance()
            }
            .disabled(!servicesStepValid)
            .padding(.bottom, 48)
        }
    }

    private var servicesStepValid: Bool {
        mainServices.contains { selectedServices.contains($0.name) }
    }

    private func serviceSection(title: String, services: [BusinessService]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            VStack(spacing: 8) {
                ForEach(services) { service in
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
        }
    }

    // MARK: - Step 3: All Set

    private var stepAllSet: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.1))
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.sweeplyAccent)
                        .scaleEffect(checkmarkAppeared ? 1.0 : 0.2)
                        .opacity(checkmarkAppeared ? 1.0 : 0)
                }

                VStack(spacing: 10) {
                    Text("Welcome to Sweeply,\n\(firstName)!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .tracking(-0.4)

                    VStack(spacing: 8) {
                        if !selectedServices.isEmpty {
                            allSetRow(
                                icon: "sparkles",
                                text: "\(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s") ready to go"
                            )
                        }
                        allSetRow(
                            icon: "building.2.fill",
                            text: "\(businessName.trimmingCharacters(in: .whitespaces)) is all set"
                        )
                    }
                }

                if notifStatus == .notDetermined {
                    notificationPermissionCard
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            primaryButton(label: isSaving ? "Setting up..." : "Open Dashboard →") {
                saveAndFinish()
            }
            .disabled(isSaving)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.15)) {
                checkmarkAppeared = true
            }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async { notifStatus = settings.authorizationStatus }
            }
        }
    }

    private func allSetRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
        }
    }

    private var notificationPermissionCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: "bell.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Get reminders for jobs & invoices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Stay on top of your schedule")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                NotificationManager.shared.requestAuthorization()
                withAnimation { notifStatus = .authorized }
            } label: {
                Text("Allow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.sweeplyAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var firstName: String {
        fullName.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "there"
    }

    // MARK: - Primary Button

    private func primaryButton(label: String, action: @escaping () -> Void) -> some View {
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
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: AppSettings()
            )
            profile.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.businessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

            let chosenServices = AppSettings.defaultServiceCatalog.filter { selectedServices.contains($0.name) }
            if !chosenServices.isEmpty {
                profile.settings.services = chosenServices
            }

            await profileStore.save(profile, userId: userId)
            await MainActor.run {
                isSaving = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Supporting Views

private struct OnboardingField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 24)

            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .keyboardType(keyboardType)
                .submitLabel(submitLabel)
                .autocorrectionDisabled()
                .onSubmit { onSubmit?() }
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
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyBorder)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(service.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)

                Spacer()

                Text(service.price.currency)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isSelected ? Color.sweeplyAccent.opacity(0.08) : Color.sweeplyNavy.opacity(0.05))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.sweeplyAccent.opacity(0.05) : Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.sweeplyAccent.opacity(0.35) : Color.sweeplyBorder, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environment(ProfileStore())
        .environment(AppSession())
}
