import SwiftUI

struct MemberPaySetupView: View {
    @Environment(TeamStore.self) private var teamStore
    @Environment(\.dismiss) private var dismiss

    let member: TeamMember

    // MARK: - Wizard state
    @State private var step: Int = 1
    @State private var selectedPayType: PayRateType
    @State private var serviceRates: [String: Double]
    @State private var flatAmount: String
    @State private var payDay: Int
    @State private var paymentMethod: PaymentMethod
    @State private var isSaving = false

    // Standard service types shown in the per-job rate screen
    private let standardServices: [ServiceType] = [.standard, .deep, .moveInOut, .postConstruction, .office]

    init(member: TeamMember) {
        self.member = member
        _selectedPayType = State(initialValue: member.payRateEnabled ? member.payRateType : .perJob)
        _serviceRates = State(initialValue: member.serviceRates)
        _flatAmount = State(initialValue: member.payRateAmount > 0 ? String(format: "%.0f", member.payRateAmount) : "")
        _payDay = State(initialValue: member.payDayOfWeek ?? 6)
        let key = "memberPayMethod_\(member.id.uuidString)"
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        _paymentMethod = State(initialValue: PaymentMethod(rawValue: raw) ?? .cash)
    }

    // MARK: - Step sequence

    private var totalSteps: Int {
        switch selectedPayType {
        case .perWeek: return 5
        default:       return 4
        }
    }

    private var displayStep: Int {
        // Map internal step to display position (skips pay-day step for non-weekly)
        step
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.sweeplyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                        .padding(.top, 8)

                    Group {
                        switch step {
                        case 1: payTypeStep
                        case 2: selectedPayType == .perJob ? AnyView(serviceRatesStep) : AnyView(flatAmountStep)
                        case 3 where selectedPayType == .perWeek: payDayStep
                        case 3: paymentMethodStep
                        case 4 where selectedPayType == .perWeek: paymentMethodStep
                        case 4: summaryStep
                        case 5: summaryStep
                        default: summaryStep
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Spacer()
                }

                // Bottom navigation
                bottomBar
            }
            .navigationTitle("Pay Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.6))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .padding(.horizontal, 24)

            Text("Step \(step) of \(totalSteps)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .padding(.bottom, 32)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if step > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
            }

            let isLastStep = step == totalSteps
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if isLastStep {
                    Task { await save() }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) { step += 1 }
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 6) {
                            Text(isLastStep ? "Save Setup" : "Next")
                                .font(.system(size: 16, weight: .semibold))
                            if !isLastStep {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isNextEnabled ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isNextEnabled || isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .background(
            Color.sweeplyBackground
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: -6)
                .ignoresSafeArea()
        )
    }

    private var isNextEnabled: Bool {
        switch step {
        case 1: return true
        case 2:
            if selectedPayType == .perJob {
                return serviceRates.values.contains { $0 > 0 }
            }
            return selectedPayType == .custom || (Double(flatAmount) ?? 0) > 0
        default: return true
        }
    }

    // MARK: - Step 1: Pay Type

    private var payTypeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: "How do you pay \(member.name.components(separatedBy: " ").first ?? member.name)?",
                subtitle: "Choose the pay structure that fits your arrangement."
            )

            VStack(spacing: 12) {
                ForEach(PayRateType.allCases, id: \.self) { type in
                    payTypeCard(type)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func payTypeCard(_ type: PayRateType) -> some View {
        let isSelected = selectedPayType == type
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) { selectedPayType = type }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.4))
                        .frame(width: 40, height: 40)
                    Image(systemName: payTypeIcon(type))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(type.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sweeplyNavy)
                }
            }
            .padding(14)
            .background(isSelected ? Color.sweeplyNavy.opacity(0.06) : Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.sweeplyNavy.opacity(0.4) : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func payTypeIcon(_ type: PayRateType) -> String {
        switch type {
        case .perJob:  return "briefcase.fill"
        case .perDay:  return "sun.max.fill"
        case .perWeek: return "calendar"
        case .custom:  return "slider.horizontal.3"
        }
    }

    // MARK: - Step 2a: Service rates (Per Job)

    private var serviceRatesStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: "Set your rate per service",
                subtitle: "Enter how much you pay for each type of job. Leave blank to skip a service."
            )

            VStack(spacing: 0) {
                ForEach(Array(standardServices.enumerated()), id: \.element) { idx, svc in
                    serviceRateRow(svc)
                    if idx < standardServices.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 24)
        }
    }

    private func serviceRateRow(_ svc: ServiceType) -> some View {
        let binding = Binding<String>(
            get: {
                let v = serviceRates[svc.rawValue] ?? 0
                return v > 0 ? String(format: "%.0f", v) : ""
            },
            set: { newVal in
                serviceRates[svc.rawValue] = Double(newVal) ?? 0
            }
        )
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.sweeplyAccent.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: serviceIcon(svc))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            Text(svc.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                Text("$")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                TextField("0", text: binding)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func serviceIcon(_ svc: ServiceType) -> String {
        switch svc {
        case .standard:         return "house.fill"
        case .deep:             return "sparkles"
        case .moveInOut:        return "shippingbox.fill"
        case .postConstruction: return "hammer.fill"
        case .office:           return "building.2.fill"
        case .custom:           return "wrench.and.screwdriver.fill"
        }
    }

    // MARK: - Step 2b: Flat amount (Per Day / Per Week / Custom)

    private var flatAmountStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: flatAmountTitle,
                subtitle: flatAmountSubtitle
            )

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.sweeplyTextSub)
                    TextField("0", text: $flatAmount)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.sweeplyNavy)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
    }

    private var flatAmountTitle: String {
        let name = member.name.components(separatedBy: " ").first ?? member.name
        switch selectedPayType {
        case .perDay:  return "How much per day?"
        case .perWeek: return "How much per week?"
        case .custom:  return "What's the amount for \(name)?"
        default:       return "How much?"
        }
    }

    private var flatAmountSubtitle: String {
        switch selectedPayType {
        case .perDay:  return "This amount is paid for every day they work, regardless of how many jobs."
        case .perWeek: return "This flat amount covers all their work for the week."
        case .custom:  return "Enter a custom amount you'll pay. You can adjust this at any time."
        default:       return ""
        }
    }

    // MARK: - Step 3: Pay Day (Per Week only)

    private var payDayStep: some View {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: "Which day do you pay \(member.name.components(separatedBy: " ").first ?? member.name)?",
                subtitle: "They'll receive a notification on this day as a reminder."
            )

            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                    let weekday = idx + 1
                    let isSelected = payDay == weekday
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) { payDay = weekday }
                    } label: {
                        Text(day)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Color.sweeplyNavy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color.sweeplyNavy : Color.sweeplySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.clear : Color.sweeplyBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 4: Payment method

    private var paymentMethodStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: "How will you send payment?",
                subtitle: "Choose how you typically pay this team member."
            )

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    paymentMethodCard(method)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func paymentMethodCard(_ method: PaymentMethod) -> some View {
        let isSelected = paymentMethod == method
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) { paymentMethod = method }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.sweeplyNavy : Color.sweeplyBorder.opacity(0.35))
                        .frame(width: 42, height: 42)
                    Image(systemName: method.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.sweeplyTextSub)
                }
                Text(method.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.sweeplyNavy : Color.sweeplyTextSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.sweeplyNavy.opacity(0.07) : Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.sweeplyNavy.opacity(0.4) : Color.sweeplyBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Summary

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepHeader(
                title: "All set! Here's the summary",
                subtitle: "Review before saving. You can edit this at any time from the member profile."
            )

            VStack(spacing: 0) {
                summaryRow(icon: "briefcase.fill", label: "Pay Type", value: selectedPayType.displayName)
                Divider().padding(.leading, 54)

                if selectedPayType == .perJob {
                    let active = standardServices.filter { (serviceRates[$0.rawValue] ?? 0) > 0 }
                    summaryRow(
                        icon: "dollarsign.circle.fill",
                        label: "Rates",
                        value: active.isEmpty ? "None set" : "\(active.count) service\(active.count == 1 ? "" : "s")"
                    )
                    if !active.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(active, id: \.rawValue) { svc in
                                HStack {
                                    Text(svc.rawValue)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                    Spacer()
                                    Text((serviceRates[svc.rawValue] ?? 0).currency)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyNavy)
                                }
                            }
                        }
                        .padding(.horizontal, 54)
                        .padding(.bottom, 12)
                    }
                } else {
                    summaryRow(
                        icon: "dollarsign.circle.fill",
                        label: "Amount",
                        value: "\((Double(flatAmount) ?? 0).currency) \(selectedPayType == .custom ? "" : selectedPayType.displayName.lowercased())"
                    )
                }

                Divider().padding(.leading, 54)
                if selectedPayType == .perWeek {
                    summaryRow(icon: "calendar", label: "Pay Day", value: weekdayFullName(payDay))
                    Divider().padding(.leading, 54)
                }
                summaryRow(icon: paymentMethod.icon, label: "Via", value: paymentMethod.rawValue)
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 24)
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.sweeplyNavy.opacity(0.08)).frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func weekdayFullName(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[max(0, min(6, weekday - 1))]
    }

    // MARK: - Shared UI

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.sweeplyNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        isSaving = true
        let amount = selectedPayType == .perJob ? 0 : (Double(flatAmount) ?? 0)
        let rates  = selectedPayType == .perJob ? serviceRates.filter { $0.value > 0 } : [:]
        let ok = await teamStore.updatePayRate(
            id: member.id,
            rateType: selectedPayType,
            amount: amount,
            enabled: true,
            payDay: selectedPayType == .perWeek ? payDay : nil,
            serviceRates: rates
        )
        isSaving = false
        if ok {
            // Persist payment method to UserDefaults
            let key = "memberPayMethod_\(member.id.uuidString)"
            UserDefaults.standard.set(paymentMethod.rawValue, forKey: key)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}
