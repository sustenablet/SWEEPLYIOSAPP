import SwiftUI

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                Text("All features are included".translated())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Sweeply no longer uses paywalls or subscription purchases in this build.".translated())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button("Close".translated()) {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.sweeplyAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                Spacer()
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
        }
    }
}

struct ProGateView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}

struct SubscriptionProView: View {
    var body: some View {
        SubscriptionPaywallView()
    }
}

struct SubscriptionStandardUpgradeView: View {
    var onShowAllPlans: () -> Void = {}

    var body: some View {
        SubscriptionPaywallView()
    }
}
