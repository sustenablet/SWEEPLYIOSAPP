import SwiftUI
import UserNotifications
import RevenueCat

struct OnboardingView: View {
    private struct TeamInvite: Identifiable {
        let id = UUID()
        var name: String
        var email: String
    }

    @Environment(ProfileStore.self)        private var profileStore
    @Environment(AppSession.self)          private var session
    @Environment(TeamStore.self)           private var teamStore
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

    // Step 1 fields
    @State private var fullName = ""
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
        withAnimation(.easeInOut(duration: 0.28)) { step += 1 }
    }

    private func goBack() {
        focusedField = nil
        goingForward = false
        withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
    }

    var body: some View {
        ZStack {
            (step == 4 || step == 5
                ? Color(red: 0.22, green: 0.50, blue: 0.92)
                : Color.sweeplyBackground
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — shown on data-collection steps only (not paywall/location/all-set)
                if step >= 1 && step <= 4 {
                    headerBar
                        .transition(.opacity)
                }

                ZStack {
                    switch step {
                    case 0: stepWelcome.transition(stepTransition).id(0)
                    case 1: stepIdentity.transition(stepTransition).id(1)
                    case 2: stepServices.transition(stepTransition).id(2)
                    case 3: stepTeam.transition(stepTransition).id(3)
                    case 4: stepNotifications.transition(stepTransition).id(4)
                    case 5: stepLocation.transition(stepTransition).id(5)
                    case 6: stepPaywall.transition(stepTransition).id(6)
                    case 7: stepAllSet.transition(stepTransition).id(7)
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
            if step >= 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Previous")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(step == 4 ? .white : Color.sweeplyNavy)
                }
                .buttonStyle(.plain)
                .frame(width: 80, alignment: .leading)
            } else {
                Color.clear.frame(width: 80, height: 1)
            }

            // Progress bar — 3 steps
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(step == 4 ? Color.white.opacity(0.3) : Color.sweeplyBorder)
                        .frame(height: 4)
                    Capsule()
                        .fill(step == 4 ? Color.white : Color.sweeplyAccent)
                        .frame(width: geo.size.width * (CGFloat(step - 1) / 4.0), height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                }
            }
            .frame(height: 4)

            // Skip — only on step 2 (services), else balance spacer
            if step == 2 {
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

    // MARK: - Step 0: Welcome

    private var stepWelcome: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top: hero image ──────────────────────────────────
                Image("SignupImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 193/255, green: 223/255, blue: 253/255))

                // ── Bottom: content card flush with image ─────────────
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Let's get you set up")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Get your workspace ready and start managing jobs with ease.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 28)
                    .padding(.bottom, 32)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        advance()
                    } label: {
                        Text("Get started".translated())
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom + 8 : 28)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background(Color.sweeplyBackground)
                .opacity(welcomeAppeared ? 1 : 0)
                .offset(y: welcomeAppeared ? 0 : 32)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            welcomeAppeared = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.1)) {
                welcomeAppeared = true
            }
        }
    }

    // MARK: - Step 1: Identity

    private var stepIdentity: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tell us about\nyour business")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .lineSpacing(2)
                            .tracking(-0.6)

                        Text("This appears on your invoices and client messages.".translated())
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer().frame(height: 32)

                    VStack(spacing: 12) {
                        OnboardingField(
                            placeholder: "Your name",
                            text: $fullName,
                            icon: "person",
                            keyboardType: .default,
                            submitLabel: .next,
                            onSubmit: { focusedField = .business }
                        )
                        .focused($focusedField, equals: .name)

                        OnboardingField(
                            placeholder: "Business name (e.g. Sunrise Cleaning)",
                            text: $businessName,
                            icon: "building.2",
                            keyboardType: .default,
                            submitLabel: .next,
                            onSubmit: { focusedField = .phone }
                        )
                        .focused($focusedField, equals: .business)

                        OnboardingField(
                            placeholder: "Phone (optional)",
                            text: $phone,
                            icon: "phone",
                            keyboardType: .phonePad,
                            submitLabel: .done,
                            onSubmit: { focusedField = nil }
                        )
                        .focused($focusedField, equals: .phone)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.5)
            primaryButton(
                label: "Continue",
                isEnabled: identityStepValid,
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { focusedField = nil }
    }

    private var identityStepValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !businessName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step 2: Services

    private var stepServices: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What services\ndo you offer?")
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
                        Text("Build your team")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.6)

                        Text("Invite team members who'll complete jobs with you. You can always add more later.")
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
                            Text("PENDING INVITES")
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
                            Text("Fill in name and email above to add a team member.")
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
                        Text("Stay in the loop")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Get notified about upcoming jobs, payments, and team updates.")
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
                        Text("Enable Notifications")
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
                        Text("Maybe later")
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
                        Text("Your free trial starts today")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.sweeplyAccent.opacity(0.10))
                    .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())

                    VStack(spacing: 4) {
                        Text("30 days free,\nthen choose your plan.")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .multilineTextAlignment(.center)
                            .tracking(-0.4)
                        Text("No payment needed until your trial ends.")
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
                            Text("Start Free Trial")
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
                    Text("I'll decide later")
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
                            Text("Popular")
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
                        Text("Enable your location")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Quickly find nearby jobs and get directions to your clients.")
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
                        Text("Enable Location")
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
                        Text("Maybe later")
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
                Image("MascotSweeply")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 193/255, green: 223/255, blue: 253/255))

                // ── Bottom: content card ──────────────────────────────
                VStack(spacing: 0) {

                    // Headline
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(firstName), you're in business.")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.4)

                        Text("Start booking jobs, sending invoices, and getting paid.")
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
                            Text("Couldn't save — tap to try again.")
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


    private var firstName: String {
        fullName.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "there"
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
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                businessName: businessName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: "",
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: AppSettings()
            )
            profile.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.businessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

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
                Button("Cancel", action: onCancel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Spacer()
                Text(isAddon ? "Add Extra" : "Add Service")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Save", action: onSave)
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
