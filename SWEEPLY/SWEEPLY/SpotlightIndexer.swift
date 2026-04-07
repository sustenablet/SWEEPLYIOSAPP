import CoreSpotlight
import Foundation

/// Indexes clients and jobs in Spotlight so users can search for them from the home screen.
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    private init() {}

    private let clientDomain = "com.sweeply.client"
    private let jobDomain    = "com.sweeply.job"

    // MARK: - Clients

    func indexClients(_ clients: [Client]) {
        let items = clients.map { spotlightItem(for: $0) }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    func removeClient(id: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ["\(clientDomain).\(id.uuidString)"])  { _ in }
    }

    private func spotlightItem(for client: Client) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = client.name
        var parts: [String] = []
        if !client.phone.isEmpty    { parts.append(client.phone) }
        if !client.address.isEmpty  { parts.append(client.address) }
        if !client.city.isEmpty     { parts.append(client.city) }
        attrs.contentDescription = parts.joined(separator: " · ")
        attrs.keywords = ["client", "cleaning", client.name]
        return CSSearchableItem(
            uniqueIdentifier: "\(clientDomain).\(client.id.uuidString)",
            domainIdentifier: clientDomain,
            attributeSet: attrs
        )
    }

    // MARK: - Jobs

    func indexJobs(_ jobs: [Job]) {
        let f = DateFormatter()
        f.dateFormat = "MMM d 'at' h:mm a"
        let items = jobs.map { job -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = "\(job.serviceType.rawValue) — \(job.clientName)"
            attrs.contentDescription = "\(f.string(from: job.date)), \(job.address)"
            attrs.keywords = ["job", "cleaning", job.clientName, job.serviceType.rawValue]
            return CSSearchableItem(
                uniqueIdentifier: "\(jobDomain).\(job.id.uuidString)",
                domainIdentifier: jobDomain,
                attributeSet: attrs
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    func removeJob(id: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ["\(jobDomain).\(id.uuidString)"]) { _ in }
    }

    // MARK: - Parsing deep link from Spotlight tap

    /// Returns a deep link string like "client:<uuid>" or "job:<uuid>" from a Spotlight activity.
    static func deepLink(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        if id.hasPrefix("com.sweeply.client.") {
            return "client:" + id.replacingOccurrences(of: "com.sweeply.client.", with: "")
        }
        if id.hasPrefix("com.sweeply.job.") {
            return "job:" + id.replacingOccurrences(of: "com.sweeply.job.", with: "")
        }
        return nil
    }
}
