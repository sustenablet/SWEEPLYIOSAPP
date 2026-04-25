import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class TeamStore {
    var members: [TeamMember] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        members = []
        lastError = nil
    }

    func load(ownerId: UUID) async {
        guard let client = SupabaseManager.shared else {
            // Offline mode: keep whatever is in memory
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [TeamMemberDTO] = try await client
                .from("team_members")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .order("added_at", ascending: true)
                .execute()
                .value
            members = rows.map { $0.toMember() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func add(_ member: TeamMember) async -> Bool {
        guard let client = SupabaseManager.shared else {
            members.append(member)
            return true
        }

        let insert = TeamMemberInsert(
            ownerId: member.ownerId,
            name: member.name,
            email: member.email,
            phone: member.phone,
            role: member.role.rawValue,
            status: member.status.rawValue,
            addedAt: member.addedAt
        )

        do {
            let row: TeamMemberDTO = try await client
                .from("team_members")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            members.append(row.toMember())
            // Link immediately if the invited email already has an account
            try? await client.rpc("link_existing_cleaner", params: ["invite_id": row.id.uuidString])
            return true
        } catch {
            lastError = error.localizedDescription
            members.append(member)
            return true
        }
    }

    func remove(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            members.removeAll { $0.id == id }
            return true
        }

        do {
            try await client
                .from("team_members")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            members.removeAll { $0.id == id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateRole(id: UUID, role: TeamRole) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].role = role
            }
            return true
        }

        do {
            try await client
                .from("team_members")
                .update(TeamMemberPatch(role: role.rawValue))
                .eq("id", value: id.uuidString)
                .execute()
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].role = role
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateStatus(id: UUID, status: TeamMemberStatus) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].status = status
            }
            return true
        }

        do {
            try await client
                .from("team_members")
                .update(TeamMemberStatusPatch(status: status.rawValue))
                .eq("id", value: id.uuidString)
                .execute()
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].status = status
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateMember(id: UUID, name: String, email: String, phone: String, role: TeamRole) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].name  = name
                members[idx].email = email
                members[idx].phone = phone
                members[idx].role  = role
            }
            return true
        }

        do {
            try await client
                .from("team_members")
                .update(TeamMemberFullPatch(name: name, email: email, phone: phone, role: role.rawValue))
                .eq("id", value: id.uuidString)
                .execute()
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].name  = name
                members[idx].email = email
                members[idx].phone = phone
                members[idx].role  = role
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Payment History

    func loadPayments(memberId: UUID, ownerId: UUID) async -> [TeamMemberPayment] {
        guard let client = SupabaseManager.shared else { return [] }
        do {
            let rows: [TeamMemberPaymentDTO] = try await client
                .from("team_member_payments")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .eq("owner_id", value: ownerId.uuidString)
                .order("paid_at", ascending: false)
                .limit(20)
                .execute()
                .value
            return rows.map { $0.toPayment() }
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func recordPayment(memberId: UUID, ownerId: UUID, amount: Double, notes: String) async -> Bool {
        guard let client = SupabaseManager.shared else { return true }
        do {
            let insert = TeamMemberPaymentInsert(
                memberId: memberId,
                ownerId: ownerId,
                amount: amount,
                notes: notes.isEmpty ? nil : notes,
                paidAt: Date()
            )
            try await client
                .from("team_member_payments")
                .insert(insert)
                .execute()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Update Pay Rate

    func updatePayRate(id: UUID, rateType: PayRateType, amount: Double, enabled: Bool) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].payRateType = rateType
                members[idx].payRateAmount = amount
                members[idx].payRateEnabled = enabled
            }
            return true
        }

        do {
            try await client
                .from("team_members")
                .update(TeamMemberPayRatePatch(
                    payRateType: rateType.rawValue,
                    payRateAmount: amount,
                    payRateEnabled: enabled
                ))
                .eq("id", value: id.uuidString)
                .execute()
            if let idx = members.firstIndex(where: { $0.id == id }) {
                members[idx].payRateType = rateType
                members[idx].payRateAmount = amount
                members[idx].payRateEnabled = enabled
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

// MARK: - DTOs

private struct TeamMemberDTO: Decodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let email: String
    let phone: String
    let role: String
    let status: String
    let addedAt: Date
    let payRateType: String?
    let payRateAmount: Double?
    let payRateEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, role, status
        case ownerId  = "owner_id"
        case addedAt  = "added_at"
        case payRateType = "pay_rate_type"
        case payRateAmount = "pay_rate_amount"
        case payRateEnabled = "pay_rate_enabled"
    }

    func toMember() -> TeamMember {
        TeamMember(
            id: id,
            ownerId: ownerId,
            name: name,
            email: email,
            phone: phone,
            role: TeamRole(rawValue: role) ?? .member,
            status: TeamMemberStatus(rawValue: status) ?? .invited,
            addedAt: addedAt,
            payRateType: PayRateType(rawValue: payRateType ?? "per_job") ?? .perJob,
            payRateAmount: payRateAmount ?? 0,
            payRateEnabled: payRateEnabled ?? false
        )
    }
}

private struct TeamMemberInsert: Encodable {
    let ownerId: UUID
    let name: String
    let email: String
    let phone: String
    let role: String
    let status: String
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, email, phone, role, status
        case ownerId = "owner_id"
        case addedAt = "added_at"
    }
}

private struct TeamMemberPatch: Encodable {
    let role: String
}

private struct TeamMemberStatusPatch: Encodable {
    let status: String
}

private struct TeamMemberFullPatch: Encodable {
    let name: String
    let email: String
    let phone: String
    let role: String
}

private struct TeamMemberPayRatePatch: Encodable {
    let payRateType: String
    let payRateAmount: Double
    let payRateEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case payRateType = "pay_rate_type"
        case payRateAmount = "pay_rate_amount"
        case payRateEnabled = "pay_rate_enabled"
    }
}

// MARK: - TeamMemberPayment Public Model

struct TeamMemberPayment: Identifiable {
    let id: UUID
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let notes: String
    let paidAt: Date
}

private struct TeamMemberPaymentDTO: Decodable {
    let id: UUID
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let notes: String?
    let paidAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, notes
        case memberId = "member_id"
        case ownerId  = "owner_id"
        case paidAt   = "paid_at"
    }

    func toPayment() -> TeamMemberPayment {
        TeamMemberPayment(id: id, memberId: memberId, ownerId: ownerId,
                          amount: amount, notes: notes ?? "", paidAt: paidAt)
    }
}

private struct TeamMemberPaymentInsert: Encodable {
    let memberId: UUID
    let ownerId: UUID
    let amount: Double
    let notes: String?
    let paidAt: Date

    enum CodingKeys: String, CodingKey {
        case amount, notes
        case memberId = "member_id"
        case ownerId  = "owner_id"
        case paidAt   = "paid_at"
    }
}
