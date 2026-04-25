import Foundation
import Observation
import Supabase
import EventKit
import StoreKit
import UIKit

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
            jobs = []
            lastError = "Unable to connect. Please try again."
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
                .select("*, recurrence_rules(frequency)")
                .order("scheduled_at", ascending: false)
                .execute()
                .value
            jobs = rows.map { $0.toJob() }
            SpotlightIndexer.shared.indexJobs(jobs)
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
                isRecurring: job.isRecurring,
                recurrence_rule_id: job.recurrenceRuleId,
                assignedMemberId: job.assignedMemberId,
                assignedMemberName: job.assignedMemberName
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
            NotificationManager.shared.scheduleJobReminder(for: mapped)
            NotificationManager.shared.refreshDailyDigests(jobs: jobs)
            Task.detached { await CalendarSyncManager.shared.addEvent(for: mapped) }
            SpotlightIndexer.shared.indexJobs([mapped])
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
                isRecurring: job.isRecurring,
                recurrence_rule_id: job.recurrenceRuleId,
                assignedMemberId: job.assignedMemberId,
                assignedMemberName: job.assignedMemberName
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
            NotificationManager.shared.cancelJobReminders(for: mapped.id)
            NotificationManager.shared.scheduleJobReminder(for: mapped)
            NotificationManager.shared.refreshDailyDigests(jobs: jobs)
            Task.detached { await CalendarSyncManager.shared.updateEvent(for: mapped) }
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
            if status == .completed { requestReviewIfAppropriate() }
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
            if status == .completed || status == .cancelled {
                NotificationManager.shared.cancelJobReminders(for: id)
            }
            NotificationManager.shared.refreshDailyDigests(jobs: jobs)
            if status == .completed { requestReviewIfAppropriate() }
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
            NotificationManager.shared.cancelJobReminders(for: id)
            try await client
                .from("jobs")
                .delete()
                .eq("id", value: id)
                .execute()
            jobs.removeAll { $0.id == id }
            NotificationManager.shared.refreshDailyDigests(jobs: jobs)
            Task.detached { await CalendarSyncManager.shared.removeEvent(for: id) }
            SpotlightIndexer.shared.removeJob(id: id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func fetchHealthStats(userId: UUID) async -> HealthStats? {
        guard let client = SupabaseManager.shared else { return nil }
        do {
            let res: HealthStats = try await client
                .rpc("get_business_health_stats", params: ["user_id_param": userId])
                .execute()
                .value
            return res
        } catch {
            print("Error fetching health stats: \(error)")
            return nil
        }
    }

    func insertRecurring(rule: RecurrenceRule, clientName: String, address: String) async -> Bool {
        guard let client = SupabaseManager.shared else { return false }
        lastError = nil
        do {
            // 1. Insert the Rule
            let ruleRow = RecurrenceRuleRowInsert(
                user_id: rule.userId,
                client_id: rule.clientId,
                service_type: rule.serviceType.rawValue,
                frequency: rule.frequency.rawValue,
                interval_days: rule.intervalDays,
                start_date: rule.startDate,
                end_date: rule.endDate,
                price: rule.price,
                duration_hours: rule.durationHours
            )
            
            let insertedRule: RecurrenceRuleRow = try await client
                .from("recurrence_rules")
                .insert(ruleRow)
                .select()
                .single()
                .execute()
                .value
            
            // 2. Generate first 8 instances
            let dates = generateRecurringDates(
                start: rule.startDate,
                frequency: rule.frequency,
                interval: rule.intervalDays,
                endDate: rule.endDate,
                count: 8
            )
            
            let jobRows = dates.map { date in
                JobRowInsert(
                    userId: rule.userId,
                    clientId: rule.clientId,
                    clientName: clientName,
                    serviceType: rule.serviceType.rawValue,
                    scheduledAt: date,
                    durationHours: rule.durationHours,
                    price: rule.price,
                    status: JobStatus.scheduled.rawValue,
                    address: address,
                    isRecurring: true,
                    recurrence_rule_id: insertedRule.id,
                    assignedMemberId: nil,
                    assignedMemberName: nil
                )
            }
            
            try await client
                .from("jobs")
                .insert(jobRows)
                .execute()
            
            await load(isAuthenticated: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func requestReviewIfAppropriate() {
        let completedCount = jobs.filter { $0.status == .completed }.count
        let milestones = [5, 15, 50]
        guard milestones.contains(completedCount) else { return }

        let lastCount = UserDefaults.standard.integer(forKey: "lastReviewPromptCount")
        guard lastCount != completedCount else { return }

        UserDefaults.standard.set(completedCount, forKey: "lastReviewPromptCount")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private func generateRecurringDates(start: Date, frequency: RecurrenceFrequency, interval: Int, endDate: Date?, count: Int) -> [Date] {
        var dates: [Date] = [start]
        let calendar = Calendar.current
        let limit = endDate ?? calendar.date(byAdding: .day, value: 365, to: start) ?? start
        
        for i in 1..<count {
            let nextDate: Date?
            switch frequency {
            case .once: return [start]
            case .weekly:   nextDate = calendar.date(byAdding: .weekOfYear, value: i, to: start)
            case .biweekly: nextDate = calendar.date(byAdding: .weekOfYear, value: i * 2, to: start)
            case .monthly:  nextDate = calendar.date(byAdding: .month, value: i, to: start)
            case .custom:   nextDate = calendar.date(byAdding: .day, value: i * interval, to: start)
            }
            
            if let d = nextDate, d <= limit {
                dates.append(d)
            } else {
                break
            }
        }
        return dates
    }
}

// MARK: - Models

struct HealthStats: Decodable {
    let revenue: Double
    let revenue_trend: String
    let job_count: Int
    let job_trend: String
    let is_rev_positive: Bool
    let is_job_positive: Bool
}

// MARK: - DTOs

private struct RecurrenceRuleEmbed: Decodable {
    let frequency: String
}

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
    let recurrence_rule_id: UUID?
    let recurrence_rules: RecurrenceRuleEmbed?
    let assignedMemberId: UUID?
    let assignedMemberName: String?

    enum CodingKeys: String, CodingKey {
        case id, address, price, status
        case userId            = "user_id"
        case clientId          = "client_id"
        case clientName        = "client_name"
        case serviceType       = "service_type"
        case scheduledAt       = "scheduled_at"
        case durationHours     = "duration_hours"
        case isRecurring       = "is_recurring"
        case recurrence_rule_id
        case recurrence_rules
        case assignedMemberId  = "assigned_member_id"
        case assignedMemberName = "assigned_member_name"
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
            isRecurring: isRecurring,
            recurrenceRuleId: recurrence_rule_id,
            recurrenceFrequency: recurrence_rules.flatMap { RecurrenceFrequency(rawValue: $0.frequency) },
            assignedMemberId: assignedMemberId,
            assignedMemberName: assignedMemberName
        )
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
    let recurrence_rule_id: UUID?
    let assignedMemberId: UUID?
    let assignedMemberName: String?

    enum CodingKeys: String, CodingKey {
        case address, price, status
        case clientId           = "client_id"
        case clientName         = "client_name"
        case serviceType        = "service_type"
        case scheduledAt        = "scheduled_at"
        case durationHours      = "duration_hours"
        case isRecurring        = "is_recurring"
        case recurrence_rule_id
        case assignedMemberId   = "assigned_member_id"
        case assignedMemberName = "assigned_member_name"
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
    let recurrence_rule_id: UUID?
    let assignedMemberId: UUID?
    let assignedMemberName: String?

    enum CodingKeys: String, CodingKey {
        case address, price, status
        case userId             = "user_id"
        case clientId           = "client_id"
        case clientName         = "client_name"
        case serviceType        = "service_type"
        case scheduledAt        = "scheduled_at"
        case durationHours      = "duration_hours"
        case isRecurring        = "is_recurring"
        case recurrence_rule_id
        case assignedMemberId   = "assigned_member_id"
        case assignedMemberName = "assigned_member_name"
    }
}

private struct JobStatusPatch: Encodable {
    let status: String
}

private struct RecurrenceRuleRow: Decodable {
    let id: UUID
}

private struct RecurrenceRuleRowInsert: Encodable {
    let user_id: UUID
    let client_id: UUID
    let service_type: String
    let frequency: String
    let interval_days: Int
    let start_date: Date
    let end_date: Date?
    let price: Double
    let duration_hours: Double
}
