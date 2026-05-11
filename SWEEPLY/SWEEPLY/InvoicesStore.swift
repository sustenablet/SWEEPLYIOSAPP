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
            lastError = "Unable to connect. Please try again."
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
            // Refresh Monday summary push with real last-week revenue
            let cal = Calendar.current
            if let lastWeek = cal.dateInterval(of: .weekOfYear, for: Date().addingTimeInterval(-7*24*3600)) {
                let lastWeekRevenue = invoices
                    .filter { $0.status == .paid }
                    .filter { inv in lastWeek.contains(inv.paidAt ?? inv.createdAt) }
                    .reduce(0) { $0 + $1.total }
                NotificationManager.shared.refreshWeeklyEarningsSummary(weeklyRevenue: lastWeekRevenue)
            }
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
            let finalInvoice = inserted.toInvoice()
            invoices.insert(finalInvoice, at: 0)
            NotificationManager.shared.scheduleInvoiceReminder(for: finalInvoice)
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
            let updated = refreshed.toInvoice()
            if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
                invoices[idx] = updated
            }
            // Reschedule reminders in case due date changed
            NotificationManager.shared.cancelInvoiceReminders(for: invoice.id)
            NotificationManager.shared.scheduleInvoiceReminder(for: updated)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func markPaid(id: UUID, amount: Double, method: PaymentMethod) async -> Bool {
        let paidAt = Date()
        
        guard let client = SupabaseManager.shared else {
            if let idx = invoices.firstIndex(where: { $0.id == id }) {
                invoices[idx].status = .paid
                invoices[idx].paidAmount = amount
                invoices[idx].paymentMethod = method
                invoices[idx].paidAt = paidAt
            }
            return true
        }
        
        lastError = nil
        do {
            let patch = InvoicePaymentPatch(
                status: InvoiceStatus.paid.rawValue,
                paidAmount: amount,
                paymentMethod: method.rawValue,
                paidAt: paidAt
            )
            let refreshed: InvoiceRow = try await client
                .from("invoices")
                .update(patch)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            if let idx = invoices.firstIndex(where: { $0.id == id }) {
                let paid = refreshed.toInvoice()
                invoices[idx] = paid
                NotificationManager.shared.cancelInvoiceReminders(for: id)
                // Revenue milestone check
                let totalNow = invoices.filter { $0.status == .paid }.reduce(0) { $0 + $1.total }
                let totalBefore = totalNow - amount
                let milestones: [Double] = [1_000, 5_000, 10_000, 25_000, 50_000, 100_000]
                for milestone in milestones {
                    if totalBefore < milestone && totalNow >= milestone {
                        let label = milestone >= 1_000
                            ? "$\(String(format: "%.0f", milestone / 1_000))k"
                            : milestone.currency
                        await NotificationHelper.insert(
                            title: "Revenue Milestone Reached 🎉",
                            message: "You've collected \(label) in total revenue. Keep it up!",
                            kind: "system"
                        )
                        NotificationManager.shared.fireInstantBanner(
                            title: "Revenue Milestone 🎉",
                            body: "You've collected \(label) in total revenue!"
                        )
                        break
                    }
                }
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
            NotificationManager.shared.cancelInvoiceReminders(for: id)
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
        guard let client = SupabaseManager.shared else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Query Supabase directly — safe to call from background tasks
        // where the in-memory `invoices` array may be empty.
        do {
            let rows: [InvoiceRow] = try await client
                .from("invoices")
                .select()
                .eq("status", value: InvoiceStatus.unpaid.rawValue)
                .lt("due_date", value: ISO8601DateFormatter().string(from: today))
                .execute()
                .value

            guard !rows.isEmpty else { return }
            let ids = rows.map { $0.id }

            let patch = InvoiceStatusPatch(status: InvoiceStatus.overdue.rawValue)
            for id in ids {
                try? await client
                    .from("invoices")
                    .update(patch)
                    .eq("id", value: id)
                    .execute()
            }

            // Refresh in-memory list if already loaded
            if !invoices.isEmpty {
                for id in ids {
                    if let idx = invoices.firstIndex(where: { $0.id == id }) {
                        invoices[idx].status = .overdue
                    }
                }
            }
        } catch { /* silent — background task, not user-facing */ }
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
    let paidAmount: Double?
    let paymentMethod: String?
    let paidAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount, status, notes
        case userId        = "user_id"
        case clientId      = "client_id"
        case clientName    = "client_name"
        case createdAt     = "created_at"
        case dueDate       = "due_date"
        case invoiceNumber = "invoice_number"
        case lineItems     = "line_items"
        case paidAmount    = "paid_amount"
        case paymentMethod = "payment_method"
        case paidAt        = "paid_at"
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
            lineItems: items,
            paidAmount: paidAmount,
            paymentMethod: paymentMethod.flatMap { PaymentMethod(rawValue: $0) },
            paidAt: paidAt
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

private struct InvoicePaymentPatch: Encodable {
    let status: String
    let paidAmount: Double
    let paymentMethod: String
    let paidAt: Date
    
    enum CodingKeys: String, CodingKey {
        case status
        case paidAmount    = "paid_amount"
        case paymentMethod = "payment_method"
        case paidAt        = "paid_at"
    }
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
