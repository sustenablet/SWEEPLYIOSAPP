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
            let lineItemsJSON = (try? JSONEncoder().encode(invoice.lineItems)).flatMap { String(data: $0, encoding: .utf8) }
            let row = InvoiceRowInsert(
                userId: userId,
                clientId: invoice.clientId,
                clientName: invoice.clientName,
                amount: invoice.subtotal,
                status: invoice.status.rawValue,
                dueDate: invoice.dueDate,
                invoiceNumber: invoice.invoiceNumber,
                notes: invoice.notes.isEmpty ? nil : invoice.notes,
                lineItems: lineItemsJSON
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

    func update(_ invoice: Invoice, userId: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
                invoices[idx] = invoice
            }
            return true
        }
        lastError = nil
        do {
            let lineItemsJSON = (try? JSONEncoder().encode(invoice.lineItems)).flatMap { String(data: $0, encoding: .utf8) }
            let patch = InvoiceUpdatePatch(
                amount: invoice.subtotal,
                dueDate: invoice.dueDate,
                notes: invoice.notes.isEmpty ? nil : invoice.notes,
                lineItems: lineItemsJSON
            )
            let refreshed: InvoiceRow = try await client
                .from("invoices")
                .update(patch)
                .eq("id", value: invoice.id)
                .select()
                .single()
                .execute()
                .value
            if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
                invoices[idx] = refreshed.toInvoice()
            }
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

    func markOverdueInvoices() async {
        let today = Calendar.current.startOfDay(for: Date())
        let overdueIds = invoices
            .filter { $0.status == .unpaid && Calendar.current.startOfDay(for: $0.dueDate) < today }
            .map { $0.id }
        guard !overdueIds.isEmpty else { return }

        // Update locally first for immediate UI response
        for id in overdueIds {
            if let idx = invoices.firstIndex(where: { $0.id == id }) {
                invoices[idx].status = .overdue
            }
        }

        // Persist to Supabase
        guard let client = SupabaseManager.shared else { return }
        for id in overdueIds {
            do {
                let patch = InvoiceStatusPatch(status: InvoiceStatus.overdue.rawValue)
                let refreshed: InvoiceRow = try await client
                    .from("invoices")
                    .update(patch)
                    .eq("id", value: id)
                    .select()
                    .single()
                    .execute()
                    .value
                if let idx = invoices.firstIndex(where: { $0.id == refreshed.id }) {
                    invoices[idx] = refreshed.toInvoice()
                }
            } catch { /* skip individual failures silently */ }
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
    let notes: String?
    let lineItems: String?      // JSON-encoded [InvoiceLineItem]

    enum CodingKeys: String, CodingKey {
        case id, amount, status, notes
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case createdAt     = "created_at"
        case dueDate       = "due_date"
        case invoiceNumber = "invoice_number"
        case lineItems     = "line_items"
    }

    func toInvoice() -> Invoice {
        let items: [InvoiceLineItem] = {
            guard let json = lineItems, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([InvoiceLineItem].self, from: data)) ?? []
        }()
        return Invoice(
            id: id,
            clientId: clientId,
            clientName: clientName,
            amount: amount,
            status: InvoiceStatus(rawValue: status) ?? .unpaid,
            createdAt: createdAt,
            dueDate: dueDate,
            invoiceNumber: invoiceNumber,
            notes: notes ?? "",
            lineItems: items
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
    let notes: String?
    let lineItems: String?

    enum CodingKeys: String, CodingKey {
        case amount, status, notes
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case dueDate       = "due_date"
        case invoiceNumber = "invoice_number"
        case lineItems     = "line_items"
    }
}

private struct InvoiceStatusPatch: Encodable {
    let status: String
}

private struct InvoiceUpdatePatch: Encodable {
    let amount: Double
    let dueDate: Date
    let notes: String?
    let lineItems: String?

    enum CodingKeys: String, CodingKey {
        case amount, notes
        case dueDate   = "due_date"
        case lineItems = "line_items"
    }
}
