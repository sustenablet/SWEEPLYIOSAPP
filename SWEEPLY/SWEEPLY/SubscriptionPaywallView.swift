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
    @State private var ctaPressed = false

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

    private var standardMonthlyPrice: String {
        subscriptionManager.offerings?.current?.package(identifier: "$rc_monthly")?.storeProduct.localizedPriceString ?? "$8.99"
    }
    private var standardYearlyPrice: String {
        subscriptionManager.offerings?.current?.package(identifier: "$rc_annual")?.storeProduct.localizedPriceString ?? "$79.99"
    }
    private var proMonthlyPrice: String {
        subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")?.storeProduct.localizedPriceString ?? "$19.99"
    }
    private var proYearlyPrice: String {
        subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_yearly")?.storeProduct.localizedPriceString ?? "$179.99"
    }

    private var currentMonthlyPrice: String { selectedPlan == .pro ? proMonthlyPrice : standardMonthlyPrice }
    private var currentYearlyPrice: String  { selectedPlan == .pro ? proYearlyPrice  : standardYearlyPrice }
    private var currentYearlyPerMonth: String { selectedPlan == .pro ? "~$15.00/mo" : "~$6.67/mo" }

    // MARK: - Body

    var body: some View {
        ZStack {
            atmosphereBackground
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        centeredLogo
                            .padding(.top, 4)
                            .padding(.bottom, 12)

                        header
                            .padding(.bottom, 20)

                        planToggle
                            .padding(.bottom, 16)

                        featureBox
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)

                        billingCards
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)

                        if let error = purchaseError {
                            errorBanner(error)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }

                        ctaButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

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
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        closeButton
                    }
                }
            }
        }
        .task { await subscriptionManager.loadOfferings() }
    }

    // MARK: - Background

    private var atmosphereBackground: some View {
        Color.sweeplyBackground.ignoresSafeArea()
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(Color.sweeplyNavy.opacity(0.08))
                .overlay(Circle().stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1))
                .clipShape(Circle())
        }
    }

    // MARK: - Centered Logo

    private var centeredLogo: some View {
        Image("MascotSweeply")
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
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
        .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
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
                    .padding(.vertical, 7)
                    .background(selectedPlan == plan ? Color.sweeplyNavy : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.sweeplyNavy.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.sweeplyNavy.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Feature Box

    private var featureBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(features(for: selectedPlan), id: \.text) { item in
                featureRow(item.text, icon: item.icon, highlight: item.highlight)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    selectedPlan == .pro
                        ? LinearGradient(
                            colors: [Color.sweeplyAccent.opacity(0.5), Color.sweeplyAccent.opacity(0.15), Color.sweeplyNavy.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: [Color.sweeplyNavy.opacity(0.12), Color.sweeplyNavy.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: selectedPlan == .pro ? Color.sweeplyAccent.opacity(0.10) : Color.sweeplyNavy.opacity(0.06), radius: 20, x: 0, y: 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlan)
    }

    private struct FeatureItem {
        let text: String
        let icon: String
        var highlight: Bool = false
    }

    private func features(for plan: PlanType) -> [FeatureItem] {
        switch plan {
        case .pro:
            return [
                FeatureItem(text: "Everything in Standard",              icon: "checkmark.circle.fill",              highlight: true),
                FeatureItem(text: "Unlimited cleaners & teams",          icon: "person.3.fill"),
                FeatureItem(text: "Revenue analytics dashboard",         icon: "chart.bar.xaxis"),
                FeatureItem(text: "Profit & loss breakdown",             icon: "doc.text.fill"),
                FeatureItem(text: "Predictive cash flow",                icon: "waveform.path.ecg"),
                FeatureItem(text: "Custom job checklists & notes",       icon: "checklist"),
                FeatureItem(text: "Invoice reminders & tracking",        icon: "envelope.badge.fill"),
                FeatureItem(text: "Team messaging & job updates",        icon: "bubble.left.and.bubble.right.fill"),
                FeatureItem(text: "Unlimited expense categories",        icon: "folder.badge.plus"),
            ]
        case .standard:
            return [
                FeatureItem(text: "Unlimited client profiles",        icon: "person.fill"),
                FeatureItem(text: "Unlimited jobs & invoices",        icon: "briefcase.fill"),
                FeatureItem(text: "Add up to 3 team members",        icon: "person.2.fill"),
                FeatureItem(text: "Smart calendar & recurring jobs",  icon: "calendar"),
                FeatureItem(text: "Expense categorization",           icon: "chart.pie.fill"),
                FeatureItem(text: "Home-screen widgets",              icon: "square.grid.2x2.fill"),
            ]
        }
    }

    private func featureRow(_ text: String, icon: String, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(highlight ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.45))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.75))
        }
    }

    // MARK: - Billing Cards

    private var billingCards: some View {
        HStack(spacing: 10) {
            billingCard(period: .monthly)
            billingCard(period: .yearly)
        }
    }

    private func billingCard(period: BillingPeriod) -> some View {
        let isSelected = billing == period
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { billing = period }
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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(isSelected ? Color.sweeplyAccent.opacity(0.12) : Color.sweeplyNavy.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                Text(period == .monthly ? currentMonthlyPrice : currentYearlyPrice)
                    .font(Font.sweeplyDisplay(18, weight: .bold))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.45))
                Text(period == .monthly ? "/month" : "\(currentYearlyPerMonth) · billed yearly")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy.opacity(0.5) : Color.sweeplyNavy.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white : Color.sweeplyNavy.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isSelected ? Color.sweeplyAccent.opacity(0.10) : .clear, radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ctaPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { ctaPressed = false }
            let package = selectedPlan == .pro ? proPackage : standardPackage
            Task { await purchase(package) }
        } label: {
            HStack(spacing: 8) {
                if subscriptionManager.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedPlan == .pro ? "Get Pro" : "Get Standard")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedPlan == .pro ? Color.sweeplyAccent : Color.sweeplyNavy)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .scaleEffect(ctaPressed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.12), value: ctaPressed)
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
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                footerLink("Terms of Service") {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        UIApplication.shared.open(url)
                    }
                }
                footerDot
                footerLink("Privacy Policy") {
                    if let url = URL(string: "https://www.apple.com/legal/privacy/") {
                        UIApplication.shared.open(url)
                    }
                }
                footerDot
                footerLink("Restore Purchases") {
                    Task {
                        try? await subscriptionManager.restorePurchases()
                        if subscriptionManager.isSubscribed { dismiss() }
                    }
                }
            }
            Text("Cancel anytime · Auto-renews · Prices in USD")
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.25))
                .multilineTextAlignment(.center)
        }
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    private var footerDot: some View {
        Text(" · ")
            .font(.system(size: 12))
            .foregroundStyle(Color.sweeplyNavy.opacity(0.2))
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

// MARK: - Shared feature data

private let proFeatures: [(icon: String, text: String)] = [
    ("checkmark.circle.fill",             "Everything in Standard"),
    ("person.3.fill",                     "Unlimited cleaners & teams"),
    ("chart.bar.xaxis",                   "Revenue analytics dashboard"),
    ("doc.text.fill",                     "Profit & loss breakdown"),
    ("waveform.path.ecg",                 "Predictive cash flow"),
    ("checklist",                         "Custom job checklists & notes"),
    ("envelope.badge.fill",               "Invoice reminders & tracking"),
    ("bubble.left.and.bubble.right.fill", "Team messaging & job updates"),
    ("folder.badge.plus",                 "Unlimited expense categories"),
]

private let standardFeatures: [(icon: String, text: String)] = [
    ("person.fill",          "Unlimited client profiles"),
    ("briefcase.fill",       "Unlimited jobs & invoices"),
    ("person.2.fill",        "Up to 3 team members"),
    ("calendar",             "Smart calendar & recurring jobs"),
    ("chart.pie.fill",       "Expense categorization"),
    ("square.grid.2x2.fill", "Home-screen widgets"),
]

// MARK: - SubscriptionProView

struct SubscriptionProView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Close ────────────────────────────────────────────
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy.opacity(0.6))
                                .frame(width: 30, height: 30)
                                .background(Color.sweeplyNavy.opacity(0.07))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // ── Hero ─────────────────────────────────────────────
                    VStack(spacing: 10) {
                        Image("MascotSweeply")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 68)

                        Text("Sweeply Pro")
                            .font(Font.sweeplyDisplay(24, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)

                        // Status card
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("Active")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sweeplyAccent)
                            if let exp = subscriptionManager.expirationDate {
                                Text("·")
                                    .foregroundStyle(Color.sweeplyNavy.opacity(0.3))
                                Text("Renews \(exp.formatted(.dateTime.month(.abbreviated).day().year()))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyNavy.opacity(0.55))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.sweeplyAccent.opacity(0.08))
                        .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .padding(.bottom, 28)

                    // ── What's included ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHAT'S INCLUDED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .tracking(0.8)
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(proFeatures, id: \.text) { f in
                                HStack(spacing: 12) {
                                    Image(systemName: f.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyAccent)
                                        .frame(width: 20)
                                    Text(f.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.sweeplyNavy.opacity(0.8))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(LinearGradient(colors: [Color.sweeplyAccent.opacity(0.4), Color.sweeplyAccent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)

                    // ── Manage button ─────────────────────────────────────
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Manage in App Store")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    Text("To cancel, go to App Store → Subscriptions")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - SubscriptionStandardUpgradeView

struct SubscriptionStandardUpgradeView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var onShowAllPlans: () -> Void = {}

    @State private var isPurchasing = false
    @State private var purchaseError: String?

    private var proMonthlyPrice: String {
        subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")?.storeProduct.localizedPriceString ?? "$19.99"
    }

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Close ────────────────────────────────────────────
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy.opacity(0.6))
                                .frame(width: 30, height: 30)
                                .background(Color.sweeplyNavy.opacity(0.07))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // ── Hero ─────────────────────────────────────────────
                    VStack(spacing: 8) {
                        Image("MascotSweeply")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)

                        Text("You're on Standard")
                            .font(Font.sweeplyDisplay(22, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)

                        Text("Upgrade to unlock everything in Pro.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.bottom, 24)

                    // ── Your plan ─────────────────────────────────────────
                    sectionCard(
                        label: "YOUR PLAN",
                        borderColor: Color.sweeplyNavy.opacity(0.15)
                    ) {
                        ForEach(standardFeatures, id: \.text) { f in
                            featureRow(icon: f.icon, text: f.text, style: .included)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    // ── Unlock with Pro ───────────────────────────────────
                    sectionCard(
                        label: "UNLOCK WITH PRO",
                        borderColor: Color.sweeplyAccent.opacity(0.4)
                    ) {
                        ForEach(proFeatures.filter { $0.text != "Everything in Standard" }, id: \.text) { f in
                            featureRow(icon: f.icon, text: f.text, style: .locked)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    if let err = purchaseError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sweeplyDestructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }

                    // ── Upgrade CTA ───────────────────────────────────────
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await upgradeToPro() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                HStack(spacing: 6) {
                                    Text("Upgrade to Pro")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("· \(proMonthlyPrice)/mo")
                                        .font(.system(size: 14))
                                        .opacity(0.75)
                                }
                                .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.sweeplyAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    Button {
                        dismiss()
                        onShowAllPlans()
                    } label: {
                        Text("See all plans & pricing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                }
            }
        }
        .task { await subscriptionManager.loadOfferings() }
    }

    private enum FeatureStyle { case included, locked }

    private func featureRow(icon: String, text: String, style: FeatureStyle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: style == .locked ? "lock.fill" : icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style == .locked ? Color.sweeplyAccent : Color.sweeplySuccess)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(style == .locked ? Color.sweeplyNavy.opacity(0.7) : Color.sweeplyNavy.opacity(0.8))
        }
    }

    private func sectionCard(label: String, borderColor: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
    }

    private func upgradeToPro() async {
        guard let package = subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly") else {
            dismiss(); onShowAllPlans(); return
        }
        isPurchasing = true
        purchaseError = nil
        do {
            try await subscriptionManager.purchase(package: package)
            isPurchasing = false
            dismiss()
        } catch {
            isPurchasing = false
            if (error as NSError).code != 1 {
                purchaseError = "Purchase failed — please try again."
            }
        }
    }
}
