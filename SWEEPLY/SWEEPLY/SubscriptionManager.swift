import Foundation
import Observation
import RevenueCat

// MARK: - SubscriptionManager

@Observable
final class SubscriptionManager {

    // MARK: Constants

    static let apiKey          = "test_DHssIPjCgrwchzppmUiQjfJooNy"
    static let entitlementID   = "sweeply Pro"

    // MARK: Published state

    private(set) var customerInfo: CustomerInfo?
    private(set) var offerings: Offerings?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var lastError: String?

    // MARK: Derived

    var isPro: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    var activeProductID: String? {
        customerInfo?.entitlements[Self.entitlementID]?.productIdentifier
    }

    var isLifetime: Bool { activeProductID == "lifetime" }

    var expirationDate: Date? {
        customerInfo?.entitlements[Self.entitlementID]?.expirationDate
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

    // MARK: - Identify user (call after Supabase sign-in)

    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run { customerInfo = info }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    // MARK: - Sign out (call after Supabase sign-out)

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
