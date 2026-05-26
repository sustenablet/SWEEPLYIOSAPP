import Foundation
import Observation
import RevenueCat

// MARK: - Access Level

enum AccessLevel {
    case standard
    case pro
}

// MARK: - SubscriptionManager

@Observable
@MainActor
final class SubscriptionManager: NSObject {

    // MARK: - Published state

    private(set) var isLoading        = false
    private(set) var currentOffering: Offering?
    private(set) var purchaseError:   String?

    // Backing stores updated from CustomerInfo
    private var _isPro               = false
    private var _isStandard          = false
    private var _isInTrial           = false
    private var _trialDaysRemaining  = 0
    private var _isSubscribed        = false
    private var _expirationDate:     Date?    = nil
    private var _activeProductID:    String?  = nil

    // MARK: - Computed properties (match original public surface)

    var isPro: Bool                 { _isPro }
    var isStandard: Bool            { _isStandard }
    var isSubscribed: Bool          { _isSubscribed }
    var isInTrial: Bool             { _isInTrial }
    var trialDaysRemaining: Int     { _trialDaysRemaining }
    var hasProAccess: Bool          { _isPro }
    var accessLevel: AccessLevel    { _isPro ? .pro : .standard }
    var expirationDate: Date?       { _expirationDate }
    var activeProductID: String?    { _activeProductID }

    // Convenience package accessors (nil if offering not yet loaded)
    var standardMonthlyPackage: Package? { currentOffering?.monthly }
    var standardAnnualPackage:  Package? { currentOffering?.annual }
    var proMonthlyPackage:      Package? { currentOffering?.availablePackages.first { $0.identifier == "$rc_custom_pro_monthly" } }
    var proAnnualPackage:       Package? { currentOffering?.availablePackages.first { $0.identifier == "$rc_custom_pro_yearly" } }

    // MARK: - Private

    private var currentUserId: UUID?

    // MARK: - API Key

    private static let apiKey: String? = {
        guard
            let url  = Bundle.main.url(forResource: "RevenueCatConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            let key  = dict["REVENUECAT_API_KEY"],
            !key.isEmpty
        else {
            #if DEBUG
            print("[SubscriptionManager] RevenueCatConfig.plist missing or empty — subscription features disabled")
            #endif
            return nil
        }
        return key
    }()

    private var isConfigured: Bool { Self.apiKey != nil }

    // MARK: - Init

    override init() {
        super.init()
    }

    // MARK: - Configure (call once before any views appear)

    func configure() {
        guard let key = Self.apiKey else { return }
        Purchases.logLevel = .error
        let config = Configuration.Builder(withAPIKey: key).build()
        Purchases.configure(with: config)
        Purchases.shared.delegate = self
    }

    // MARK: - Load

    @MainActor
    func loadCustomerInfo() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(customerInfo: info)
        } catch {
            #if DEBUG
            print("[SubscriptionManager] loadCustomerInfo: \(error.localizedDescription)")
            #endif
        }
    }

    @MainActor
    func loadOfferings() async {
        guard isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            #if DEBUG
            print("[SubscriptionManager] loadOfferings: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Identity

    func setUserId(_ userId: UUID?) {
        currentUserId = userId
    }

    func identify(userId: String) async {
        guard isConfigured else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run { apply(customerInfo: info) }
        } catch {
            #if DEBUG
            print("[SubscriptionManager] identify: \(error.localizedDescription)")
            #endif
        }
    }

    func reset() async {
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.logOut()
            await MainActor.run { apply(customerInfo: info) }
        } catch {
            #if DEBUG
            print("[SubscriptionManager] reset: \(error.localizedDescription)")
            #endif
        }
    }

    func startListening() {
        // Delegate is set in configure(); real-time updates handled via PurchasesDelegate
    }

    func startLocalTrial(userId: UUID? = nil) {
        currentUserId = userId ?? currentUserId
    }

    // MARK: - Purchase

    @MainActor
    func purchase(package: Package) async -> Bool {
        guard isConfigured else { return false }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                apply(customerInfo: result.customerInfo)
                return true
            }
            return false
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    @MainActor
    func restorePurchases() async -> Bool {
        guard isConfigured else { return false }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            return !info.entitlements.active.isEmpty
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    // MARK: - Parse CustomerInfo

    private func apply(customerInfo: CustomerInfo) {
        let proEntry      = customerInfo.entitlements["pro"]
        let standardEntry = customerInfo.entitlements["standard"]

        _isPro       = proEntry?.isActive == true
        _isStandard  = _isPro || (standardEntry?.isActive == true)
        _isSubscribed = _isStandard || _isPro

        // Active entitlement for trial/expiry info (prefer pro)
        let active   = (_isPro ? proEntry : standardEntry)
        _isInTrial   = active?.periodType == .trial
        _expirationDate  = active?.expirationDate
        _activeProductID = active?.productIdentifier

        if _isInTrial, let exp = _expirationDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
            _trialDaysRemaining = max(0, days)
        } else {
            _trialDaysRemaining = 0
        }
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.apply(customerInfo: customerInfo)
        }
    }
}
