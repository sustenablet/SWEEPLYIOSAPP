import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - SubscriptionPaywallView
//
// Thin SwiftUI wrapper around RevenueCat's managed PaywallView.
// Present this as a .sheet() anywhere in the app.
//
// Usage:
//   .sheet(isPresented: $showPaywall) { SubscriptionPaywallView() }

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss)        private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptionManager

    // Optional: pass a specific Offering from RevenueCat dashboard.
    // Nil = RevenueCat uses the "current" offering (default).
    var offering: Offering? = nil

    var body: some View {
        Group {
            if let offering {
                PaywallView(offering: offering)
            } else {
                PaywallView()
            }
        }
        .onPurchaseCompleted { customerInfo in
            // Sync updated customer info back into our manager
            Task { await subscriptionManager.loadCustomerInfo() }
            dismiss()
        }
        .onRestoreCompleted { customerInfo in
            Task { await subscriptionManager.loadCustomerInfo() }
            dismiss()
        }
    }
}

// MARK: - SubscriptionCustomerCenterView
//
// RevenueCat Customer Center — lets subscribers manage, cancel,
// and request refunds without leaving the app.
//
// Present as a .sheet() from Settings when the user is already subscribed.

struct SubscriptionCustomerCenterView: View {
    var body: some View {
        CustomerCenterView()
    }
}

// MARK: - ProGateView
//
// Drop-in gate that blurs/hides content and shows an upgrade prompt
// when the user is not on the Pro plan.
//
// Usage:
//   ProGateView { MyProFeature() }

struct ProGateView<Content: View>: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false

    @ViewBuilder var content: () -> Content

    var body: some View {
        if subscriptionManager.isPro {
            content()
        } else {
            proPrompt
                .sheet(isPresented: $showPaywall) {
                    SubscriptionPaywallView()
                        .environment(subscriptionManager)
                }
        }
    }

    private var proPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.sweeplyAccent)

            Text("Sweeply Pro".translated())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)

            Text("Upgrade to unlock this feature.".translated())
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .multilineTextAlignment(.center)

            Button {
                showPaywall = true
            } label: {
                Text("See Plans".translated())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sweeplyBackground)
    }
}
