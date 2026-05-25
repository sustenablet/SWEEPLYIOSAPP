import Foundation
import Observation
import Supabase

// MARK: - SyncPayload

enum SyncPayload: Codable {
    // MARK: Jobs
    case insertJob(
        id: UUID, userId: UUID, clientId: UUID, clientName: String,
        serviceType: String, scheduledAt: Date, durationHours: Double,
        price: Double, status: String, address: String, isRecurring: Bool,
        assignedMemberId: UUID?, assignedMemberName: String?,
        assignedMemberIds: [UUID], assignedMemberNames: [String]
    )
    case updateJobStatus(id: UUID, status: String)
    case updateJob(
        id: UUID, clientId: UUID, clientName: String,
        serviceType: String, scheduledAt: Date, durationHours: Double,
        price: Double, status: String, address: String, isRecurring: Bool,
        assignedMemberId: UUID?, assignedMemberName: String?,
        assignedMemberIds: [UUID], assignedMemberNames: [String]
    )
    case deleteJob(id: UUID)

    // MARK: Clients
    case insertClient(
        id: UUID, userId: UUID, name: String, email: String, phone: String,
        address: String, city: String, state: String, zip: String,
        preferredService: String?, entryInstructions: String, notes: String,
        avatarTone: String?, isActive: Bool
    )
    case updateClient(
        id: UUID, name: String, email: String, phone: String,
        address: String, city: String, state: String, zip: String,
        preferredService: String?, entryInstructions: String, notes: String,
        avatarTone: String?, isActive: Bool
    )
    case deleteClient(id: UUID)

    // MARK: Invoices
    case insertInvoice(
        id: UUID, userId: UUID, clientId: UUID, clientName: String,
        amount: Double, status: String, dueDate: Date, invoiceNumber: String,
        notes: String?, lineItems: String?
    )
    case updateInvoice(id: UUID, amount: Double, dueDate: Date, notes: String?, lineItems: String?)
    case markInvoicePaid(id: UUID, amount: Double, method: String, paidAt: Date)
    case deleteInvoice(id: UUID)

    // MARK: Expenses
    case insertExpense(id: UUID, userId: UUID, amount: Double, category: String, notes: String, date: Date)
    case deleteExpense(id: UUID)
}

// MARK: - PendingOperation

struct PendingOperation: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var retryCount: Int = 0
    var payload: SyncPayload
}

// MARK: - SyncQueue

@Observable
@MainActor
final class SyncQueue {
    nonisolated(unsafe) static let shared: SyncQueue = MainActor.assumeIsolated {
        SyncQueue()
    }

    private(set) var operations: [PendingOperation] = []
    var pendingCount: Int { operations.count }

    private let maxRetries = 3
    private let udKey = "sweeply.syncQueue"

    private init() { loadFromDisk() }

    // MARK: - Enqueue

    func enqueue(_ payload: SyncPayload) {
        operations.append(PendingOperation(payload: payload))
        saveToDisk()
    }

    // MARK: - Flush

    /// Replay all queued operations against Supabase.
    /// Operations that succeed are removed. Failed ones get a retry count increment
    /// and are dropped silently after `maxRetries` attempts.
    func flush() async {
        guard let client = SupabaseManager.shared else { return }
        var remaining: [PendingOperation] = []

        for var op in operations {
            let success = await execute(op.payload, client: client)
            if !success {
                op.retryCount += 1
                if op.retryCount < maxRetries {
                    remaining.append(op)
                }
                // Drop silently after maxRetries
            }
        }

        operations = remaining
        saveToDisk()
    }

    // MARK: - Execute

    private func execute(_ payload: SyncPayload, client: SupabaseClient) async -> Bool {
        do {
            switch payload {

            // ── Jobs ──────────────────────────────────────────────────────────

            case let .insertJob(id, userId, clientId, clientName, serviceType, scheduledAt,
                                durationHours, price, status, address, isRecurring,
                                assignedMemberId, assignedMemberName, assignedMemberIds, assignedMemberNames):
                struct Row: Encodable {
                    let id, user_id, client_id: UUID
                    let client_name, service_type, status, address: String
                    let scheduled_at: Date
                    let duration_hours, price: Double
                    let is_recurring: Bool
                    let assigned_member_id: UUID?
                    let assigned_member_name: String?
                    let assigned_member_ids: [UUID]
                    let assigned_member_names: [String]
                }
                try await client.from("jobs")
                    .upsert(Row(
                        id: id, user_id: userId, client_id: clientId,
                        client_name: clientName, service_type: serviceType,
                        status: status, address: address, scheduled_at: scheduledAt,
                        duration_hours: durationHours, price: price,
                        is_recurring: isRecurring,
                        assigned_member_id: assignedMemberId,
                        assigned_member_name: assignedMemberName,
                        assigned_member_ids: assignedMemberIds,
                        assigned_member_names: assignedMemberNames
                    ))
                    .execute()

            case let .updateJobStatus(id, status):
                struct Patch: Encodable { let status: String }
                try await client.from("jobs")
                    .update(Patch(status: status))
                    .eq("id", value: id)
                    .execute()

            case let .updateJob(id, clientId, clientName, serviceType, scheduledAt, durationHours,
                                price, status, address, isRecurring,
                                assignedMemberId, assignedMemberName, assignedMemberIds, assignedMemberNames):
                struct Patch: Encodable {
                    let client_id: UUID
                    let client_name, service_type, status, address: String
                    let scheduled_at: Date
                    let duration_hours, price: Double
                    let is_recurring: Bool
                    let assigned_member_id: UUID?
                    let assigned_member_name: String?
                    let assigned_member_ids: [UUID]
                    let assigned_member_names: [String]
                }
                try await client.from("jobs")
                    .update(Patch(
                        client_id: clientId, client_name: clientName,
                        service_type: serviceType, status: status, address: address,
                        scheduled_at: scheduledAt, duration_hours: durationHours,
                        price: price, is_recurring: isRecurring,
                        assigned_member_id: assignedMemberId,
                        assigned_member_name: assignedMemberName,
                        assigned_member_ids: assignedMemberIds,
                        assigned_member_names: assignedMemberNames
                    ))
                    .eq("id", value: id)
                    .execute()

            case let .deleteJob(id):
                try await client.from("jobs").delete().eq("id", value: id).execute()

            // ── Clients ───────────────────────────────────────────────────────

            case let .insertClient(id, userId, name, email, phone, address, city, state, zip,
                                   preferredService, entryInstructions, notes, avatarTone, isActive):
                struct Row: Encodable {
                    let id, user_id: UUID
                    let name, email, phone, address, city, state, zip: String
                    let preferred_service: String?
                    let entry_instructions, notes: String
                    let avatar_tone: String?
                    let is_active: Bool
                }
                try await client.from("clients")
                    .upsert(Row(
                        id: id, user_id: userId,
                        name: name, email: email, phone: phone,
                        address: address, city: city, state: state, zip: zip,
                        preferred_service: preferredService,
                        entry_instructions: entryInstructions, notes: notes,
                        avatar_tone: avatarTone, is_active: isActive
                    ))
                    .execute()

            case let .updateClient(id, name, email, phone, address, city, state, zip,
                                   preferredService, entryInstructions, notes, avatarTone, isActive):
                struct Patch: Encodable {
                    let name, email, phone, address, city, state, zip: String
                    let preferred_service: String?
                    let entry_instructions, notes: String
                    let avatar_tone: String?
                    let is_active: Bool
                }
                try await client.from("clients")
                    .update(Patch(
                        name: name, email: email, phone: phone,
                        address: address, city: city, state: state, zip: zip,
                        preferred_service: preferredService,
                        entry_instructions: entryInstructions, notes: notes,
                        avatar_tone: avatarTone, is_active: isActive
                    ))
                    .eq("id", value: id)
                    .execute()

            case let .deleteClient(id):
                try await client.from("clients").delete().eq("id", value: id).execute()

            // ── Invoices ──────────────────────────────────────────────────────

            case let .insertInvoice(id, userId, clientId, clientName, amount, status, dueDate,
                                    invoiceNumber, notes, lineItems):
                struct Row: Encodable {
                    let id, user_id, client_id: UUID
                    let client_name, status, invoice_number: String
                    let amount: Double
                    let due_date: Date
                    let notes: String?
                    let line_items: String?
                }
                try await client.from("invoices")
                    .upsert(Row(
                        id: id, user_id: userId, client_id: clientId,
                        client_name: clientName, status: status,
                        invoice_number: invoiceNumber, amount: amount,
                        due_date: dueDate, notes: notes, line_items: lineItems
                    ))
                    .execute()

            case let .updateInvoice(id, amount, dueDate, notes, lineItems):
                struct Patch: Encodable {
                    let amount: Double; let due_date: Date
                    let notes: String?; let line_items: String?
                }
                try await client.from("invoices")
                    .update(Patch(amount: amount, due_date: dueDate, notes: notes, line_items: lineItems))
                    .eq("id", value: id)
                    .execute()

            case let .markInvoicePaid(id, amount, method, paidAt):
                struct Patch: Encodable {
                    let status: String
                    let paid_amount: Double
                    let payment_method: String
                    let paid_at: Date
                }
                try await client.from("invoices")
                    .update(Patch(status: "paid", paid_amount: amount, payment_method: method, paid_at: paidAt))
                    .eq("id", value: id)
                    .execute()

            case let .deleteInvoice(id):
                try await client.from("invoices").delete().eq("id", value: id).execute()

            // ── Expenses ──────────────────────────────────────────────────────

            case let .insertExpense(id, userId, amount, category, notes, date):
                struct Row: Encodable {
                    let id, user_id: UUID
                    let amount: Double
                    let category, notes: String
                    let date: Date
                }
                try await client.from("expenses")
                    .upsert(Row(
                        id: id, user_id: userId,
                        amount: amount, category: category, notes: notes, date: date
                    ))
                    .execute()

            case let .deleteExpense(id):
                try await client.from("expenses").delete().eq("id", value: id.uuidString).execute()
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(operations) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let ops = try? JSONDecoder().decode([PendingOperation].self, from: data)
        else { return }
        operations = ops
    }
}
