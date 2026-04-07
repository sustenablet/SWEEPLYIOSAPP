import EventKit
import Foundation

/// Manages syncing Sweeply jobs to the iOS Calendar app.
/// Enabled via Settings → "Sync jobs to iOS Calendar".
final class CalendarSyncManager {
    static let shared = CalendarSyncManager()
    private init() {}

    private let store = EKEventStore()
    private let mapKey = "ekEventMap"

    // MARK: - Access

    func requestAccessIfNeeded() async -> Bool {
        if #available(iOS 17, *) {
            do {
                return try await store.requestWriteOnlyAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "calendarSyncEnabled")
    }

    // MARK: - Mutations

    func addEvent(for job: Job) async {
        guard isEnabled else { return }
        guard await requestAccessIfNeeded() else { return }
        let event = EKEvent(eventStore: store)
        configure(event, with: job)
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent, commit: true)
            saveMapping(jobId: job.id, eventId: event.eventIdentifier)
        } catch {
            // Calendar write failed silently — non-critical
        }
    }

    func updateEvent(for job: Job) async {
        guard isEnabled else { return }
        guard await requestAccessIfNeeded() else { return }
        if let eventId = loadMapping()[job.id.uuidString],
           let event = store.event(withIdentifier: eventId) {
            configure(event, with: job)
            do { try store.save(event, span: .thisEvent, commit: true) } catch {}
        } else {
            await addEvent(for: job)
        }
    }

    func removeEvent(for jobId: UUID) async {
        guard isEnabled else { return }
        guard await requestAccessIfNeeded() else { return }
        if let eventId = loadMapping()[jobId.uuidString],
           let event = store.event(withIdentifier: eventId) {
            do { try store.remove(event, span: .thisEvent, commit: true) } catch {}
        }
        removeMapping(jobId: jobId)
    }

    // MARK: - Helpers

    private func configure(_ event: EKEvent, with job: Job) {
        event.title = "\(job.serviceType.rawValue) — \(job.clientName)"
        event.location = job.address.isEmpty ? nil : job.address
        event.startDate = job.date
        event.endDate = job.date.addingTimeInterval(job.duration * 3600)
        event.notes = "Sweeply job"
    }

    // MARK: - Mapping persistence

    private func loadMapping() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: mapKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private func saveMapping(jobId: UUID, eventId: String) {
        var map = loadMapping()
        map[jobId.uuidString] = eventId
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: mapKey)
        }
    }

    private func removeMapping(jobId: UUID) {
        var map = loadMapping()
        map.removeValue(forKey: jobId.uuidString)
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: mapKey)
        }
    }
}
