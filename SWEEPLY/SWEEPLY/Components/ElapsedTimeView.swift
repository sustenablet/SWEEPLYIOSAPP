import SwiftUI
import Combine

struct ElapsedTimeView: View {
    let startedAt: Date

    @State private var elapsed: TimeInterval = 0
    @State private var pulsing = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.4, green: 0.45, blue: 0.95))
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.3 : 0.8)
                .opacity(pulsing ? 1.0 : 0.5)

            Text(formatElapsed(elapsed))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.4, green: 0.45, blue: 0.95))
        }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(startedAt)
        }
        .onAppear {
            elapsed = Date().timeIntervalSince(startedAt)
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        } else {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }
}
