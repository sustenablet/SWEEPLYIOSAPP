import SwiftUI

struct NewJobForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(ProfileStore.self)  private var profileStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(TeamStore.self)     private var teamStore

    @State private var selectedClientId: UUID? = nil

    init(preselectClient: Client? = nil) {
        _selectedClientId = State(initialValue: preselectClient?.id)
    }
    @State private var serviceType: ServiceType = .standard
    @State private var date = Self.defaultJobDate()
    @State private var price: String = ""
    @State private var duration: String = ""
    @State private var recurrence: RecurrenceFrequency = .once
    @State private var customInterval: String = "7"
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 30)
    @State private var showEndDatePicker = false
    @State private var isSaving = false
    @State private var showValidationErrors = false
    @State private var saveError: String?
    @State private var selectedExtras: [BusinessService] = []
    @State private var showExtrasPicker = false
    @State private var baseServicePrice: Double = 0
    @State private var assignedMemberId: UUID? = nil

    /// Default to the next full hour, at minimum 1 hour from now.
    private static func defaultJobDate() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date())
        components.hour = (components.hour ?? 0) + 1
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date().addingTimeInterval(3600)
    }

    private var fallbackSettings: AppSettings {
        var settings = AppSettings()
        settings.services = AppSettings.defaultServiceCatalog
        settings.defaultRate = 120
        settings.defaultDuration = 2
        return settings
    }

    private var serviceCatalog: [BusinessService] {
        let settings = profileStore.profile?.settings ?? fallbackSettings
        return settings.hydratedServiceCatalog.filter { !$0.isAddon }
    }

    private var extrasCatalog: [BusinessService] {
        let settings = profileStore.profile?.settings ?? fallbackSettings
        return settings.hydratedServiceCatalog.filter { $0.isAddon }
    }

    private var extrasTotalPrice: Double {
        selectedExtras.reduce(0) { $0 + $1.price }
    }

    private var activeCleaners: [TeamMember] {
        teamStore.members.filter { $0.role == .member && $0.status == .active }
    }

    private var assignedMember: TeamMember? {
        guard let id = assignedMemberId else { return nil }
        return activeCleaners.first { $0.id == id }
    }

    private var selectedServiceLabel: String {
        if let service = selectedService {
            return "\(service.name) · \(service.price.currency)"
        }
        return serviceType.rawValue
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if selectedClientId == nil { errors.append("Select a client") }
        if (Double(price) ?? 0) <= 0 { errors.append("Enter a price greater than $0") }
        // Allow up to 5 minutes in the past to avoid race between form open and submit
        if date < Date().addingTimeInterval(-300) { errors.append("Job date must be in the future") }
        return errors
    }

    private var conflictingJob: Job? {
        let durationSecs = (Double(duration) ?? 2.0) * 3600.0
        let newStart = date
        let newEnd   = date.addingTimeInterval(durationSecs)
        return jobsStore.jobs.first { existing in
            guard Calendar.current.isDate(existing.date, inSameDayAs: newStart) else { return false }
            let existingEnd = existing.date.addingTimeInterval(existing.duration * 3600.0)
            return newStart < existingEnd && existing.date < newEnd
        }
    }

    private var selectedService: BusinessService? {
        serviceCatalog.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(serviceType.rawValue) == .orderedSame
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Schedule a Job".translated())
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Save error banner
                    if let saveError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sweeplyDestructive)
                            Text(saveError)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.sweeplyDestructive.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // 1. Job Details
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "JOB DETAILS")
                        
                        // Client Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client *".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(showValidationErrors && selectedClientId == nil ? Color.sweeplyDestructive : Color.sweeplyTextSub)
                            Menu {
                                ForEach(clientsStore.clients) { client in
                                    Button(client.name) {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedClientId = client.id
                                    }
                                }
                            } label: {
                                PickerButton(
                                    label: selectedClient?.name ?? "Select client",
                                    isSelected: selectedClientId != nil
                                )
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(showValidationErrors && selectedClientId == nil ? Color.sweeplyDestructive : Color.clear, lineWidth: 1.5)
                            )
                            if showValidationErrors && selectedClientId == nil {
                                Text("Please select a client".translated())
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.sweeplyDestructive)
                                    .padding(.top, 2)
                            }
                        }
                        
                        // Service Type Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Service Type *".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                            Menu {
                                ForEach(serviceCatalog) { service in
                                    Button("\(service.name) · \(service.price.currency)") {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        serviceType = ServiceType(rawValue: service.name) ?? .custom(service.name)
                                        applyPricingHierarchy()
                                    }
                                }
                            } label: {
                                PickerButton(
                                    label: selectedServiceLabel,
                                    isSelected: true
                                )
                            }
                        }
                    }
                    
                    // 2. Schedule
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "SCHEDULE")
                        
                        HStack(spacing: 16) {
                            // Date
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date *".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(showValidationErrors && date < Date() ? Color.sweeplyDestructive : Color.sweeplyTextSub)
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(showValidationErrors && date < Date() ? Color.sweeplyDestructive : Color.sweeplyBorder, lineWidth: 1))
                            }

                            // Time
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Time *".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }
                        }
                        if showValidationErrors && date < Date() {
                            Text("Job date must be in the future".translated())
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sweeplyDestructive)
                                .padding(.top, 2)
                        }
                        if let conflict = conflictingJob {
                            let conflictEnd = conflict.date.addingTimeInterval(conflict.duration * 3600)
                            let fmt: DateFormatter = {
                                let f = DateFormatter()
                                f.timeStyle = .short
                                f.dateStyle = .none
                                return f
                            }()
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyWarning)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Time overlap with \(conflict.clientName)'s job (\(fmt.string(from: conflict.date)) – \(fmt.string(from: conflictEnd)))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("You can still schedule this job.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.sweeplyWarning.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.sweeplyWarning.opacity(0.35), lineWidth: 1)
                            )
                            .animation(.easeInOut(duration: 0.2), value: conflict.id)
                        }
                    }
                    
                    // 3. Pricing
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "PRICING")
                        
                        HStack(spacing: 16) {
                            // Duration
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Duration (hrs)".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                                TextField("2", text: $duration)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }

                            // Price
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Price ($)".translated()).font(.system(size: 13, weight: .medium)).foregroundStyle(showValidationErrors && (Double(price) ?? 0) <= 0 ? Color.sweeplyDestructive : Color.sweeplyTextSub)
                                TextField("120.00", text: $price)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(showValidationErrors && (Double(price) ?? 0) <= 0 ? Color.sweeplyDestructive : Color.sweeplyBorder, lineWidth: 1))
                                if showValidationErrors && (Double(price) ?? 0) <= 0 {
                                    Text("Enter a price greater than $0".translated())
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.sweeplyDestructive)
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }
                    
                    // 4. Recurrence
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "RECURRENCE")

                        // Chip-style frequency picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            recurrence = freq
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: freq.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(freq.displayName)
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(recurrence == freq ? Color.sweeplyNavy : Color.sweeplySurface)
                                        .foregroundStyle(recurrence == freq ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(
                                                recurrence == freq ? Color.sweeplyNavy : Color.sweeplyBorder,
                                                lineWidth: 1
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                            .padding(.vertical, 2)
                        }

                        if recurrence != .once {
                            VStack(alignment: .leading, spacing: 16) {
                                if recurrence == .custom {
                                    HStack(spacing: 8) {
                                        Text("Every".translated())
                                            .font(.system(size: 14))
                                        TextField("7", text: $customInterval)
                                            .keyboardType(.numberPad)
                                            .frame(width: 40)
                                            .multilineTextAlignment(.center)
                                            .padding(6)
                                            .background(Color.sweeplyBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sweeplyBorder, lineWidth: 1))
                                        Text("days")
                                            .font(.system(size: 14))
                                        Spacer()
                                    }
                                }

                                // Next occurrence preview
                                let nextDates = generateNextOccurrences(from: date, recurrence: recurrence, interval: Int(customInterval) ?? 7, count: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next occurrences".translated())
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                    ForEach(nextDates, id: \.self) { nextDate in
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                                            Text(nextDate.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))

                                Toggle(isOn: $showEndDatePicker) {
                                    Text("Set end date".translated())
                                        .font(.system(size: 14))
                                }
                                .tint(Color.sweeplyNavy)

                                if showEndDatePicker {
                                    DatePicker("Repeat until", selection: $endDate, displayedComponents: .date)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(16)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    // 5. Extras
                    if !extrasCatalog.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "EXTRAS (OPTIONAL)")

                            if !selectedExtras.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(selectedExtras) { extra in
                                        HStack(spacing: 10) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color.sweeplyAccent)
                                                .frame(width: 20)
                                            Text(extra.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Color.sweeplyNavy)
                                            Spacer()
                                            Text(extra.price.currency)
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Color.sweeplyNavy)
                                            Button {
                                                selectedExtras.removeAll { $0.id == extra.id }
                                                recalculateTotalPrice()
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.sweeplySurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
                                    }
                                }
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showExtrasPicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Add Extra".translated())
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(Color.sweeplyAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.sweeplyAccent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // 4. Assign Cleaner (only if there are active cleaners)
                    if !activeCleaners.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "ASSIGN CLEANER")

                            Menu {
                                Button {
                                    assignedMemberId = nil
                                } label: {
                                    Label("Unassigned".translated(), systemImage: "person.slash")
                                }
                                Divider()
                                ForEach(activeCleaners) { cleaner in
                                    Button {
                                        assignedMemberId = cleaner.id
                                    } label: {
                                        Label(cleaner.name, systemImage: "person.fill")
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(assignedMember != nil ? Color.sweeplyAccent.opacity(0.15) : Color.sweeplyBorder.opacity(0.4))
                                            .frame(width: 32, height: 32)
                                        if let m = assignedMember {
                                            Text(m.initials)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color.sweeplyAccent)
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                        }
                                    }
                                    Text(assignedMember?.name ?? "Unassigned")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(assignedMember != nil ? Color.sweeplyNavy : Color.sweeplyTextSub)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.sweeplySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .sheet(isPresented: $showExtrasPicker) {
                ExtrasPickerSheet(catalog: extrasCatalog, selected: selectedExtras) { picked in
                    selectedExtras = picked
                    recalculateTotalPrice()
                }
            }

            // Footer Actions
            HStack(spacing: 12) {
                Button("Cancel".translated()) { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                
                Button {
                    showValidationErrors = true
                    guard validationErrors.isEmpty else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }
                    Task { await saveJob() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white).padding(.trailing, 8) }
                        Text(isSaving ? "Scheduling..." : conflictingJob != nil ? "Schedule Anyway" : "Schedule Job")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isSaving ? Color.sweeplyNavy.opacity(0.4) : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.sweeplyNavy.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .disabled(isSaving)
            }
            .padding(24)
            .background(Color.sweeplySurface)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done".translated()) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            }
        }
        .background(Color.sweeplySurface.ignoresSafeArea())
        .onAppear {
            if selectedService == nil, let firstService = serviceCatalog.first {
                serviceType = ServiceType(rawValue: firstService.name) ?? .custom(firstService.name)
            }
            applyPricingHierarchy()
        }
    }

    private var selectedClient: Client? {
        clientsStore.clients.first { $0.id == selectedClientId }
    }

    private func applyPricingHierarchy() {
        let settings = profileStore.profile?.settings ?? fallbackSettings

        if let service = selectedService {
            baseServicePrice = service.price
            duration = "\(Int(settings.defaultDuration > 0 ? settings.defaultDuration : 2))"
        } else {
            baseServicePrice = settings.defaultRate > 0 ? settings.defaultRate : 120
            duration = "\(Int(settings.defaultDuration > 0 ? settings.defaultDuration : 2))"
        }
        recalculateTotalPrice()
    }

    private func recalculateTotalPrice() {
        let total = baseServicePrice + extrasTotalPrice
        price = total == floor(total) ? "\(Int(total))" : String(format: "%.2f", total)
    }

    private func generateNextOccurrences(from startDate: Date, recurrence: RecurrenceFrequency, interval: Int, count: Int) -> [Date] {
        var dates: [Date] = []
        var current = startDate
        let calendar = Calendar.current
        for _ in 0..<count {
            switch recurrence {
            case .once:
                break
            case .weekly:
                current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
            case .biweekly:
                current = calendar.date(byAdding: .weekOfYear, value: 2, to: current) ?? current
            case .monthly:
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            case .custom:
                current = calendar.date(byAdding: .day, value: interval, to: current) ?? current
            }
            dates.append(current)
        }
        return dates
    }

    private func saveJob() async {
        guard let client = selectedClient, let userId = session.userId else { return }
        isSaving = true
        saveError = nil

        let finalPrice    = Double(price) ?? 120.0
        let finalDuration = Double(duration) ?? 2.0
        let success: Bool

        if recurrence == .once {
            let newJob = Job(
                id: UUID(),
                userId: userId,
                clientId: client.id,
                clientName: client.name,
                serviceType: serviceType,
                date: date,
                duration: finalDuration,
                price: finalPrice,
                status: .scheduled,
                address: client.address,
                isRecurring: false,
                assignedMemberId: assignedMemberId,
                assignedMemberName: assignedMember?.name
            )
            success = await jobsStore.insert(newJob, userId: userId)
            // Notify assigned member that a new job has been given to them
            if success, let cleanerUserId = assignedMember?.cleanerUserId {
                let dateStr = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                await NotificationHelper.insert(
                    userId: cleanerUserId,
                    title: "New Job Assigned",
                    message: "\(serviceType.rawValue) at \(client.name) — \(dateStr). \(finalPrice.currency)",
                    kind: "jobs"
                )
            }
        } else {
            let rule = RecurrenceRule(
                id: UUID(),
                userId: userId,
                clientId: client.id,
                serviceType: serviceType,
                frequency: recurrence,
                intervalDays: Int(customInterval) ?? 7,
                startDate: date,
                endDate: showEndDatePicker ? endDate : nil,
                price: finalPrice,
                durationHours: finalDuration
            )
            success = await jobsStore.insertRecurring(rule: rule, clientName: client.name, address: client.address)
        }

        isSaving = false

        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            saveError = jobsStore.lastError ?? "Failed to save the job. Please try again."
        }
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            Rectangle()
                .fill(Color.sweeplyBorder)
                .frame(height: 1)
        }
    }
}

private struct ExtrasPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: [BusinessService]
    let selected: [BusinessService]
    let onConfirm: ([BusinessService]) -> Void

    @State private var localSelected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(catalog) { extra in
                        Button {
                            if localSelected.contains(extra.id) {
                                localSelected.remove(extra.id)
                            } else {
                                localSelected.insert(extra.id)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: localSelected.contains(extra.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(localSelected.contains(extra.id) ? Color.sweeplyWarning : Color.sweeplyBorder)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(extra.name)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.sweeplyNavy)
                                }
                                Spacer()
                                Text(extra.price.currency)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("JOB EXTRAS".translated())
                }
            }
            .navigationTitle("Add Extras".translated())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".translated()) { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".translated()) {
                        let picked = catalog.filter { localSelected.contains($0.id) }
                        onConfirm(picked)
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            localSelected = Set(selected.map(\.id))
        }
    }
}

private struct PickerButton: View {
    let label: String
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? Color.primary : Color.sweeplyTextSub)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }
}

