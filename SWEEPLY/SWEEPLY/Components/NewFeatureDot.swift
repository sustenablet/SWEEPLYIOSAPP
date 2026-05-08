import SwiftUI

/// Small pulsing blue dot shown next to features newly unlocked by a Pro upgrade.
struct NewFeatureDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.22, green: 0.50, blue: 0.92).opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.6 : 1.0)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                    value: pulsing
                )

            Circle()
                .fill(Color(red: 0.22, green: 0.50, blue: 0.92))
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}
