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

    // Step 3: Team
    @State private var teamInviteEmail = ""
    @State private var teamInviteEmails: [String] = []
    @FocusState private var teamEmailFocused: Bool

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

    // Step 3 state
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var notifDismissed = false
    @State private var checkmarkAppeared = false
    @State private var saveError = false

    @State private var isSaving = false
    @State private var welcomeAppeared = false

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
                // Header — shown on all data-collection steps
                if step >= 1 && step <= 3 {
                    headerBar
                        .transition(.opacity)
                }

                ZStack {
                    switch step {
                    case 0: stepWelcome.transition(stepTransition).id(0)
                    case 1: stepIdentity.transition(stepTransition).id(1)
                    case 2: stepServices.transition(stepTransition).id(2)
                    case 3: stepTeam.transition(stepTransition).id(3)
                    case 4: stepAllSet.transition(stepTransition).id(4)
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Previous — shown on steps 2 and 3
            if step >= 2 {
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
                    .foregroundStyle(Color.sweeplyNavy)
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
                        .fill(Color.sweeplyBorder)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.sweeplyAccent)
                        .frame(width: geo.size.width * (CGFloat(step) / 3.0), height: 4)
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
                    .background(Color(red: 0.757, green: 0.875, blue: 0.992))

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
                        Text("Let's set up\nyour business")
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

                    // Email input row
                    HStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .frame(width: 24)

                            TextField("Team member email", text: $teamInviteEmail)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.sweeplyNavy)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit { addTeamEmail() }
                                .focused($teamEmailFocused)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(teamEmailFocused ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1)
                        )

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            addTeamEmail()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(teamInviteEmailValid ? Color.sweeplyNavy : Color.sweeplyBorder)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!teamInviteEmailValid)
                        .animation(.easeInOut(duration: 0.15), value: teamInviteEmailValid)
                    }
                    .padding(.horizontal, 24)

                    // Added emails
                    if !teamInviteEmails.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PENDING INVITES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .tracking(0.8)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 12)

                            VStack(spacing: 0) {
                                ForEach(Array(teamInviteEmails.enumerated()), id: \.element) { idx, email in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.sweeplyNavy.opacity(0.08))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.sweeplyNavy)
                                        }

                                        Text(email)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Button {
                                            let i = idx
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                teamInviteEmails.remove(at: i)
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

                                    if idx < teamInviteEmails.count - 1 {
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
                        // Empty state hint
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("Add emails above to invite your team.")
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
                label: teamInviteEmails.isEmpty ? "Skip for now" : "Continue",
                isEnabled: true,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    teamEmailFocused = false
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

    private var teamInviteEmailValid: Bool {
        let t = teamInviteEmail.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && !teamInviteEmails.contains(t)
    }

    private func addTeamEmail() {
        let email = teamInviteEmail.trimmingCharacters(in: .whitespaces)
        guard teamInviteEmailValid else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            teamInviteEmails.append(email)
            teamInviteEmail = ""
        }
    }

    // MARK: - Step 4: All Set

    private var stepAllSet: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Animated checkmark with accent circle
                ZStack {
                    Circle()
                        .fill(Color.sweeplyAccent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.sweeplyAccent)
                        .scaleEffect(checkmarkAppeared ? 1.0 : 0.1)
                        .opacity(checkmarkAppeared ? 1.0 : 0)
                }

                VStack(spacing: 14) {
                    Text("Welcome to Sweeply,\n\(firstName)!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .tracking(-0.4)

                    VStack(spacing: 8) {
                        allSetRow(icon: "building.2.fill",
                                  text: businessName.trimmingCharacters(in: .whitespaces))
                        if !selectedServices.isEmpty {
                            allSetRow(
                                icon: "sparkles",
                                text: "\(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s") ready to go"
                            )
                        }
                    }
                }

                if notifStatus == .notDetermined && !notifDismissed {
                    notificationCard
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            // Save error banner
            if saveError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text("Couldn't save your info — tap to try again.".translated())
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.sweeplyDestructive)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sweeplyDestructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Dashboard CTA
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
                .background(Color.sweeplyNavy)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.sweeplyNavy.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .disabled(isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            checkmarkAppeared = false
            saveError = false
            notifDismissed = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.15)) {
                checkmarkAppeared = true
            }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async { notifStatus = settings.authorizationStatus }
            }
        }
    }

    private func allSetRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
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

    private var notificationCard: some View {
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
                Text("Stay on top of jobs & invoices".translated())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Get reminders before they're due".translated())
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                NotificationManager.shared.requestAuthorization()
                withAnimation { notifStatus = .authorized }
            } label: {
                Text("Allow".translated())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.sweeplyAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation { notifDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
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
