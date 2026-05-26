import SwiftUI
import RevenueCat

// MARK: - SubscriptionPaywallView

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss)          private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    // Billing cycle toggle
    @State private var isAnnual     = true
    // Which plan card is highlighted
    @State private var selectedPlan: PlanTier = .pro
    // Loading / error
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    enum PlanTier { case standard, pro }

    // MARK: - Helpers

    private var standardPackage: Package? {
        isAnnual ? subscriptionManager.standardAnnualPackage
                 : subscriptionManager.standardMonthlyPackage
    }
    private var proPackage: Package? {
        isAnnual ? subscriptionManager.proAnnualPackage
                 : subscriptionManager.proMonthlyPackage
    }

    private func priceLabel(for package: Package?) -> String {
        guard let pkg = package else { return "—" }
        if isAnnual {
            // Show per-month equivalent for annual plans
            let annual = pkg.storeProduct.price
            let perMonth = (annual / 12) as NSDecimalNumber
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.locale = pkg.storeProduct.priceLocale
            return fmt.string(from: perMonth) ?? pkg.storeProduct.localizedPriceString
        }
        return pkg.storeProduct.localizedPriceString
    }

    private func annualTotal(for package: Package?) -> String? {
        guard isAnnual, let pkg = package else { return nil }
        return pkg.storeProduct.localizedPriceString
    }

    private var activePackage: Package? {
        selectedPlan == .pro ? proPackage : standardPackage
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.sweeplyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    billingToggle
                        .padding(.top, 24)
                    planCards
                        .padding(.top, 20)
                    featureTable
                        .padding(.top, 24)
                    ctaSection
                        .padding(.top, 28)
                    footer
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
            }

            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 32, height: 32)
                    .background(Color.sweeplySurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.sweeplyBorder, lineWidth: 1))
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .onChange(of: subscriptionManager.isSubscribed) { _, isSubscribed in
            if isSubscribed { dismiss() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.sweeplyAccent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
            }

            Text("Try free for 30 days")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sweeplyNavy)
                .multilineTextAlignment(.center)

            Text("Then keep what works for your business.\nCancel anytime.")
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingTab(label: "Monthly", isSelected: !isAnnual) { isAnnual = false }
            billingTab(label: "Annual", badge: "Save ~17%", isSelected: isAnnual) { isAnnual = true }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func billingTab(label: String, badge: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.sweeplyAccent)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(isSelected ? Color.sweeplyBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        HStack(spacing: 12) {
            planCard(.standard)
            planCard(.pro)
        }
    }

    private func planCard(_ tier: PlanTier) -> some View {
        let isSelected = selectedPlan == tier
        let isPro = tier == .pro
        let price = isPro ? priceLabel(for: proPackage) : priceLabel(for: standardPackage)
        let total = isPro ? annualTotal(for: proPackage) : annualTotal(for: standardPackage)

        return Button { withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = tier } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(isPro ? "Pro" : "Standard")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isPro ? Color.sweeplyAccent : Color.sweeplyNavy)
                    Spacer()
                    if isPro {
                        Text("Popular")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.sweeplyAccent)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("/mo")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    if let total {
                        Text("billed \(total)/yr")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? (isPro ? Color.sweeplyAccent : Color.sweeplyNavy) : Color.sweeplyBorder)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? (isPro ? Color.sweeplyAccent : Color.sweeplyNavy) : Color.sweeplyBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Table

    private struct FeatureRow {
        let name: String
        let standard: Bool
        let pro: Bool
    }

    private let features: [FeatureRow] = [
        .init(name: "Jobs & Schedule",     standard: true,  pro: true),
        .init(name: "Clients",             standard: true,  pro: true),
        .init(name: "Invoices",            standard: true,  pro: true),
        .init(name: "Expenses",            standard: true,  pro: true),
        .init(name: "Team (up to 2)",      standard: true,  pro: false),
        .init(name: "Team (unlimited)",    standard: false, pro: true),
        .init(name: "Financial Reports",   standard: false, pro: true),
    ]

    private var featureTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Features")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Standard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(width: 70, alignment: .center)
                Text("Pro")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                    .frame(width: 50, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: CGRect(x: 0, y: 0, width: 400, height: 100)))

            // Feature rows
            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { idx, feature in
                    featureRowView(feature, isLast: idx == features.count - 1)
                }
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

    private func featureRowView(_ row: FeatureRow, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(row.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                checkmark(row.standard)
                    .frame(width: 70, alignment: .center)
                checkmark(row.pro)
                    .frame(width: 50, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast {
                Divider()
                    .padding(.leading, 14)
            }
        }
    }

    @ViewBuilder
    private func checkmark(_ value: Bool) -> some View {
        if value {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyAccent)
        } else {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sweeplyBorder)
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            // Primary — Start Free Trial with selected plan
            Button {
                Task { await startTrial() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Text(ctaLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sweeplyNavy)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || activePackage == nil)
            .opacity((isPurchasing || activePackage == nil) ? 0.6 : 1)

            // Secondary — switch to other plan
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedPlan = selectedPlan == .pro ? .standard : .pro
                }
            } label: {
                Text(secondaryCTALabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private var ctaLabel: String {
        "Start Free Trial — \(selectedPlan == .pro ? "Pro" : "Standard")"
    }

    private var secondaryCTALabel: String {
        selectedPlan == .pro
            ? "Or choose Standard instead"
            : "Or upgrade to Pro instead"
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Text("30-day free trial, no charge today.\nCancel anytime before the trial ends.")
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await restore() }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)

                Text("·").foregroundStyle(Color.sweeplyBorder)

                Link("Terms", destination: URL(string: "https://sweeply.app/terms")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)

                Text("·").foregroundStyle(Color.sweeplyBorder)

                Link("Privacy", destination: URL(string: "https://sweeply.app/privacy")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
    }

    // MARK: - Actions

    private func startTrial() async {
        guard let pkg = activePackage else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        let success = await subscriptionManager.purchase(package: pkg)
        if !success, let err = subscriptionManager.purchaseError {
            errorMessage = err
        }
    }

    private func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        let restored = await subscriptionManager.restorePurchases()
        if !restored {
            errorMessage = "No active subscription found. If you believe this is an error, contact support."
        }
    }
}

// MARK: - ProGateView

struct ProGateView<Content: View>: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if subscriptionManager.isPro {
            content()
        } else {
            proLockPlaceholder
                .sheet(isPresented: $showPaywall) {
                    SubscriptionPaywallView()
                        .environment(subscriptionManager)
                }
        }
    }

    private var proLockPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Pro feature")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text("Upgrade to Pro to unlock this feature.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)
            Button("Upgrade to Pro") { showPaywall = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.sweeplyNavy)
                .clipShape(Capsule())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Aliases (keep existing call sites working)

struct SubscriptionProView: View {
    var body: some View { SubscriptionPaywallView() }
}

struct SubscriptionStandardUpgradeView: View {
    var onShowAllPlans: () -> Void = {}
    var body: some View { SubscriptionPaywallView() }
}
