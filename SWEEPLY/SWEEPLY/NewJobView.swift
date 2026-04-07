import SwiftUI

struct NewJobForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(ProfileStore.self)  private var profileStore
    @Environment(JobsStore.self)     private var jobsStore

    @State private var selectedClientId: UUID? = nil
    @State private var serviceType: ServiceType = .standard
    @State private var date = Date()
    @State private var price: String = ""
    @State private var duration: String = ""
    @State private var recurrence: RecurrenceFrequency = .once
    @State private var customInterval: String = "7"
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 30)
    @State private var showEndDatePicker = false
    @State private var isSaving = false

    private var fallbackSettings: AppSettings {
        var settings = AppSettings()
        settings.services = AppSettings.defaultServiceCatalog
        settings.defaultRate = 120
        settings.defaultDuration = 2
        return settings
    }

    private var serviceCatalog: [BusinessService] {
        let settings = profileStore.profile?.settings ?? fallbackSettings
        return settings.hydratedServiceCatalog
    }

    private var selectedServiceLabel: String {
        if let service = selectedService {
            return "\(service.name) · \(service.price.currency)"
        }
        return serviceType.rawValue
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
                Text("Schedule a Job")
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
                    // 1. Job Details
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "JOB DETAILS")
                        
                        // Client Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client *").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
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
                        }
                        
                        // Service Type Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Service Type *").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
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
                                Text("Date *").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                            }
                            
                            // Time
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Time *").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
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
                    }
                    
                    // 3. Pricing
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "PRICING")
                        
                        HStack(spacing: 16) {
                            // Duration
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Duration (hrs)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
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
                                Text("Price ($)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sweeplyTextSub)
                                TextField("120.00", text: $price)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.sweeplySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
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
                                        Text("Every")
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
                                    Text("Next occurrences")
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
                                    Text("Set end date")
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            
            // Footer Actions
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.sweeplySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                
                Button {
                    Task { await saveJob() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white).padding(.trailing, 8) }
                        Text(isSaving ? "Scheduling..." : "Schedule Job")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedClientId == nil || isSaving ? Color.sweeplyNavy.opacity(0.4) : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.sweeplyNavy.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .disabled(selectedClientId == nil || isSaving)
            }
            .padding(24)
            .background(Color.sweeplySurface)
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: -5)
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
        
        // 1. Search in Catalog
        if let service = selectedService {
            price = service.price == floor(service.price) ? "\(Int(service.price))" : String(format: "%.2f", service.price)
            duration = "\(Int(settings.defaultDuration > 0 ? settings.defaultDuration : 2))"
        } else {
            // 2. Business Default
            let rate = settings.defaultRate > 0 ? settings.defaultRate : 120
            price = "\(Int(rate))"
            duration = "\(Int(settings.defaultDuration > 0 ? settings.defaultDuration : 2))"
        }
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
        
        let finalPrice = Double(price) ?? 120.0
        let finalDuration = Double(duration) ?? 2.0
        
        if recurrence == .once {
            let newJob = Job(
                id: UUID(),
                clientId: client.id,
                clientName: client.name,
                serviceType: serviceType,
                date: date,
                duration: finalDuration,
                price: finalPrice,
                status: .scheduled,
                address: client.address,
                isRecurring: false
            )
            _ = await jobsStore.insert(newJob, userId: userId)
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
            _ = await jobsStore.insertRecurring(rule: rule, clientName: client.name, address: client.address)
        }
        
        isSaving = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
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

