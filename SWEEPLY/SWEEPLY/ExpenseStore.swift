import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class ExpenseStore {
    var expenses: [Expense] = []
    var isLoading = false
    var lastError: String?

    func clear() {
        expenses = []
        lastError = nil
    }

    // MARK: - Load

    func load(userId: UUID) async {
        guard let client = SupabaseManager.shared else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let rows: [ExpenseRow] = try await client
                .from("expenses")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("date", ascending: false)
                .execute()
                .value
            expenses = rows.map { $0.toExpense() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Add

    func add(_ expense: Expense) async -> Bool {
        guard let client = SupabaseManager.shared else {
            expenses.insert(expense, at: 0)
            return true
        }

        let insert = ExpenseInsert(
            userId: expense.userId,
            amount: expense.amount,
            category: expense.category.rawValue,
            notes: expense.notes,
            date: expense.date
        )

        do {
            let row: ExpenseRow = try await client
                .from("expenses")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            expenses.insert(row.toExpense(), at: 0)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Remove

    func remove(id: UUID) async -> Bool {
        guard let client = SupabaseManager.shared else {
            expenses.removeAll { $0.id == id }
            return true
        }

        do {
            try await client
                .from("expenses")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            expenses.removeAll { $0.id == id }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Computed

    func total(in period: DateInterval) -> Double {
        expenses
            .filter { period.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    func byCategory(in period: DateInterval) -> [(ExpenseCategory, Double)] {
        let filtered = expenses.filter { period.contains($0.date) }
        return ExpenseCategory.allCases.compactMap { cat in
            let sum = filtered.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            return sum > 0 ? (cat, sum) : nil
        }
    }
}

// MARK: - DTOs

private struct ExpenseRow: Decodable {
    let id: UUID
    let userId: UUID
    let amount: Double
    let category: String
    let notes: String
    let date: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, category, notes, date
        case userId = "user_id"
    }

    func toExpense() -> Expense {
        Expense(
            id: id,
            userId: userId,
            amount: amount,
            category: ExpenseCategory(rawValue: category) ?? .other,
            notes: notes,
            date: date
        )
    }
}

private struct ExpenseInsert: Encodable {
    let userId: UUID
    let amount: Double
    let category: String
    let notes: String
    let date: Date

    enum CodingKeys: String, CodingKey {
        case amount, category, notes, date
        case userId = "user_id"
    }
}
