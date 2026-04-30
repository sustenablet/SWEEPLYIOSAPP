import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Billing Period

private enum BillingPeriod: String, CaseIterable {
    case monthly = "Monthly"
    case yearly  = "Yearly"
}

// MARK: - Plan Type

private enum PlanType: String, CaseIterable {
    case standard = "Standard"
    case pro     = "Pro"
}

// MARK: - SubscriptionPaywallView

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var billing: BillingPeriod = .monthly
    @State private var selectedPlan: PlanType = .pro
    @State private var purchaseError: String?
    @State private var appeared = false
    @State private var proCardPressed = false
    @State private var standardCardPressed = false

    private var standardPackage: Package? {
        billing == .monthly
            ? subscriptionManager.offerings?.current?.package(identifier: "$rc_monthly")
            : subscriptionManager.offerings?.current?.package(identifier: "$rc_annual")
    }
    private var proPackage: Package? {
        billing == .monthly
            ? subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")
            : subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_yearly")
    }

    private var standardPrice: String {
        standardPackage?.storeProduct.localizedPriceString ?? (billing == .monthly ? "$8.99" : "$79.99")
    }
    private var proPrice: String {
        proPackage?.storeProduct.localizedPriceString ?? (billing == .monthly ? "$19.99" : "$179.99")
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            atmosphereBackground
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 12)
                            .padding(.bottom, 24)

                        planToggle
                            .padding(.bottom, 12)

                        billingToggle
                            .padding(.bottom, 24)

                        if let error = purchaseError {
                            errorBanner(error)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }

                        Group {
                            if selectedPlan == .pro {
                                proCard
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity
                                    ))
                            } else {
                                standardCard
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlan)

                        footer
                            .padding(.bottom, 40)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            appeared = true
                        }
                    }
                }
                .background(Color.clear)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        closeButton
                    }
                }
            }
        }
        .task { await subscriptionManager.loadOfferings() }
    }

    // MARK: - Atmosphere Background

    private var atmosphereBackground: some View {
        ZStack {
            // Light blue gradient — soft and non-vibrant
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.85, green: 0.92, blue: 0.98), location: 0),
                    .init(color: Color(red: 0.75, green: 0.88, blue: 0.95), location: 0.5),
                    .init(color: Color(red: 0.70, green: 0.85, blue: 0.93), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle accent glow — top
            Circle()
                .fill(Color.sweeplyAccent.opacity(0.08))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: 0, y: -150)
        }
        .ignoresSafeArea()
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(Color.sweeplyNavy.opacity(0.08))
                .overlay(
                    Circle().stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1)
                )
                .clipShape(Circle())
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            // Mascot + Brand in top left
            HStack {
                Image("MascotSweeply")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                
                Text("Sweeply")
                    .font(Font.sweeplyDisplay(28, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                
                Spacer()
            }
            .padding(.horizontal, 4)

            Text("Run your cleaning business like a pro.")
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.55))
                .multilineTextAlignment(.center)

            if subscriptionManager.isInTrial {
                trialBadge.padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
    }

    private var trialBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "gift.fill")
                .font(.system(size: 11))
            Text("\(subscriptionManager.trialDaysRemaining) days left in your free trial")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.sweeplyAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.sweeplyAccent.opacity(0.15))
        .overlay(
            Capsule().stroke(Color.sweeplyAccent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            ForEach(BillingPeriod.allCases, id: \.self) { period in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { billing = period }
                } label: {
                    HStack(spacing: 6) {
                        Text(period.rawValue)
                            .font(.system(size: 14, weight: billing == period ? .semibold : .regular))
                            .foregroundStyle(billing == period ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.5))
                        if period == .yearly {
                            Text("26% off")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(billing == .yearly ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.4))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(billing == .yearly ? Color.sweeplyAccent.opacity(0.15) : Color.clear)
                                .overlay(
                                    Capsule().stroke(
                                        billing == .yearly ? Color.sweeplyAccent.opacity(0.5) : Color.sweeplyNavy.opacity(0.15),
                                        lineWidth: 1
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        billing == period
                            ? Color.white
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sweeplyNavy.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Plan Toggle

    private var planToggle: some View {
        HStack(spacing: 0) {
            ForEach(PlanType.allCases, id: \.self) { plan in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedPlan = plan }
                } label: {
                    HStack(spacing: 6) {
                        Text(plan.rawValue)
                            .font(.system(size: 14, weight: selectedPlan == plan ? .semibold : .regular))
                            .foregroundStyle(selectedPlan == plan ? .white : Color.sweeplyNavy.opacity(0.5))
                        if plan == .pro {
                            Text("Popular")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(selectedPlan == .pro ? .white : Color.sweeplyAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(selectedPlan == .pro ? Color.white.opacity(0.2) : Color.sweeplyAccent.opacity(0.15))
                                .overlay(
                                    Capsule().stroke(
                                        selectedPlan == .pro ? Color.white.opacity(0.3) : Color.sweeplyAccent.opacity(0.5),
                                        lineWidth: 1
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedPlan == plan
                            ? Color.sweeplyNavy
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sweeplyNavy.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Pro Card

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("PRO")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyAccent)
                        Text("MOST POPULAR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.45))
                            .tracking(0.5)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(proPrice)
                            .font(Font.sweeplyDisplay(36, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text(billing == .monthly ? "/mo" : "/yr")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.45))
                            .padding(.bottom, 4)
                    }
                    if billing == .yearly {
                        Text("~$15.00/mo · billed annually")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            // Divider
            Rectangle()
                .fill(Color.sweeplyNavy.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)

            // Features
            VStack(alignment: .leading, spacing: 12) {
                proFeatureRow("Everything in Standard", icon: "checkmark.circle.fill", highlight: true)
                proFeatureRow("Unlimited team members", icon: "person.3.fill")
                proFeatureRow("Advanced finance dashboard", icon: "chart.bar.xaxis")
                proFeatureRow("Profit & loss reports", icon: "doc.text.fill")
                proFeatureRow("Cash-flow forecasting", icon: "waveform.path.ecg")
                proFeatureRow("Priority support", icon: "bolt.fill")
                proFeatureRow("All future Pro features", icon: "star.fill")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            // CTA
            proCTAButton
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.sweeplyAccent.opacity(0.5),
                            Color.sweeplyAccent.opacity(0.2),
                            Color.sweeplyNavy.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.sweeplyAccent.opacity(0.12), radius: 20, x: 0, y: 8)
        .scaleEffect(proCardPressed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.12), value: proCardPressed)
    }

    private func proFeatureRow(_ text: String, icon: String, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(highlight ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.5))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.75))
        }
    }

    private var proCTAButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            proCardPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { proCardPressed = false }
            Task { await purchase(proPackage) }
        } label: {
            HStack(spacing: 8) {
                if subscriptionManager.isPurchasing {
                    ProgressView().tint(Color.sweeplyNavy)
                } else {
                    Text("Get Pro")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    if billing == .monthly {
                        Text("· 1 month free")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.sweeplyAccent)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
    }

    // MARK: - Standard Card

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STANDARD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
                        .tracking(0.5)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(standardPrice)
                            .font(Font.sweeplyDisplay(36, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text(billing == .monthly ? "/mo" : "/yr")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
                            .padding(.bottom, 4)
                    }
                    if billing == .yearly {
                        Text("~$6.67/mo · billed annually")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.35))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.sweeplyNavy.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                proFeatureRow("Unlimited clients", icon: "person.fill")
                proFeatureRow("Unlimited jobs & invoices", icon: "briefcase.fill")
                proFeatureRow("Team members", icon: "person.2.fill")
                proFeatureRow("Calendar + recurring jobs", icon: "calendar")
                proFeatureRow("Expense tracking + reports", icon: "chart.pie.fill")
                proFeatureRow("Home-screen widgets", icon: "square.grid.2x2.fill")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            standardCTAButton
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(standardCardPressed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.12), value: standardCardPressed)
    }

    private var standardCTAButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            standardCardPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { standardCardPressed = false }
            Task { await purchase(standardPackage) }
        } label: {
            HStack(spacing: 8) {
                if subscriptionManager.isPurchasing {
                    ProgressView().tint(Color.sweeplyNavy)
                } else {
                    Text("Get Standard")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    if billing == .monthly {
                        Text("· 1 month free")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.sweeplyNavy.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.sweeplyNavy.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
    }

    // MARK: - Helpers

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.sweeplyDestructive)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sweeplyDestructive.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.sweeplyDestructive.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func purchase(_ package: Package?) async {
        guard let package else { return }
        purchaseError = nil
        do {
            try await subscriptionManager.purchase(package: package)
            dismiss()
        } catch {
            if (error as NSError).code != 1 {
                purchaseError = "Purchase failed — please try again."
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    try? await subscriptionManager.restorePurchases()
                    if subscriptionManager.isSubscribed { dismiss() }
                }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
            }
            .buttonStyle(.plain)

            Text("Cancel anytime · Auto-renews · Prices in USD")
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.25))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - SubscriptionCustomerCenterView

struct SubscriptionCustomerCenterView: View {
    var body: some View {
        CustomerCenterView()
    }
}

// MARK: - ProGateView

struct ProGateView<Content: View>: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false

    @ViewBuilder var content: () -> Content

    var body: some View {
        if subscriptionManager.hasProAccess {
            content()
        } else {
            upgradePrompt
                .sheet(isPresented: $showPaywall) {
                    SubscriptionPaywallView()
                        .environment(subscriptionManager)
                }
        }
    }

    private var upgradePrompt: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.sweeplyAccent)
            }

            VStack(spacing: 6) {
                Text("Sweeply Pro")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Upgrade to Pro to unlock this feature.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
            }

            Button { showPaywall = true } label: {
                Text("See Plans")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
    }
}
