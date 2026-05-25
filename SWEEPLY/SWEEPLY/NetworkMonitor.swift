import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private nonisolated let monitor = NWPathMonitor()
    private nonisolated let queue   = DispatchQueue(label: "com.sweeply.network", qos: .utility)

    var isConnected: Bool = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
