import Foundation
import Observation
import RevenueCat

// MARK: - Access Level

enum AccessLevel {
    case trial(daysRemaining: Int)
    case standard
    case pro
    case expired
}

// MARK: - SubscriptionManager

@Observable
final class SubscriptionManager {

    // MARK: Constants

    static let apiKey                = "appl_hoKbHHnURrLVPDKpGKktXmrSsLJ"
    static let proEntitlementID      = "pro"
    static let standardEntitlementID = "standard"

    // MARK: State

    private(set) var customerInfo: CustomerInfo?
    private(set) var offerings: Offerings?
    private(set) var isLoading = false
    private(set) var isLoadingOfferings = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var lastError: String?

    // MARK: - Entitlements

    var isPro: Bool {
        customerInfo?.entitlements[Self.proEntitlementID]?.isActive == true
    }

    var isStandard: Bool {
        customerInfo?.entitlements[Self.standardEntitlementID]?.isActive == true
    }

    // MARK: - Trial: RevenueCat (purchased introductory offer)

    var isInProTrial: Bool {
        customerInfo?.entitlements[Self.proEntitlementID]?.isActive == true &&
        customerInfo?.entitlements[Self.proEntitlementID]?.periodType == .trial
    }

    var isInStandardTrial: Bool {
        customerInfo?.entitlements[Self.standardEntitlementID]?.isActive == true &&
        customerInfo?.entitlements[Self.standardEntitlementID]?.periodType == .trial
    }

    var isInRevenueCatTrial: Bool { isInProTrial || isInStandardTrial }

    var revenueCatTrialDaysRemaining: Int {
        let entitlement = isInProTrial
            ? customerInfo?.entitlements[Self.proEntitlementID]
            : customerInfo?.entitlements[Self.standardEntitlementID]
        guard let exp = entitlement?.expirationDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0)
    }

    // MARK: - Trial: Local (users who tapped "I'll decide later")

    private static let localTrialStartKey     = "sweeply_trial_start"
    private static let localTrialDurationDays = 30
    private var currentUserId: UUID?

    func setUserId(_ userId: UUID?) {
        self.currentUserId = userId
    }

    private var perUserTrialKey: String {
        guard let uid = currentUserId else { return Self.localTrialStartKey }
        return "\(Self.localTrialStartKey)_\(uid.uuidString)"
    }

    var isInLocalTrial: Bool {
        guard !isStandard, !isPro else { return false }
        guard let start = UserDefaults.standard.object(forKey: perUserTrialKey) as? Date else { return false }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return elapsed < Self.localTrialDurationDays
    }

    var localTrialDaysRemaining: Int {
        guard let start = UserDefaults.standard.object(forKey: perUserTrialKey) as? Date else { return 0 }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.localTrialDurationDays - elapsed)
    }

    func startLocalTrial(userId: UUID? = nil) {
        let uid = userId ?? currentUserId
        let key = uid != nil ? "\(Self.localTrialStartKey)_\(uid!.uuidString)" : Self.localTrialStartKey
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // MARK: - Combined

    var isInTrial: Bool { isInRevenueCatTrial || isInLocalTrial }

    var trialDaysRemaining: Int {
        isInRevenueCatTrial ? revenueCatTrialDaysRemaining : localTrialDaysRemaining
    }

    // Any active access
    var isSubscribed: Bool { isStandard || isPro || isInLocalTrial }

    // Pro-level access: active Pro entitlement (includes Pro trial via RevenueCat)
    var hasProAccess: Bool { isPro }

    var accessLevel: AccessLevel {
        if isPro && isInProTrial           { return .trial(daysRemaining: revenueCatTrialDaysRemaining) }
        if isPro                           { return .pro }
        if isStandard && isInStandardTrial { return .trial(daysRemaining: revenueCatTrialDaysRemaining) }
        if isStandard                      { return .standard }
        if isInLocalTrial                  { return .trial(daysRemaining: localTrialDaysRemaining) }
        return .expired
    }

    var expirationDate: Date? {
        customerInfo?.entitlements[Self.proEntitlementID]?.expirationDate
            ?? customerInfo?.entitlements[Self.standardEntitlementID]?.expirationDate
    }

    var activeProductID: String? {
        customerInfo?.entitlements[Self.proEntitlementID]?.productIdentifier
            ?? customerInfo?.entitlements[Self.standardEntitlementID]?.productIdentifier
    }

    // MARK: - Configuration

    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: apiKey)
    }

    // MARK: - Load

    @MainActor
    func loadCustomerInfo() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func loadOfferings() async {
        guard !isLoadingOfferings else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    @MainActor
    @discardableResult
    func purchase(package: Package) async throws -> CustomerInfo {
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        let result = try await Purchases.shared.purchase(package: package)
        customerInfo = result.customerInfo
        return result.customerInfo
    }

    // MARK: - Restore

    @MainActor
    @discardableResult
    func restorePurchases() async throws -> CustomerInfo {
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        return info
    }

    // MARK: - Identity

    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run { customerInfo = info }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    func reset() async {
        do {
            let info = try await Purchases.shared.logOut()
            await MainActor.run { customerInfo = info }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    // MARK: - Real-time listener

    func startListening() {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await MainActor.run { self?.customerInfo = info }
            }
        }
    }
}
