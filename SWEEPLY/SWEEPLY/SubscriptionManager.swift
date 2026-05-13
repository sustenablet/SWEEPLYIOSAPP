import Foundation
import Observation

// MARK: - Access Level

enum AccessLevel {
    case pro
}

// MARK: - SubscriptionManager

@Observable
final class SubscriptionManager {
    private(set) var isLoading = false
    private var currentUserId: UUID?

    var isPro: Bool { true }
    var isStandard: Bool { false }
    var isInTrial: Bool { false }
    var trialDaysRemaining: Int { 0 }
    var isSubscribed: Bool { true }
    var hasProAccess: Bool { true }
    var accessLevel: AccessLevel { .pro }
    var expirationDate: Date? { nil }
    var activeProductID: String? { nil }

    func setUserId(_ userId: UUID?) {
        currentUserId = userId
    }

    func startLocalTrial(userId: UUID? = nil) {
        currentUserId = userId ?? currentUserId
    }

    static func configure() {}

    @MainActor
    func loadCustomerInfo() async {}

    @MainActor
    func loadOfferings() async {}

    func identify(userId: String) async {}

    func reset() async {}

    func startListening() {}
}
