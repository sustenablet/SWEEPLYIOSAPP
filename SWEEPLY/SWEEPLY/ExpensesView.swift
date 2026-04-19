import SwiftUI

// MARK: - ExpensesView

struct ExpensesView: View {
    @Environment(ExpenseStore.self) private var expenseStore
    @Environment(AppSession.self)   private var session
    @Environment(\.dismiss)          private var dismiss

    @State private var showAddSheet  = false
    @State private var selectedMonth : Date = Date()
    @State private var selectedDay  : Date? = nil
    @State private var appeared      = false

    private var canAddExpense: Bool {
        session.userId != nil
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }

    private var shortMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
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

    private var filteredExpenses: [Expense] {
        if let day = selectedDay {
            let cal = Calendar.current
            return monthExpenses.filter { cal.isDate($0.date, inSameDayAs: day) }
        }
        return monthExpenses
    }

    private var filteredTotal: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }

    private var monthTotal: Double {
        monthExpenses.reduce(0) { $0 + $1.amount }
    }

    private var categoryBreakdown: [(ExpenseCategory, Double)] {
        expenseStore.byCategory(in: monthInterval)
    }

    private var canGoForward: Bool {
        (Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? Date()) <= Date()
    }

    private var daysInMonth: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }
        
        var days: [Date] = []
        var current = interval.start
        while current < interval.end {
            days.append(current)
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current
        }
        
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let paddingDays = firstWeekday - 1
        var paddedDays: [Date] = []
        for i in 0..<paddingDays {
            if let paddingDate = cal.date(byAdding: .day, value: -i - 1, to: interval.start) {
                paddedDays.insert(paddingDate, at: 0)
            }
        }
        
        return paddedDays + days
    }

    private func hasExpense(on date: Date) -> Bool {
        let cal = Calendar.current
        return monthExpenses.contains { cal.isDate($0.date, inSameDayAs: date) }
    }

    private func dayNumber(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.day, from: date))"
    }

    private func selectDay(_ date: Date) {
        let cal = Calendar.current
        let now = Date()
        
        if cal.component(.month, from: date) == cal.component(.month, from: selectedMonth) {
            if let selected = selectedDay, cal.isDate(selected, inSameDayAs: date) {
                selectedDay = nil
            } else if date <= now {
                selectedDay = date
            }
        }
    }

    private func isSameMonth(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.month, from: date) == cal.component(.month, from: selectedMonth)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selected = selectedDay else { return false }
        let cal = Calendar.current
        return cal.isDate(date, inSameDayAs: selected)
    }

    private func isFuture(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = Date()
        return date > now
    }

    @ViewBuilder
    private var totalLabel: some View {
        if selectedDay != nil {
            Text("Day Total")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.8)
        } else {
            Text("Total Spent")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }

    @ViewBuilder
    private var expenseCountLabel: some View {
        if selectedDay != nil {
            Text("\(filteredExpenses.count) expense\(filteredExpenses.count == 1 ? "" : "s") in \(shortMonthLabel)")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
        } else {
            Text("\(monthExpenses.count) expense\(monthExpenses.count == 1 ? "" : "s") in \(shortMonthLabel)")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
        }
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.sweeplyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                            .padding(.bottom, 24)

                        VStack(spacing: 16) {
                            if !categoryBreakdown.isEmpty {
                                categoryCard
                            }
                            expenseListSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }

                // Floating add button
                addButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) { appeared = true }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                ToolbarItem(placement: .principal) {
                    Text("Expenses")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
.sheet(isPresented: $showAddSheet) {
                if let uid = session.userId {
                    AddExpenseSheet(userId: uid)
                        .environment(expenseStore)
                }
        }
        }
    }

    // MARK: - Hero header with calendar

    private var heroHeader: some View {
        VStack(spacing: 0) {
            // Month navigator
            HStack(spacing: 20) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    selectedDay = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(width: 32, height: 32)
                        .background(Color.sweeplySurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.sweeplyBorder, lineWidth: 1))
                }

                Text(shortMonthLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(minWidth: 90)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    if next <= Date() { selectedMonth = next }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canGoForward ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .background(canGoForward ? Color.sweeplySurface : Color.clear)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(canGoForward ? Color.sweeplyBorder : Color.clear, lineWidth: 1))
                }
                .disabled(!canGoForward)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)

            // Calendar grid
            calendarGrid
                .padding(.bottom, 20)

            // Big total
            VStack(spacing: 6) {
                totalLabel

                Text(filteredTotal.currency)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(filteredTotal > 0 ? Color.sweeplyDestructive : Color.sweeplyTextSub.opacity(0.4))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: filteredTotal)

                if !filteredExpenses.isEmpty {
                    expenseCountLabel
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                colors: [Color.sweeplySurface, Color.sweeplyBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            // Day headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(daysInMonth, id: \.self) { date in
                    calendarDayCell(date)
                }
            }
        }
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let inCurrentMonth = isSameMonth(date)
        let today = isToday(date)
        let selected = isSelected(date)
        let hasExp = inCurrentMonth && hasExpense(on: date)
        let future = isFuture(date)

        return Button {
            if inCurrentMonth && !future {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectDay(date)
            }
        } label: {
            VStack(spacing: 2) {
                Text(dayNumber(date))
                    .font(.system(size: 14, weight: selected ? .bold : (today ? .semibold : .medium)))
                    .foregroundStyle(selected ? .white : (today ? Color.sweeplyNavy : (inCurrentMonth ? Color.primary : Color.sweeplyTextSub.opacity(0.25))))

                if hasExp && inCurrentMonth {
                    Circle()
                        .fill(selected ? Color.white : Color.sweeplyAccent)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.sweeplyNavy)
                } else if today && inCurrentMonth {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sweeplyNavy, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!inCurrentMonth || future)
    }

    // MARK: - Category breakdown card

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Category")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categoryBreakdown, id: \.0) { cat, amount in
                        categoryCarouselCard(cat: cat, amount: amount)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private func categoryCarouselCard(cat: ExpenseCategory, amount: Double) -> some View {
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(categoryColor(cat).opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: cat.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(categoryColor(cat))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(cat.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text(amount.currency)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func categoryRow(cat: ExpenseCategory, amount: Double) -> some View {
        let pct = monthTotal > 0 ? amount / monthTotal : 0
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(categoryColor(cat).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: cat.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(categoryColor(cat))
                }
                Text(cat.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(amount.currency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 30, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 3)
                    Capsule()
                        .fill(categoryColor(cat))
                        .frame(width: max(4, geo.size.width * pct), height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Expense list

    @ViewBuilder
    private var expenseListTitle: some View {
        if selectedDay != nil {
            Text("Day's Expenses")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.6)
        } else {
            Text("Transactions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
                .textCase(.uppercase)
                .tracking(0.6)
        }
    }

    private var expenseListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !filteredExpenses.isEmpty {
                expenseListTitle

                VStack(spacing: 0) {
                    ForEach(Array(filteredExpenses.enumerated()), id: \.element.id) { idx, expense in
                        expenseRow(expense)
                        if idx < filteredExpenses.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(categoryColor(expense.category).opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: expense.category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(categoryColor(expense.category))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(expense.notes.isEmpty
                     ? expense.date.formatted(date: .abbreviated, time: .omitted)
                     : expense.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("−\(expense.amount.currency)")
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyBorder.opacity(0.4))
                    .frame(width: 72, height: 72)
                Image(systemName: "creditcard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            }
            VStack(spacing: 6) {
                Text("No expenses in \(shortMonthLabel)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Track supplies, fuel, equipment,\nand every business cost here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: - Floating add button

    private var addButton: some View {
        Button {
            guard canAddExpense else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("Add Expense")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(canAddExpense ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.sweeplyNavy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.sweeplyNavy.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canAddExpense)
    }

    // MARK: - Helpers

    private func categoryColor(_ cat: ExpenseCategory) -> Color {
        switch cat {
        case .supplies:    return Color(hue: 0.58, saturation: 0.70, brightness: 0.75)
        case .fuel:        return Color(hue: 0.08, saturation: 0.80, brightness: 0.82)
        case .equipment:   return Color(hue: 0.55, saturation: 0.60, brightness: 0.65)
        case .insurance:   return Color(hue: 0.35, saturation: 0.65, brightness: 0.68)
        case .marketing:   return Color(hue: 0.78, saturation: 0.55, brightness: 0.75)
        case .other:       return Color(hue: 0.40, saturation: 0.45, brightness: 0.60)
        }
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
    @FocusState private var isAmountFocused: Bool

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
                    .onTapGesture {
                        isAmountFocused = false
                    }

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
                                        .focused($isAmountFocused)
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
