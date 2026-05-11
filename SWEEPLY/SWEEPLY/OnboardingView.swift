import SwiftUI
import UserNotifications
import RevenueCat

struct OnboardingView: View {
    var isSignUpFlow: Bool = false
    var onDismiss: (() -> Void)? = nil

    private struct TeamInvite: Identifiable {
        let id = UUID()
        var name: String
        var email: String
    }

    private struct RecurringCard: Identifiable {
        let id = UUID()
        var name: String = ""
        var frequency: String = "Weekly"
    }

    @Environment(ProfileStore.self)        private var profileStore
    @Environment(AppSession.self)          private var session
    @Environment(TeamStore.self)           private var teamStore
    @Environment(ClientsStore.self)        private var clientsStore
    @Environment(SubscriptionManager.self) private var subscriptionManager

    // Paywall step local enums (mirrors private types in SubscriptionPaywallView)
    private enum OBPlan: String, CaseIterable {
        case standard = "Standard"; case pro = "Pro"
    }
    private enum OBBilling: String, CaseIterable {
        case monthly = "Monthly"; case yearly = "Yearly"
    }

    @State private var step = 0
    @State private var goingForward = true

    // Discovery steps (0-3)
    @State private var describesYouIndex: Int? = nil
    @State private var goalIndex: Int? = nil
    @State private var clientCountIndex: Int? = nil
    @State private var recurringCards: [RecurringCard] = [RecurringCard()]

    // Account creation steps (4-7)
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var usePasscode = false
    @State private var password = ""
    @State private var showPassword = false
    @State private var isCreatingAccount = false
    @State private var accountError: String? = nil

    // Existing identity fields (kept for saveAndFinish compatibility)
    @State private var businessName = ""
    @State private var phone = ""
    @FocusState private var focusedField: IdentityField?

    // Step 3: Team
    @State private var teamInviteName = ""
    @State private var teamInviteEmail = ""
    @State private var teamInviteMembers: [TeamInvite] = []
    @FocusState private var teamField: TeamField?

    // Step 4: Notifications
    @State private var notificationRequested = false

    // Step 5: Paywall
    @State private var paywallPlan: OBPlan = .pro
    @State private var paywallBilling: OBBilling = .monthly
    @State private var paywallPurchasing = false
    @State private var paywallError: String?

    // Step 6: Location
    @State private var locationRequested = false

    // Step 2 fields
    @State private var selectedServices: Set<String> = []
    @State private var customServices: [BusinessService] = []
    @State private var showCreateService = false
    @State private var newServiceIsAddon = false
    @State private var newServiceName = ""
    @State private var newServicePrice = ""

    private var allMainServices: [BusinessService] {
        let defaults = AppSettings.defaultServiceCatalog.filter { !$0.isAddon }
        return defaults + customServices.filter { !$0.isAddon }
    }

    private var allAddonServices: [BusinessService] {
        let defaults = AppSettings.defaultServiceCatalog.filter { $0.isAddon }
        return defaults + customServices.filter { $0.isAddon }
    }

    @State private var checkmarkAppeared = false
    @State private var saveError = false

    @State private var isSaving = false
    @State private var welcomeAppeared = false

    private enum IdentityField { case name, business, phone }
    private enum TeamField { case name, email }

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
        withAnimation(.easeInOut(duration: 0.28)) {
            switch step {
            case 2: step = (clientCountIndex ?? 0) > 0 ? 3 : 4
            case 3: step = 4
            case 6:
                if usePasscode {
                    step = 8
                    Task { await createAccount() }
                } else {
                    step = 7
                }
            case 7:
                step = 8
                Task { await createAccount() }
            default: step += 1
            }
        }
    }

    private func goBack() {
        focusedField = nil
        goingForward = false
        withAnimation(.easeInOut(duration: 0.22)) {
            switch step {
            case 4: step = (clientCountIndex ?? 0) > 0 ? 3 : 2
            case 8: step = usePasscode ? 6 : 7
            default: step -= 1
            }
        }
    }

    private var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordHas8: Bool { password.count >= 8 }
    private var passwordHasUpper: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var passwordHasLower: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    private var passwordHasNumber: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
    private var passwordIsValid: Bool { passwordHas8 && passwordHasUpper && passwordHasLower && passwordHasNumber }

    private var isBlueStep: Bool { step == 10 || step == 11 || step == 13 }

    private func createAccount() async {
        guard !isCreatingAccount else { return }
        await MainActor.run { isCreatingAccount = true; accountError = nil }

        let pwd: String
        if usePasscode {
            let generated = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
            KeychainHelper.save(key: "sweeply_auth_password", value: generated)
            UserDefaults.standard.set(true, forKey: "biometricLockEnabled")
            UserDefaults.standard.set(true, forKey: "sweeply_uses_passcode_auth")
            pwd = generated
        } else {
            pwd = password
        }

        await session.signUpDirect(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: pwd)

        // Wait up to 10s for session to be established
        for _ in 0..<20 {
            if session.userId != nil { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        await MainActor.run {
            isCreatingAccount = false
            if session.lastAuthError == nil && session.userId != nil {
                applyDiscoveryEffects()
            } else if session.lastAuthError != nil {
                accountError = session.lastAuthError
                // Step back to whichever input caused the error
                withAnimation(.easeInOut(duration: 0.28)) {
                    step = usePasscode ? 6 : 7
                }
            }
        }
    }

    private func applyDiscoveryEffects() {
        // Page B: "Get invoices paid faster" → open Finances tab first
        if goalIndex == 1 {
            UserDefaults.standard.set("finances", forKey: "sweeply_initial_tab_override")
        }
        // Page A: "Switching from another app" → show import tip after onboarding
        if describesYouIndex == 3 {
            UserDefaults.standard.set(true, forKey: "sweeply_show_import_tip")
        }
        // Page A: "Manage a team" → badge the team section
        if describesYouIndex == 2 {
            UserDefaults.standard.set(true, forKey: "sweeply_team_badge")
        }
    }

    var body: some View {
        ZStack {
            (isBlueStep
                ? Color(red: 0.22, green: 0.50, blue: 0.92)
                : Color.sweeplyBackground
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — shown on setup steps (services, team, notifications, location)
                if step >= 8 && step <= 11 {
                    headerBar
                        .transition(.opacity)
                }

                ZStack {
                    switch step {
                    // Discovery
                    case 0:  stepDescribesYou.transition(stepTransition).id(0)
                    case 1:  stepGoal.transition(stepTransition).id(1)
                    case 2:  stepClientCount.transition(stepTransition).id(2)
                    case 3:  stepRecurringClients.transition(stepTransition).id(3)
                    // Account creation
                    case 4:  stepName.transition(stepTransition).id(4)
                    case 5:  stepBusinessName.transition(stepTransition).id(5)
                    case 6:  stepEmail.transition(stepTransition).id(6)
                    case 7:  stepPassword.transition(stepTransition).id(7)
                    // Setup
                    case 8:  stepServices.transition(stepTransition).id(8)
                    case 9:  stepTeam.transition(stepTransition).id(9)
                    case 10: stepNotifications.transition(stepTransition).id(10)
                    case 11: stepLocation.transition(stepTransition).id(11)
                    case 12: stepPaywall.transition(stepTransition).id(12)
                    case 13: stepAllSet.transition(stepTransition).id(13)
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showCreateService) {
            CreateServiceSheet(
                isAddon: newServiceIsAddon,
                name: $newServiceName,
                price: $newServicePrice,
                onSave: {
                    guard !newServiceName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let priceValue = Double(newServicePrice.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
                    let newService = BusinessService(
                        name: newServiceName.trimmingCharacters(in: .whitespaces),
                        price: priceValue,
                        isAddon: newServiceIsAddon
                    )
                    customServices.append(newService)
                    showCreateService = false
                },
                onCancel: { showCreateService = false }
            )
        }
    }

    // Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Previous — shown on steps 1-5
            if step >= 9 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Previous".translated())
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(step == 10 ? .white : Color.sweeplyNavy)
                }
                .buttonStyle(.plain)
                .frame(width: 80, alignment: .leading)
            } else {
                Color.clear.frame(width: 80, height: 1)
            }

            // Progress bar — 4 setup steps (8–11)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(step == 10 ? Color.white.opacity(0.3) : Color.sweeplyBorder)
                        .frame(height: 4)
                    Capsule()
                        .fill(step == 10 ? Color.white : Color.sweeplyAccent)
                        .frame(width: geo.size.width * (CGFloat(step - 7) / 4.0), height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                }
            }
            .frame(height: 4)

            // Skip — only on services step (8)
            if step == 8 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    advance()
                } label: {
                    Text("Skip".translated())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
                .frame(width: 80, alignment: .trailing)
            } else {
                Color.clear.frame(width: 80, height: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Step 0: What describes you?

    private var stepDescribesYou: some View {
        discoveryPage(
            question: "What best\ndescribes you?",
            options: [
                ("🌱", "Starting a new cleaning business"),
                ("⚙️", "Already running, need better tools"),
                ("👥", "Managing a team of cleaners"),
                ("🔄", "Switching from another app")
            ],
            selection: $describesYouIndex,
            onContinue: { advance() }
        )
    }

    // MARK: - Step 1: Main goal

    private var stepGoal: some View {
        discoveryPage(
            question: "What's your\nmain goal?",
            options: [
                ("📅", "Stay on top of jobs and schedule"),
                ("💸", "Get invoices paid faster"),
                ("📈", "Build a bigger client base"),
                ("👤", "Manage and pay my team")
            ],
            selection: $goalIndex,
            onContinue: { advance() }
        )
    }

    // MARK: - Step 2: Client count

    private var stepClientCount: some View {
        discoveryPage(
            question: "How many clients\ndo you have now?",
            options: [
                ("🌿", "Just starting — 0 to 5"),
                ("📊", "Growing — 6 to 20"),
                ("🏆", "Established — 21 to 50"),
                ("🚀", "Scaling fast — 50+")
            ],
            selection: $clientCountIndex,
            onContinue: { advance() }
        )
    }

    // MARK: - Discovery page builder

    private func discoveryPage(
        question: String,
        options: [(String, String)],
        selection: Binding<Int?>,
        onContinue: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Back button for steps > 0
                    if step > 0 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            goBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Back".translated())
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    } else {
                        Spacer().frame(height: 32)
                    }

                    Text(question.translated())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineSpacing(2)
                        .tracking(-0.6)
                        .padding(.horizontal, 24)
                        .padding(.top, step == 0 ? 40 : 16)
                        .padding(.bottom, 32)

                    VStack(spacing: 10) {
                        ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selection.wrappedValue = idx
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Text(option.0)
                                        .font(.system(size: 22))
                                        .frame(width: 36)
                                    Text(option.1.translated())
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(selection.wrappedValue == idx ? Color.sweeplyAccent : Color.sweeplyNavy)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if selection.wrappedValue == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.sweeplyAccent)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(
                                    selection.wrappedValue == idx
                                        ? Color.sweeplyAccent.opacity(0.08)
                                        : Color.sweeplySurface
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            selection.wrappedValue == idx ? Color.sweeplyAccent : Color.sweeplyBorder,
                                            lineWidth: selection.wrappedValue == idx ? 1.5 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }

            Divider().opacity(0.5)
            primaryButton(
                label: "Continue",
                isEnabled: selection.wrappedValue != nil,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onContinue()
                }
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(Color.sweeplyBackground)
        }
    }

    // MARK: - Step 3: Recurring clients

    private var stepRecurringClients: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            goBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Back".translated())
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            advance()
                        } label: {
                            Text("Skip".translated())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Who are your regulars?".translated())
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.6)

                        Text("We'll add them to your client list.".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 28)

                    VStack(spacing: 10) {
                        ForEach($recurringCards) { $card in
                            recurringCardRow(card: $card)
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                recurringCards.append(RecurringCard())
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.sweeplyAccent)
                                Text("Add another client".translated())
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.sweeplyAccent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.5)
            primaryButton(
                label: "Continue",
                isEnabled: recurringCards.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty },
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    focusedField = nil
                    advance()
                }
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(Color.sweeplyBackground)
        }
    }

    @ViewBuilder
    private func recurringCardRow(card: Binding<RecurringCard>) -> some View {
        HStack(spacing: 10) {
            TextField("Client name".translated(), text: card.name)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.sweeplyBorder, lineWidth: 1))
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                ForEach(["W", "2W", "M"], id: \.self) { freq in
                    let full = freq == "W" ? "Weekly" : freq == "2W" ? "Biweekly" : "Monthly"
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        card.frequency.wrappedValue = full
                    } label: {
                        Text(freq)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(card.frequency.wrappedValue == full ? .white : Color.sweeplyTextSub)
                            .frame(width: 34, height: 34)
                            .background(card.frequency.wrappedValue == full ? Color.sweeplyAccent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1))

            if recurringCards.count > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        recurringCards.removeAll { $0.id == card.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(width: 28, height: 28)
                        .background(Color.sweeplySurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.sweeplyBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 4: Name

    private var stepName: some View {
        accountCreationPage(
            title: "What's your\nname?",
            subtitle: "This appears on your invoices and client messages.",
            content: {
                AnyView(VStack(spacing: 12) {
                    OnboardingField(
                        placeholder: "First name",
                        text: $firstName,
                        icon: "person",
                        keyboardType: .default,
                        submitLabel: .next,
                        onSubmit: { focusedField = .business }
                    )
                    .focused($focusedField, equals: .name)

                    OnboardingField(
                        placeholder: "Last name",
                        text: $lastName,
                        icon: "person",
                        keyboardType: .default,
                        submitLabel: .done,
                        onSubmit: { focusedField = nil }
                    )
                    .focused($focusedField, equals: .phone)
                })
            },
            isEnabled: !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
                       !lastName.trimmingCharacters(in: .whitespaces).isEmpty,
            onContinue: { advance() }
        )
    }

    // MARK: - Step 5: Business name

    private var stepBusinessName: some View {
        accountCreationPage(
            title: "Name your\nbusiness",
            subtitle: "You can change this anytime in Settings.",
            content: {
                AnyView(OnboardingField(
                    placeholder: "e.g. Sunrise Cleaning",
                    text: $businessName,
                    icon: "building.2",
                    keyboardType: .default,
                    submitLabel: .done,
                    onSubmit: { focusedField = nil }
                )
                .focused($focusedField, equals: .business))
            },
            isEnabled: !businessName.trimmingCharacters(in: .whitespaces).isEmpty,
            onContinue: { advance() }
        )
    }

    // MARK: - Step 6: Email

    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    private var stepEmail: some View {
        accountCreationPage(
            title: "What's your\nemail?",
            subtitle: nil,
            content: {
                AnyView(VStack(alignment: .leading, spacing: 20) {
                    OnboardingField(
                        placeholder: "your@email.com",
                        text: $email,
                        icon: "envelope",
                        keyboardType: .emailAddress,
                        submitLabel: .continue,
                        onSubmit: {
                            emailFocused = false
                            if isValidEmailAddress(email) { advance() }
                        }
                    )
                    .focused($emailFocused, equals: true)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    // Enable Passcode button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        usePasscode = true
                        emailFocused = false
                        if isValidEmailAddress(email) { advance() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.sweeplyAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Passcode".translated())
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Text("Sign in with Face ID instead of a password".translated())
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyBorder)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Terms agreement
                    HStack(spacing: 4) {
                        Text("I agree to Sweeply's".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Button {
                            if let url = URL(string: "https://sweeplyapp.online/terms") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Terms of Service".translated())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyAccent)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        Text("and".translated())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Button {
                            if let url = URL(string: "https://sweeplyapp.online/privacy") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Privacy Policy".translated())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.sweeplyAccent)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                })
            },
            isEnabled: isValidEmailAddress(email),
            onContinue: { advance() }
        )
    }

    // MARK: - Step 7: Password

    private var stepPassword: some View {
        accountCreationPage(
            title: "Create a\npassword",
            subtitle: nil,
            content: {
                AnyView(VStack(alignment: .leading, spacing: 20) {
                    // Password field with show/hide
                    HStack(spacing: 0) {
                        Image(systemName: "lock")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .frame(width: 44)

                        Group {
                            if showPassword {
                                TextField("Password".translated(), text: $password)
                            } else {
                                SecureField("Password".translated(), text: $password)
                            }
                        }
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($passwordFocused, equals: true)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .frame(width: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 52)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(passwordFocused ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: passwordFocused ? 1.5 : 1))

                    // Live checklist
                    VStack(alignment: .leading, spacing: 10) {
                        passwordCheckRow("At least 8 characters", met: passwordHas8)
                        passwordCheckRow("1 uppercase letter", met: passwordHasUpper)
                        passwordCheckRow("1 lowercase letter", met: passwordHasLower)
                        passwordCheckRow("1 number", met: passwordHasNumber)
                    }
                    .padding(.horizontal, 4)

                    // Error
                    if let err = accountError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyDestructive)
                            .padding(.horizontal, 4)
                    }
                })
            },
            isEnabled: passwordIsValid && !isCreatingAccount,
            onContinue: {
                focusedField = nil
                passwordFocused = false
                advance()
            },
            isLoading: isCreatingAccount
        )
    }

    @ViewBuilder
    private func passwordCheckRow(_ label: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(met ? Color.green : Color.sweeplyBorder)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: met)
            Text(label.translated())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(met ? Color.sweeplyNavy : Color.sweeplyTextSub)
                .animation(.easeInOut(duration: 0.2), value: met)
        }
    }

    // MARK: - Account creation page builder

    private func accountCreationPage(
        title: String,
        subtitle: String?,
        content: () -> AnyView,
        isEnabled: Bool,
        onContinue: @escaping () -> Void,
        isLoading: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back".translated())
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: subtitle != nil ? 8 : 0) {
                        Text(title.translated())
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineSpacing(2)
                            .tracking(-0.6)

                        if let sub = subtitle {
                            Text(sub.translated())
                                .font(.system(size: 15))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)

                    content()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.5)
            primaryButton(
                label: isLoading ? "Creating account…" : "Continue",
                isEnabled: isEnabled,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(Color.sweeplyBackground)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func isValidEmailAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    // MARK: - Step 8: Services (was Step 2)

    private var stepServices: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What services\ndo you offer?".translated())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineSpacing(2)
                        .tracking(-0.6)

                    Text("Prices are fully editable anytime in Settings.".translated())
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer().frame(height: 24)

                // Main services — 2-column grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("MAIN SERVICES".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                        .padding(.horizontal, 24)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(allMainServices) { service in
                            ServiceGridCard(
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

                        // Add new main service button
                        Button {
                            newServiceIsAddon = false
                            showCreateService = true
                            newServiceName = ""
                            newServicePrice = ""
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Text("Add".translated())
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 90)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.sweeplyBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 28)

                // Add-ons — compact list
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD-ONS & EXTRAS".translated())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(0.8)
                        .padding(.horizontal, 24)

                    VStack(spacing: 8) {
                        ForEach(allAddonServices) { service in
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

                        // Add new addon button
                        Button {
                            newServiceIsAddon = true
                            showCreateService = true
                            newServiceName = ""
                            newServicePrice = ""
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Text("Add extra service".translated())
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.sweeplyBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 40)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.5)
                primaryButton(
                    label: "Continue",
                    isEnabled: servicesStepValid,
                    action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        focusedField = nil
                        advance()
                    }
                )
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.sweeplyBackground)
        }
    }

    private var servicesStepValid: Bool {
        allMainServices.contains { selectedServices.contains($0.name) }
    }

    // MARK: - Step 3: Team

    private var stepTeam: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Build your team".translated())
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.6)

                        Text("Invite team members who'll complete jobs with you. You can always add more later.".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer().frame(height: 32)

                    // Name + email inputs
                    VStack(spacing: 10) {
                        // Name field
                        HStack(spacing: 12) {
                            Image(systemName: "person")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .frame(width: 24)
                            TextField("Their name", text: $teamInviteName)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.sweeplyNavy)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .onSubmit { teamField = .email }
                                .focused($teamField, equals: .name)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(teamField == .name ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.15), value: teamField == .name)

                        // Email + add button
                        HStack(spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                    .frame(width: 24)
                                TextField("Email address", text: $teamInviteEmail)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.sweeplyNavy)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .onSubmit { addTeamMember() }
                                    .focused($teamField, equals: .email)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(teamField == .email ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1)
                            )
                            .animation(.easeInOut(duration: 0.15), value: teamField == .email)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                addTeamMember()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(teamInviteValid ? Color.sweeplyNavy : Color.sweeplyBorder)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!teamInviteValid)
                            .animation(.easeInOut(duration: 0.15), value: teamInviteValid)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Added members
                    if !teamInviteMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PENDING INVITES".translated())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .tracking(0.8)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 12)

                            VStack(spacing: 0) {
                                ForEach(Array(teamInviteMembers.enumerated()), id: \.element.id) { idx, member in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.sweeplyNavy.opacity(0.08))
                                                .frame(width: 36, height: 36)
                                            Text(String(member.name.prefix(1)).uppercased())
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color.sweeplyNavy)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)
                                            Text(member.email)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Button {
                                            let i = idx
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                teamInviteMembers.remove(at: i)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                                .frame(width: 28, height: 28)
                                                .background(Color.sweeplyBorder.opacity(0.5))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)

                                    if idx < teamInviteMembers.count - 1 {
                                        Divider().padding(.leading, 72)
                                    }
                                }
                            }
                            .background(Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.sweeplyBorder, lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("Fill in name and email above to add a team member.".translated())
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }

                    Spacer().frame(height: 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.5)
            primaryButton(
                label: teamInviteMembers.isEmpty ? "Skip for now" : "Continue",
                isEnabled: true,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    teamField = nil
                    advance()
                }
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(Color.sweeplyBackground)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var teamInviteValid: Bool {
        let email = teamInviteEmail.trimmingCharacters(in: .whitespaces)
        let name = teamInviteName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && email.contains("@") && email.contains(".")
            && !teamInviteMembers.contains(where: { $0.email == email })
    }

    private func addTeamMember() {
        let email = teamInviteEmail.trimmingCharacters(in: .whitespaces)
        let name = teamInviteName.trimmingCharacters(in: .whitespaces)
        guard teamInviteValid else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            teamInviteMembers.append(TeamInvite(name: name, email: email))
            teamInviteEmail = ""
            teamInviteName = ""
            teamField = nil
        }
    }

    // MARK: - Step 4: Notifications

    private var stepNotifications: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top: hero image ──────────────────────────────────
                Image("NotificationsImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.22, green: 0.50, blue: 0.92))

                // ── Bottom: content card flush with image ─────────────
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stay in the loop".translated())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Get notified about upcoming jobs, payments, and team updates.".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 28)
                    .padding(.bottom, 32)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        NotificationManager.shared.requestAuthorization()
                        notificationRequested = true
                        advance()
                    } label: {
                        Text("Enable Notifications".translated())
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 8, x: 0, y: 4)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        advance()
                    } label: {
                        Text("Maybe later".translated())
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.top, 12)

                    Spacer().frame(height: geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom + 8 : 28)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background(Color.sweeplyBackground)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Step 6: Paywall (trial intro)

    private var stepPaywall: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Trial hero ────────────────────────────────────────
                VStack(spacing: 8) {
                    Image("MascotSweeply")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .padding(.top, 20)

                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Your free trial starts today".translated())
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.sweeplyAccent.opacity(0.10))
                    .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())

                    VStack(spacing: 4) {
                        Text("30 days free,\nthen choose your plan.".translated())
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .multilineTextAlignment(.center)
                            .tracking(-0.4)
                        Text("No payment needed until your trial ends.".translated())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 16)

                // ── Plan toggle ───────────────────────────────────────
                obPlanToggle
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                // ── Feature box ───────────────────────────────────────
                obFeatureBox
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                // ── Billing cards ─────────────────────────────────────
                obBillingCards
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                if let err = paywallError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyDestructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                // ── CTA ───────────────────────────────────────────────
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await obStartTrial() }
                } label: {
                    Group {
                        if paywallPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Start Free Trial".translated())
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(paywallPlan == .pro ? Color.sweeplyAccent : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.sweeplyNavy.opacity(0.18), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(paywallPurchasing)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    advance()
                } label: {
                    Text("I'll decide later".translated())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .task { await subscriptionManager.loadOfferings() }
    }

    private var obPlanToggle: some View {
        HStack(spacing: 0) {
            ForEach(OBPlan.allCases, id: \.self) { plan in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { paywallPlan = plan }
                } label: {
                    HStack(spacing: 6) {
                        Text(plan.rawValue)
                            .font(.system(size: 14, weight: paywallPlan == plan ? .semibold : .regular))
                            .foregroundStyle(paywallPlan == plan ? .white : Color.sweeplyNavy.opacity(0.5))
                        if plan == .pro {
                            Text("Popular".translated())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(paywallPlan == .pro ? .white : Color.sweeplyAccent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(paywallPlan == .pro ? Color.white.opacity(0.2) : Color.sweeplyAccent.opacity(0.15))
                                .overlay(Capsule().stroke(paywallPlan == .pro ? Color.white.opacity(0.3) : Color.sweeplyAccent.opacity(0.5), lineWidth: 1))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(paywallPlan == plan ? Color.sweeplyNavy : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.sweeplyNavy.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var obFeatureBox: some View {
        let features: [(icon: String, text: String, highlight: Bool)] = paywallPlan == .pro ? [
            ("checkmark.circle.fill",              "Everything in Standard",           true),
            ("person.3.fill",                      "Unlimited cleaners & teams",        false),
            ("chart.bar.xaxis",                    "Revenue analytics dashboard",       false),
            ("checklist",                          "Custom job checklists & notes",     false),
            ("waveform.path.ecg",                  "Predictive cash flow",              false),
            ("envelope.badge.fill",                "Invoice reminders & tracking",      false),
            ("bubble.left.and.bubble.right.fill",  "Team messaging & job updates",      false),
            ("folder.badge.plus",                  "Unlimited expense categories",      false),
        ] : [
            ("person.fill",           "Unlimited client profiles",        false),
            ("briefcase.fill",        "Unlimited jobs & invoices",        false),
            ("person.2.fill",         "Add up to 3 team members",        false),
            ("calendar",              "Smart calendar & recurring jobs",  false),
            ("chart.pie.fill",        "Expense categorization",           false),
            ("square.grid.2x2.fill",  "Home-screen widgets",             false),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(features, id: \.text) { f in
                HStack(spacing: 10) {
                    Image(systemName: f.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(f.highlight ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.45))
                        .frame(width: 18)
                    Text(f.text)
                        .font(.system(size: 13, weight: f.highlight ? .semibold : .regular))
                        .foregroundStyle(f.highlight ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.75))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    paywallPlan == .pro
                        ? LinearGradient(colors: [Color.sweeplyAccent.opacity(0.5), Color.sweeplyAccent.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.sweeplyNavy.opacity(0.12), Color.sweeplyNavy.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: paywallPlan)
    }

    private var obBillingCards: some View {
        let monthlyPrice = paywallPlan == .pro
            ? (subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")?.storeProduct.localizedPriceString ?? "$19.99")
            : (subscriptionManager.offerings?.current?.package(identifier: "$rc_monthly")?.storeProduct.localizedPriceString ?? "$8.99")
        let yearlyPrice = paywallPlan == .pro
            ? (subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_yearly")?.storeProduct.localizedPriceString ?? "$179.99")
            : (subscriptionManager.offerings?.current?.package(identifier: "$rc_annual")?.storeProduct.localizedPriceString ?? "$79.99")
        let yearlyPerMonth = paywallPlan == .pro ? "~$15.00/mo" : "~$6.67/mo"

        return HStack(spacing: 10) {
            ForEach(OBBilling.allCases, id: \.self) { period in
                let isSelected = paywallBilling == period
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { paywallBilling = period }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(period.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.5))
                            Spacer()
                            if period == .yearly {
                                Text("Save 26%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.35))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(isSelected ? Color.sweeplyAccent.opacity(0.12) : Color.sweeplyNavy.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(period == .monthly ? monthlyPrice : yearlyPrice)
                            .font(Font.sweeplyDisplay(17, weight: .bold))
                            .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.45))
                        Text(period == .monthly ? "/month" : "\(yearlyPerMonth) · billed yearly")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.sweeplyNavy.opacity(0.5) : Color.sweeplyNavy.opacity(0.3))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Color.sweeplySurface : Color.sweeplyNavy.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.1), lineWidth: isSelected ? 1.5 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: isSelected ? Color.sweeplyAccent.opacity(0.08) : .clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func obStartTrial() async {
        // Attempt to purchase the selected plan; if no package is loaded, just advance
        let package: Package?
        switch (paywallPlan, paywallBilling) {
        case (.pro,      .monthly): package = subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")
        case (.pro,      .yearly):  package = subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_yearly")
        case (.standard, .monthly): package = subscriptionManager.offerings?.current?.package(identifier: "$rc_monthly")
        case (.standard, .yearly):  package = subscriptionManager.offerings?.current?.package(identifier: "$rc_annual")
        }
        guard let package else { advance(); return }

        paywallPurchasing = true
        paywallError = nil
        do {
            try await subscriptionManager.purchase(package: package)
            paywallPurchasing = false
            advance()
        } catch {
            paywallPurchasing = false
            if (error as NSError).code != 1 {
                paywallError = "Purchase failed — you can still start your free trial."
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                paywallError = nil
                advance()
            }
        }
    }

    // MARK: - Step 5: Location

    private var stepLocation: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top: hero image ──────────────────────────────────
                Image("LocationImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.22, green: 0.50, blue: 0.92))

                // ── Bottom: content card flush with image ─────────────
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enable your location".translated())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Quickly find nearby jobs and get directions to your clients.".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 28)
                    .padding(.bottom, 32)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        LocationManager.shared.requestPermission()
                        locationRequested = true
                        advance()
                    } label: {
                        Text("Enable Location".translated())
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 8, x: 0, y: 4)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        advance()
                    } label: {
                        Text("Maybe later".translated())
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.top, 12)

                    Spacer().frame(height: geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom + 8 : 28)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background(Color.sweeplyBackground)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Step 7: All Set

    private var stepAllSet: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top: hero image ───────────────────────────────────
                Image("AllSetImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.22, green: 0.50, blue: 0.92))

                // ── Bottom: content card ──────────────────────────────
                VStack(spacing: 0) {

                    // Headline
                    VStack(alignment: .leading, spacing: 6) {
                        Text("%@, your business is ready.".translated(with: firstName))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Start booking jobs, sending invoices, and getting paid.".translated())
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                    // Bullet rows
                    VStack(alignment: .leading, spacing: 12) {
                        let biz = businessName.trimmingCharacters(in: .whitespaces)
                        allSetBullet(
                            icon: "person.crop.circle.fill",
                            text: biz.isEmpty ? "Your profile is set up" : "\(biz) is set up"
                        )

                        let mainCount = allMainServices.filter { selectedServices.contains($0.name) }.count
                        let addonCount = allAddonServices.filter { selectedServices.contains($0.name) }.count
                        if mainCount > 0 || addonCount > 0 {
                            let mainPart = mainCount > 0 ? "\(mainCount) service\(mainCount == 1 ? "" : "s")" : nil
                            let addonPart = addonCount > 0 ? "\(addonCount) extra\(addonCount == 1 ? "" : "s")" : nil
                            let catalogText = [mainPart, addonPart].compactMap { $0 }.joined(separator: " & ")
                            allSetBullet(icon: "sparkles", text: "\(catalogText) added to your catalog")
                        }

                        allSetBullet(icon: "doc.text.fill",  text: "Invoices & payments ready")
                        allSetBullet(icon: "calendar",       text: "Calendar & scheduling ready")

                        if !teamInviteMembers.isEmpty {
                            allSetBullet(
                                icon: "person.2.fill",
                                text: "\(teamInviteMembers.count) team invite\(teamInviteMembers.count == 1 ? "" : "s") sent"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)

                    // Error banner
                    if saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13))
                            Text("Couldn't save — tap to try again.".translated())
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.sweeplyDestructive)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sweeplyDestructive.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // CTA
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        saveAndFinish()
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text(saveError ? "Try Again" : "Open Dashboard")
                                    .font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(isSaving ? Color.sweeplyNavy.opacity(0.45) : Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isSaving)
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom + 8 : 28)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background(Color.sweeplyBackground)
                .opacity(checkmarkAppeared ? 1 : 0)
                .offset(y: checkmarkAppeared ? 0 : 32)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            checkmarkAppeared = false
            saveError = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.1)) {
                checkmarkAppeared = true
            }
        }
    }

    private func allSetBullet(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.75))
        }
    }


    // MARK: - Primary Button (light steps)

    private func primaryButton(
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isEnabled ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(
                    color: isEnabled ? Color.sweeplyNavy.opacity(0.22) : .clear,
                    radius: 8, x: 0, y: 4
                )
        }
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
        .padding(.horizontal, 24)
    }

    // MARK: - Save

    private func saveAndFinish() {
        guard let userId = session.userId else { return }
        isSaving = true
        saveError = false

        Task {
            var profile = profileStore.profile ?? UserProfile(
                id: userId,
                fullName: fullName,
                businessName: businessName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: AppSettings()
            )
            profile.fullName    = fullName
            profile.businessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.email       = email.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.phone       = phone.trimmingCharacters(in: .whitespacesAndNewlines)

            let chosenServices = AppSettings.defaultServiceCatalog.filter {
                selectedServices.contains($0.name)
            } + customServices.filter { selectedServices.contains($0.name) }
            if !chosenServices.isEmpty {
                profile.settings.services = chosenServices
            }

            let success = await profileStore.save(profile, userId: userId)

            if success && !teamInviteMembers.isEmpty {
                for member in teamInviteMembers {
                    let tm = TeamMember(
                        ownerId: userId,
                        name: member.name,
                        email: member.email,
                        phone: "",
                        role: .member,
                        status: .invited,
                        addedAt: Date()
                    )
                    _ = await teamStore.add(tm)
                }
            }

            // Save recurring clients from Page D
            if success {
                for card in recurringCards where !card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let client = Client(
                        id: UUID(),
                        name: card.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        email: "",
                        phone: "",
                        address: "",
                        city: "",
                        state: "",
                        zip: "",
                        preferredService: nil,
                        entryInstructions: "",
                        notes: "Recurring: \(card.frequency)"
                    )
                    _ = await clientsStore.insert(client, userId: userId)
                }
            }

            await MainActor.run {
                isSaving = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    withAnimation { saveError = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Feature Pill (Step 0)

private struct OnboardingFeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 22)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Service Grid Card (Step 2 — Main Services)

private struct ServiceGridCard: View {
    let service: BusinessService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()

                    Text(service.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(service.price.currency)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.sweeplyAccent : Color.sweeplyTextSub)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 90)
                .background(isSelected ? Color.sweeplyAccent.opacity(0.06) : Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSelected ? Color.sweeplyAccent.opacity(0.45) : Color.sweeplyBorder,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: isSelected)

                // Checkmark badge
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(8)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.5)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Onboarding Field

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
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

// MARK: - Service Selection Card (Add-ons row)

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
                    .background(
                        isSelected
                            ? Color.sweeplyAccent.opacity(0.08)
                            : Color.sweeplyNavy.opacity(0.05)
                    )
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.sweeplyAccent.opacity(0.05) : Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.sweeplyAccent.opacity(0.35) : Color.sweeplyBorder,
                        lineWidth: 1
                    )
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

// MARK: - Create Service Sheet

private struct CreateServiceSheet: View {
    let isAddon: Bool
    @Binding var name: String
    @Binding var price: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: PriceField?

    private enum PriceField { case price }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(price.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel".translated(), action: onCancel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Spacer()
                Text(isAddon ? "Add Extra".translated() : "Add Service".translated())
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Save".translated(), action: onSave)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isValid ? Color.sweeplyAccent : Color.sweeplyTextSub)
                    .disabled(!isValid)
            }
            .padding(20)

            Spacer()

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Service Name".translated())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    TextField("e.g. Carpet Cleaning", text: $name)
                        .font(.system(size: 17))
                        .padding(14)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Price".translated())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    HStack(spacing: 4) {
                        Text("$".translated())
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.sweeplyTextSub)
                        TextField("0", text: $price)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(14)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onSave) {
                Text("Add Service".translated())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValid ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.sweeplySurface)
        .onAppear {
            focusedField = .price
        }
    }
}
