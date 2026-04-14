import SwiftUI

// MARK: - ExpensesView

struct ExpensesView: View {
    @Environment(ExpenseStore.self) private var expenseStore
    @Environment(AppSession.self)   private var session
    @Environment(\.dismiss)          private var dismiss

    @State private var showAddSheet  = false
    @State private var deleteTarget  : Expense? = nil
    @State private var selectedMonth : Date = Date()

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }

    private var monthInterval: DateInterval {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else {
            return DateInterval(start: selectedMonth, duration: 0)
        }
        return interval
    }

    private var monthExpenses: [Expense] {
        expenseStore.expenses.filter { monthInterval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var monthTotal: Double {
        monthExpenses.reduce(0) { $0 + $1.amount }
    }

    private var categoryBreakdown: [(ExpenseCategory, Double)] {
        expenseStore.byCategory(in: monthInterval)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Month picker
                        monthStepper

                        // Summary card
                        summaryCard

                        // Expense list
                        if monthExpenses.isEmpty {
                            emptyState
                        } else {
                            expenseList
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExpenseSheet(userId: session.userId ?? UUID())
                    .environment(expenseStore)
            }
        }
    }

    // MARK: - Month stepper

    private var monthStepper: some View {
        HStack {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
            }

            Spacer()

            Text(monthLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)

            Spacer()

            Button {
                let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                if next <= Date() { selectedMonth = next }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth).map { $0 <= Date() }
                        == true ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.3)
                    )
            }
            .disabled((Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? Date()) > Date())
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Total Expenses")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(monthTotal.currency)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(monthTotal > 0 ? Color.sweeplyDestructive : Color.primary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text("\(monthExpenses.count) item\(monthExpenses.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                if !categoryBreakdown.isEmpty {
                    Divider()

                    VStack(spacing: 10) {
                        ForEach(categoryBreakdown, id: \.0) { cat, amount in
                            HStack(spacing: 10) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .frame(width: 20)
                                Text(cat.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(amount.currency)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyNavy)
                                // Progress bar
                                Capsule()
                                    .fill(Color.sweeplyAccent.opacity(0.25))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.sweeplyAccent)
                                            .frame(width: max(4, 60 * (amount / monthTotal)))
                                    }
                                    .frame(width: 60, height: 4)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expense list

    private var expenseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(monthExpenses.enumerated()), id: \.element.id) { idx, expense in
                expenseRow(expense)
                if idx < monthExpenses.count - 1 {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .background(Color.sweeplySurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: expense.category.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                if !expense.notes.isEmpty {
                    Text(expense.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                } else {
                    Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.amount.currency)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyDestructive)
                if !expense.notes.isEmpty {
                    Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await expenseStore.remove(id: expense.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.35))
            Text("No expenses in \(monthLabel)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            Text("Track what you spend on supplies,\nfuel, equipment, and more.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                showAddSheet = true
            } label: {
                Text("Add Expense")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.sweeplyNavy, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - AddExpenseSheet

struct AddExpenseSheet: View {
    @Environment(ExpenseStore.self) private var expenseStore
    @Environment(\.dismiss)          private var dismiss

    let userId: UUID

    @State private var amount   = ""
    @State private var category = ExpenseCategory.supplies
    @State private var notes    = ""
    @State private var date     = Date()
    @State private var isSaving = false

    private var parsedAmount: Double? {
        let cleaned = amount.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private var canSave: Bool {
        (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Amount
                        SectionCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Amount")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("$")
                                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                    TextField("0.00", text: $amount)
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .keyboardType(.decimalPad)
                                        .foregroundStyle(Color.primary)
                                }
                            }
                        }

                        // Category
                        SectionCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Category")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyTextSub)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                    ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                                        categoryTile(cat)
                                    }
                                }
                            }
                        }

                        // Notes + Date
                        SectionCard {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Notes")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .frame(width: 60, alignment: .leading)
                                    TextField("Optional", text: $notes)
                                        .font(.system(size: 15))
                                }
                                .padding(.vertical, 14)

                                Divider()

                                HStack {
                                    Text("Date")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                        .frame(width: 60, alignment: .leading)
                                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                        .labelsHidden()
                                }
                                .padding(.vertical, 10)
                            }
                        }

                        // Save button
                        Button {
                            Task { await save() }
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Text("Save Expense")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canSave ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave || isSaving)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    private func categoryTile(_ cat: ExpenseCategory) -> some View {
        let selected = category == cat
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.1)) { category = cat }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: cat.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? .white : Color.sweeplyAccent)
                Text(cat.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? .white : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                selected ? Color.sweeplyNavy : Color.sweeplyBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func save() async {
        guard let amt = parsedAmount else { return }
        isSaving = true
        defer { isSaving = false }

        let expense = Expense(
            userId: userId,
            amount: amt,
            category: category,
            notes: notes.trimmingCharacters(in: .whitespaces),
            date: date
        )
        let ok = await expenseStore.add(expense)
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}
