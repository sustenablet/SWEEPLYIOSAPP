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
    let periodStart: Date?
    let periodEnd: Date?
    let notes: String
    let paidAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, notes
        case memberId    = "member_id"
        case ownerId     = "owner_id"
        case periodStart = "period_start"
        case periodEnd   = "period_end"
        case paidAt      = "paid_at"
    }

    func toPayment() -> TeamPayment {
        TeamPayment(id: id, memberId: memberId, ownerId: ownerId,
                    amount: amount, periodStart: periodStart, periodEnd: periodEnd,
                    notes: notes, paidAt: paidAt)
    }
}

private struct TeamPaymentInsert: Encodable {
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let periodStart: Date?
    let periodEnd: Date?
    let notes: String
    let paidAt: Date

    enum CodingKeys: String, CodingKey {
        case amount, notes
        case memberId    = "member_id"
        case ownerId     = "owner_id"
        case periodStart = "period_start"
        case periodEnd   = "period_end"
        case paidAt      = "paid_at"
    }
}