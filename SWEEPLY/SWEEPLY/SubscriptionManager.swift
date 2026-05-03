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
    static let trialDurationDays     = 30
    private static let trialStartKey = "sweeply_trial_start"

    // MARK: State

    private(set) var customerInfo: CustomerInfo?
    private(set) var offerings: Offerings?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var lastError: String?

    // MARK: - Trial

    var trialStartDate: Date {
        if let stored = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: Self.trialStartKey)
        return now
    }

    var trialDaysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        return max(0, Self.trialDurationDays - elapsed)
    }

    var isInTrial: Bool {
        trialDaysRemaining > 0 && !isStandard && !isPro
    }

    // MARK: - Entitlements

    var isPro: Bool {
        customerInfo?.entitlements[Self.proEntitlementID]?.isActive == true
    }

    var isStandard: Bool {
        customerInfo?.entitlements[Self.standardEntitlementID]?.isActive == true
    }

    // Any active access (trial, standard, or pro)
    var isSubscribed: Bool { isStandard || isPro || isInTrial }

    // Pro-level access: subscribed to Pro OR in free trial
    var hasProAccess: Bool { isPro || isInTrial }

    var accessLevel: AccessLevel {
        if isPro        { return .pro }
        if isInTrial    { return .trial(daysRemaining: trialDaysRemaining) }
        if isStandard   { return .standard }
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
