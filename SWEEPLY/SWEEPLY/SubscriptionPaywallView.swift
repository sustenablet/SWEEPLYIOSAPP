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
    @State private var restoreMessage: String?
    @State private var appeared = false
    @State private var ctaPressed = false
    @State private var didSetInitialPlan = false

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

    private var currencyFooterText: String {
        let pkg = subscriptionManager.offerings?.current?.package(identifier: "$rc_monthly")
            ?? subscriptionManager.offerings?.current?.package(identifier: "$rc_custom_pro_monthly")
        let code = pkg?.storeProduct.currencyCode ?? "USD"
        return "Cancel anytime · Auto-renews · Prices in %@".translated(with: code)
    }

    private var currentMonthlyPrice: String { selectedPlan == .pro ? proMonthlyPrice : standardMonthlyPrice }
    private var currentYearlyPrice: String  { selectedPlan == .pro ? proYearlyPrice  : standardYearlyPrice }
    private var currentYearlyPerMonth: String {
        let yearlyID = selectedPlan == .pro ? "$rc_custom_pro_yearly" : "$rc_annual"
        if let pkg = subscriptionManager.offerings?.current?.package(identifier: yearlyID) {
            let monthly = pkg.storeProduct.price / 12
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = pkg.storeProduct.currencyCode ?? "USD"
            formatter.maximumFractionDigits = 2
            if let str = formatter.string(from: NSDecimalNumber(decimal: monthly)) {
                return "~\(str)/mo"
            }
        }
        return selectedPlan == .pro ? "~$15.00/mo" : "~$6.67/mo"
    }

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
        .task { await fetchOfferings() }
    .onAppear {
        guard !didSetInitialPlan else { return }
        didSetInitialPlan = true
        // Pre-select the current plan so subscribed users land on their own tab
        if subscriptionManager.isPro { selectedPlan = .pro }
        else if subscriptionManager.isStandard { selectedPlan = .pro } // nudge Standard → Pro upgrade
    }
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
            Text(headerSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.55))
                .multilineTextAlignment(.center)

            statusBadge.padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }

    private var headerSubtitle: String {
        if subscriptionManager.isPro    { return "You're on Sweeply Pro — manage or explore your plan below.".translated() }
        if subscriptionManager.isStandard { return "You're on Standard — upgrade to Pro to unlock everything.".translated() }
        return "Run your cleaning business like a pro.".translated()
    }

    @ViewBuilder
    private var statusBadge: some View {
        if subscriptionManager.isPro {
            planBadge(
                icon: "checkmark.seal.fill",
                label: proStatusLabel,
                color: Color.sweeplyAccent
            )
        } else if subscriptionManager.isStandard {
            planBadge(
                icon: "star.circle.fill",
                label: "Standard Plan — Active".translated(),
                color: Color.sweeplyNavy
            )
        } else if subscriptionManager.isInTrial {
            planBadge(
                icon: "gift.fill",
                label: "%d days left in your free trial".translated(with: subscriptionManager.trialDaysRemaining),
                color: Color.sweeplyAccent
            )
        }
    }

    private var proStatusLabel: String {
        if let exp = subscriptionManager.expirationDate {
            return "Pro · Renews %@".translated(with: exp.formatted(.dateTime.month(.abbreviated).day()))
        }
        return "Sweeply Pro — Active".translated()
    }

    private func planBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
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
                        Text(plan.rawValue.translated())
                            .font(.system(size: 14, weight: selectedPlan == plan ? .semibold : .regular))
                            .foregroundStyle(selectedPlan == plan ? .white : Color.sweeplyNavy.opacity(0.5))
                        if plan == .pro {
                            Text("Popular".translated())
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
                        if plan == .standard && subscriptionManager.isStandard && !subscriptionManager.isPro {
                            Text("Active".translated())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(selectedPlan == .standard ? .white : Color.sweeplySuccess)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(selectedPlan == .standard ? Color.white.opacity(0.2) : Color.sweeplySuccess.opacity(0.15))
                                .overlay(
                                    Capsule().stroke(
                                        selectedPlan == .standard ? Color.white.opacity(0.3) : Color.sweeplySuccess.opacity(0.5),
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
            Text(text.translated())
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
                    Text(period.rawValue.translated())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.5))
                    Spacer()
                    if period == .yearly {
                        Text("Save 26%".translated())
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
                Text(period == .monthly ? "/month".translated() : "\(currentYearlyPerMonth) · \("billed yearly".translated())")
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

    private var isCurrentPlan: Bool {
        (selectedPlan == .standard && subscriptionManager.isStandard && !subscriptionManager.isPro)
            || (selectedPlan == .pro && subscriptionManager.isPro)
    }

    // Pro users can't downgrade to Standard in-app (Apple rule — must go via App Store)
    private var isDowngrade: Bool {
        subscriptionManager.isPro && selectedPlan == .standard
    }

    private var ctaLabel: String {
        if isCurrentPlan  { return "Current Plan".translated() }
        if isDowngrade    { return "Manage in App Store".translated() }
        if subscriptionManager.isStandard && selectedPlan == .pro { return "Upgrade to Pro".translated() }
        return selectedPlan == .pro ? "Get Pro".translated() : "Get Standard".translated()
    }

    private var ctaColor: Color {
        if isCurrentPlan  { return Color.sweeplySuccess }
        if isDowngrade    { return Color.sweeplyNavy.opacity(0.5) }
        return selectedPlan == .pro ? Color.sweeplyAccent : Color.sweeplyNavy
    }

    private var ctaButton: some View {
        Button {
            if isDowngrade {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
                return
            }
            guard !isCurrentPlan else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ctaPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { ctaPressed = false }
            let package = selectedPlan == .pro ? proPackage : standardPackage
            Task { await purchase(package) }
        } label: {
            HStack(spacing: 8) {
                if subscriptionManager.isPurchasing {
                    ProgressView().tint(.white)
                } else if isCurrentPlan {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                        Text(ctaLabel).font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                } else {
                    Text(ctaLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(ctaColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing || (isCurrentPlan && !isDowngrade) || (!isDowngrade && (selectedPlan == .pro ? proPackage : standardPackage) == nil))
        .scaleEffect(ctaPressed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.12), value: ctaPressed)
    }

    // MARK: - Helpers

    private func fetchOfferings() async {
        await subscriptionManager.loadOfferings()
        let current = subscriptionManager.offerings?.current
        let hasPackages = current?.package(identifier: "$rc_monthly") != nil
            || current?.package(identifier: "$rc_annual") != nil
            || current?.package(identifier: "$rc_custom_pro_monthly") != nil
            || current?.package(identifier: "$rc_custom_pro_yearly") != nil
        if hasPackages {
            purchaseError = nil
        } else {
            purchaseError = "Could not load products — check your connection and try again.".translated()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.sweeplyDestructive)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyNavy.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                purchaseError = nil
                Task { await fetchOfferings() }
            } label: {
                if subscriptionManager.isLoadingOfferings {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Text("Retry".translated())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyDestructive)
                }
            }
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
                purchaseError = "Purchase failed — please try again.".translated()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            // Manage subscription link for active subscribers
            if subscriptionManager.isStandard || subscriptionManager.isPro {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Manage Subscription".translated())
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.sweeplyNavy.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                footerLink("Terms of Service".translated()) {
                    if let url = URL(string: "https://sweeplyapp.online/terms") {
                        UIApplication.shared.open(url)
                    }
                }
                footerDot
                footerLink("Privacy Policy".translated()) {
                    if let url = URL(string: "https://sweeplyapp.online/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
                footerDot
                footerLink("Restore Purchases".translated()) {
                    Task {
                        try? await subscriptionManager.restorePurchases()
                        if subscriptionManager.isSubscribed {
                            dismiss()
                        } else {
                            restoreMessage = "No active subscription found.".translated()
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            restoreMessage = nil
                        }
                    }
                }
            }
            if let msg = restoreMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .transition(.opacity)
            }
            Text(currencyFooterText)
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
                Text("Sweeply Pro".translated())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Upgrade to Pro to unlock this feature.".translated())
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
            }

            Button { showPaywall = true } label: {
                Text("See Plans".translated())
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

// MARK: - SubscriptionProView (deprecated — use SubscriptionPaywallView)
// Kept as a thin redirect so any stale call sites still compile.

struct SubscriptionProView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        SubscriptionPaywallView()
            .environment(subscriptionManager)
    }
}

// MARK: - SubscriptionStandardUpgradeView (deprecated — use SubscriptionPaywallView)
// Kept as a thin redirect so any stale call sites still compile.

struct SubscriptionStandardUpgradeView: View {
    @Environment(\.dismiss)                private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager
    var onShowAllPlans: () -> Void = {}

    var body: some View {
        SubscriptionPaywallView()
            .environment(subscriptionManager)
    }
}
