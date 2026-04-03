import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class JobsStore {
    var jobs: [Job] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        jobs = []
        lastError = nil
    }

    func load(isAuthenticated: Bool) async {
        guard let client = SupabaseManager.shared else {
            jobs = MockData.makeJobs()
            return
        }
        guard isAuthenticated else {
            jobs = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [JobRow] = try await client
                .from("jobs")
                .select()
                .order("scheduled_at", ascending: false)
                .execute()
                .value
            jobs = rows.map { $0.toJob() }
        } catch {
            lastError = error.localizedDescription
            jobs = []
        }
    }

    func insert(_ job: Job, userId: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            jobs.append(job)
            jobs.sort { $0.date > $1.date }
            return true
        }
        lastError = nil
        do {
            let row = JobRowInsert(
                userId: userId,
                clientId: job.clientId,
                clientName: job.clientName,
                serviceType: job.serviceType.rawValue,
                scheduledAt: job.date,
                durationHours: job.duration,
                price: job.price,
                status: job.status.rawValue,
                address: job.address,
                isRecurring: job.isRecurring
            )
            let inserted: JobRow = try await client
                .from("jobs")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            let mapped = inserted.toJob()
            jobs.append(mapped)
            jobs.sort { $0.date > $1.date }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func update(_ job: Job) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[idx] = job
            }
            return true
        }
        lastError = nil
        do {
            let patch = JobRowPatch(
                clientId: job.clientId,
                clientName: job.clientName,
                serviceType: job.serviceType.rawValue,
                scheduledAt: job.date,
                durationHours: job.duration,
                price: job.price,
                status: job.status.rawValue,
                address: job.address,
                isRecurring: job.isRecurring
            )
            let refreshed: JobRow = try await client
                .from("jobs")
                .update(patch)
                .eq("id", value: job.id)
                .select()
                .single()
                .execute()
                .value
            let mapped = refreshed.toJob()
            if let idx = jobs.firstIndex(where: { $0.id == mapped.id }) {
                jobs[idx] = mapped
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateStatus(id: UUID, status: JobStatus) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = jobs.firstIndex(where: { $0.id == id }) {
                jobs[idx].status = status
            }
            return true
        }
        lastError = nil
        do {
            let patch = JobStatusPatch(status: status.rawValue)
            let refreshed: JobRow = try await client
                .from("jobs")
                .update(patch)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            let mapped = refreshed.toJob()
            if let idx = jobs.firstIndex(where: { $0.id == mapped.id }) {
                jobs[idx] = mapped
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            jobs.removeAll { $0.id == id }
            return true
        }
        lastError = nil
        do {
            try await client
                .from("jobs")
                .delete()
                .eq("id", value: id)
                .execute()
            jobs.removeAll { $0.id == id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

// MARK: - DTOs

private struct JobRow: Decodable {
    let id: UUID
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let serviceType: String
    let scheduledAt: Date
    let durationHours: Double
    let price: Double
    let status: String
    let address: String
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case id, address, price, status
        case userId       = "user_id"
        case clientId     = "client_id"
        case clientName   = "client_name"
        case serviceType  = "service_type"
        case scheduledAt  = "scheduled_at"
        case durationHours = "duration_hours"
        case isRecurring  = "is_recurring"
    }

    func toJob() -> Job {
        Job(
            id: id,
            clientId: clientId,
            clientName: clientName,
            serviceType: ServiceType(rawValue: serviceType) ?? .standard,
            date: scheduledAt,
            duration: durationHours,
            price: price,
            status: JobStatus(rawValue: status) ?? .scheduled,
            address: address,
            isRecurring: isRecurring
        )
    }
}

private struct JobRowInsert: Encodable {
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let serviceType: String
    let scheduledAt: Date
    let durationHours: Double
    let price: Double
    let status: String
    let address: String
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case address, price, status
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case serviceType   = "service_type"
        case scheduledAt   = "scheduled_at"
        case durationHours = "duration_hours"
        case isRecurring   = "is_recurring"
    }
}

private struct JobRowPatch: Encodable {
    let clientId: UUID
    let clientName: String
    let serviceType: String
    let scheduledAt: Date
    let durationHours: Double
    let price: Double
    let status: String
    let address: String
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case address, price, status
        case clientId      = "client_id"
        case clientName    = "client_name"
        case serviceType   = "service_type"
        case scheduledAt   = "scheduled_at"
        case durationHours = "duration_hours"
        case isRecurring   = "is_recurring"
    }
}

private struct JobStatusPatch: Encodable {
    let status: String
}
