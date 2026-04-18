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

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, role, status
        case ownerId  = "owner_id"
        case addedAt  = "added_at"
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
            addedAt: addedAt
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
