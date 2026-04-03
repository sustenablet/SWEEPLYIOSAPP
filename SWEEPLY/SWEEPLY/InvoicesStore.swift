import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class InvoicesStore {
    var invoices: [Invoice] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        invoices = []
        lastError = nil
    }

    func load(isAuthenticated: Bool) async {
        guard let client = SupabaseManager.shared else {
            invoices = []
            lastError = "Supabase is not configured."
            return
        }
        guard isAuthenticated else {
            invoices = []
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [InvoiceRow] = try await client
                .from("invoices")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            invoices = rows.map { $0.toInvoice() }
        } catch {
            lastError = error.localizedDescription
            invoices = []
        }
    }

    func insert(_ invoice: Invoice, userId: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            invoices.insert(invoice, at: 0)
            return true
        }
        lastError = nil
        do {
            let row = InvoiceRowInsert(
                userId: userId,
                clientId: invoice.clientId,
                clientName: invoice.clientName,
                amount: invoice.amount,
                status: invoice.status.rawValue,
                dueDate: invoice.dueDate,
                invoiceNumber: invoice.invoiceNumber
            )
            let inserted: InvoiceRow = try await client
                .from("invoices")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            invoices.insert(inserted.toInvoice(), at: 0)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func markPaid(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = invoices.firstIndex(where: { $0.id == id }) {
                invoices[idx].status = .paid
            }
            return true
        }
        lastError = nil
        do {
            let patch = InvoiceStatusPatch(status: InvoiceStatus.paid.rawValue)
            let refreshed: InvoiceRow = try await client
                .from("invoices")
                .update(patch)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            if let idx = invoices.firstIndex(where: { $0.id == id }) {
                invoices[idx] = refreshed.toInvoice()
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            invoices.removeAll { $0.id == id }
            return true
        }
        lastError = nil
        do {
            try await client
                .from("invoices")
                .delete()
                .eq("id", value: id)
                .execute()
            invoices.removeAll { $0.id == id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Returns the next sequential invoice number (e.g. "INV-0044").
    func nextInvoiceNumber() -> String {
        let numbers = invoices.compactMap { inv -> Int? in
            let parts = inv.invoiceNumber.split(separator: "-")
            guard parts.count == 2, let n = Int(parts[1]) else { return nil }
            return n
        }
        let next = (numbers.max() ?? 0) + 1
        return String(format: "INV-%04d", next)
    }
}

// MARK: - DTOs

private struct InvoiceRow: Decodable {
    let id: UUID
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let amount: Double
    let status: String
    let createdAt: Date
    let dueDate: Date
    let invoiceNumber: String

    enum CodingKeys: String, CodingKey {
        case id, amount, status
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case createdAt     = "created_at"
        case dueDate       = "due_date"
        case invoiceNumber = "invoice_number"
    }

    func toInvoice() -> Invoice {
        Invoice(
            id: id,
            clientId: clientId,
            clientName: clientName,
            amount: amount,
            status: InvoiceStatus(rawValue: status) ?? .unpaid,
            createdAt: createdAt,
            dueDate: dueDate,
            invoiceNumber: invoiceNumber
        )
    }
}

private struct InvoiceRowInsert: Encodable {
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let amount: Double
    let status: String
    let dueDate: Date
    let invoiceNumber: String

    enum CodingKeys: String, CodingKey {
        case amount, status
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case dueDate       = "due_date"
        case invoiceNumber = "invoice_number"
    }
}

private struct InvoiceStatusPatch: Encodable {
    let status: String
}
