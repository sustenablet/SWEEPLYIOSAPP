import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class ClientsStore {
    var clients: [Client] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        clients = []
        lastError = nil
    }

    func load(isAuthenticated: Bool) async {
        guard let client = SupabaseManager.shared else {
            clients = []
            lastError = "Supabase is not configured."
            return
        }
        guard isAuthenticated else {
            clients = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [ClientRow] = try await client
                .from("clients")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
            clients = rows.map { $0.toClient() }
        } catch {
            lastError = error.localizedDescription
            clients = []
        }
    }

    func insert(_ newClient: Client, userId: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            clients.append(newClient)
            clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return true
        }
        lastError = nil
        do {
            let row = ClientRowInsert(
                userId: userId,
                name: newClient.name,
                email: newClient.email,
                phone: newClient.phone,
                address: newClient.address,
                city: newClient.city,
                state: newClient.state,
                zip: newClient.zip,
                preferredService: newClient.preferredService?.rawValue,
                entryInstructions: newClient.entryInstructions,
                notes: newClient.notes,
                isActive: newClient.isActive
            )
            let inserted: ClientRow = try await client
                .from("clients")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            let mapped = inserted.toClient()
            clients.append(mapped)
            clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func update(_ updated: Client) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = clients.firstIndex(where: { $0.id == updated.id }) {
                clients[idx] = updated
            }
            return true
        }
        lastError = nil
        do {
            let patch = ClientRowPatch(
                name: updated.name,
                email: updated.email,
                phone: updated.phone,
                address: updated.address,
                city: updated.city,
                state: updated.state,
                zip: updated.zip,
                preferredService: updated.preferredService?.rawValue,
                entryInstructions: updated.entryInstructions,
                notes: updated.notes,
                isActive: updated.isActive
            )
            let refreshed: ClientRow = try await client
                .from("clients")
                .update(patch)
                .eq("id", value: updated.id)
                .select()
                .single()
                .execute()
                .value
            let mapped = refreshed.toClient()
            if let idx = clients.firstIndex(where: { $0.id == mapped.id }) {
                clients[idx] = mapped
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            clients.removeAll { $0.id == id }
            return true
        }
        lastError = nil
        do {
            try await client
                .from("clients")
                .delete()
                .eq("id", value: id)
                .execute()
            clients.removeAll { $0.id == id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

// MARK: - DTOs

private struct ClientRow: Decodable {
    let id: UUID
    let userId: UUID
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let preferredService: String?
    let entryInstructions: String?
    let notes: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, address, city, state, zip, notes
        case userId = "user_id"
        case preferredService = "preferred_service"
        case entryInstructions = "entry_instructions"
        case isActive = "is_active"
    }

    func toClient() -> Client {
        let svc = preferredService.flatMap { ServiceType(rawValue: $0) }
        return Client(
            id: id,
            name: name,
            email: email ?? "",
            phone: phone ?? "",
            address: address ?? "",
            city: city ?? "",
            state: state ?? "",
            zip: zip ?? "",
            preferredService: svc,
            entryInstructions: entryInstructions ?? "",
            notes: notes ?? "",
            isActive: isActive ?? true
        )
    }
}

private struct ClientRowInsert: Encodable {
    let userId: UUID
    let name: String
    let email: String
    let phone: String
    let address: String
    let city: String
    let state: String
    let zip: String
    let preferredService: String?
    let entryInstructions: String
    let notes: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, email, phone, address, city, state, zip, notes
        case preferredService = "preferred_service"
        case entryInstructions = "entry_instructions"
        case isActive = "is_active"
    }
}

private struct ClientRowPatch: Encodable {
    let name: String
    let email: String
    let phone: String
    let address: String
    let city: String
    let state: String
    let zip: String
    let preferredService: String?
    let entryInstructions: String
    let notes: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name, email, phone, address, city, state, zip, notes
        case preferredService = "preferred_service"
        case entryInstructions = "entry_instructions"
        case isActive = "is_active"
    }
}
