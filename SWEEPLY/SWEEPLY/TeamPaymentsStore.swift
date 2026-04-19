import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class TeamPaymentsStore {
    var payments: [TeamPayment] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        payments = []
        lastError = nil
    }

    // MARK: - Load payments for a member

    func loadPayments(for memberId: UUID) async {
        guard let client = SupabaseManager.shared else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [TeamPaymentDTO] = try await client
                .from("team_member_payments")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .order("paid_at", ascending: false)
                .execute()
                .value
            payments = rows.map { $0.toPayment() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Load all payments for owner's team

    func loadAllPayments(ownerId: UUID) async {
        guard let client = SupabaseManager.shared else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [TeamPaymentDTO] = try await client
                .from("team_member_payments")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .order("paid_at", ascending: false)
                .execute()
                .value
            payments = rows.map { $0.toPayment() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Add payment

    func add(_ payment: TeamPayment) async -> Bool {
        guard let client = SupabaseManager.shared else {
            payments.insert(payment, at: 0)
            return true
        }

        let insert = TeamPaymentInsert(
            memberId: payment.memberId,
            ownerId: payment.ownerId,
            amount: payment.amount,
            periodStart: payment.periodStart,
            periodEnd: payment.periodEnd,
            notes: payment.notes,
            paidAt: payment.paidAt
        )

        do {
            let row: TeamPaymentDTO = try await client
                .from("team_member_payments")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            payments.insert(row.toPayment(), at: 0)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Get total paid for a member

    func totalPaid(for memberId: UUID) -> Double {
        payments
            .filter { $0.memberId == memberId }
            .reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Model

struct TeamPayment: Identifiable {
    var id: UUID = UUID()
    var memberId: UUID
    var ownerId: UUID
    var amount: Double
    var periodStart: Date?
    var periodEnd: Date?
    var notes: String = ""
    var paidAt: Date = Date()
}

// MARK: - DTOs

private struct TeamPaymentDTO: Decodable {
    let id: UUID
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let periodStart: String?
    let periodEnd: String?
    let notes: String
    let paidAt: String

    func toPayment() -> TeamPayment {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return TeamPayment(
            id: id,
            memberId: memberId,
            ownerId: ownerId,
            amount: amount,
            periodStart: periodStart.flatMap { dateFormatter.date(from: $0) },
            periodEnd: periodEnd.flatMap { dateFormatter.date(from: $0) },
            notes: notes,
            paidAt: ISO8601DateFormatter().date(from: paidAt) ?? Date()
        )
    }
}

private struct TeamPaymentInsert: Encodable {
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let periodStart: String?
    let periodEnd: String?
    let notes: String
    let paidAt: String

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case ownerId = "owner_id"
        case amount
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case notes
        case paidAt = "paid_at"
    }

    init(memberId: UUID, ownerId: UUID, amount: Double, periodStart: Date?, periodEnd: Date?, notes: String, paidAt: Date) {
        self.memberId = memberId
        self.ownerId = ownerId
        self.amount = amount
        self.notes = notes
        self.paidAt = ISO8601DateFormatter().string(from: paidAt)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        self.periodStart = periodStart.map { df.string(from: $0) }
        self.periodEnd = periodEnd.map { df.string(from: $0) }
    }
}