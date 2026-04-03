import SwiftUI

struct NewJobForm: View {
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Job")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(24)
            
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Client Choice
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CLIENT").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        Menu {
                            ForEach(clientsStore.clients) { client in
                                Button(client.name) { selectedClientId = client.id }
                            }
                        } label: {
                            HStack {
                                Text(selectedClient?.name ?? "Select Client...")
                                    .foregroundStyle(selectedClientId == nil ? Color.sweeplyTextSub : .primary)
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 12))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // 2. Service & Scheduling
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SERVICE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                            Menu {
                                ForEach(ServiceType.allCases, id: \.self) { type in
                                    Button(type.rawValue) { 
                                        serviceType = type 
                                        applyPricingHierarchy()
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(serviceType.rawValue)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.system(size: 12))
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DATE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIME").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PRICE ($)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                            TextField("0.00", text: $price)
                                .keyboardType(.decimalPad)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.sweeplyBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // 3. Recurrence
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECURRENCE").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sweeplyTextSub)
                        
                        Picker("", selection: $recurrence) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                Text(freq.rawValue.capitalized).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)

                        if recurrence != .once {
                            VStack(spacing: 16) {
                                if recurrence == .custom {
                                    HStack {
                                        Text("Every").font(.system(size: 14))
                                        TextField("7", text: $customInterval)
                                            .keyboardType(.numberPad)
                                            .frame(width: 40)
                                            .multilineTextAlignment(.center)
                                            .padding(6)
                                            .background(Color.sweeplyBackground)
                                            .border(Color.sweeplyBorder)
                                        Text("Days").font(.system(size: 14))
                                        Spacer()
                                    }
                                }
                                
                                Toggle(isOn: $showEndDatePicker) {
                                    Text("Set End Date").font(.system(size: 14))
                                }
                                .tint(Color.sweeplyNavy)

                                if showEndDatePicker {
                                    DatePicker("Repeat Until", selection: $endDate, displayedComponents: .date)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(16)
                            .background(Color.sweeplyBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // Save Button
            Button {
                Task { await saveJob() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white).padding(.trailing, 8) }
                    Text(isSaving ? "Creating..." : "Create Job")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedClientId == nil || isSaving ? Color.sweeplyBorder : Color.sweeplyNavy)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedClientId == nil || isSaving)
            .padding(24)
        }
        .background(Color.sweeplySurface)
        .onAppear {
            applyPricingHierarchy()
        }
    }

    private var selectedClient: Client? {
        clientsStore.clients.first { $0.id == selectedClientId }
    }

    private func applyPricingHierarchy() {
        guard let p = profileStore.profile else {
            price = "120"
            duration = "2"
            return
        }
        
        // 1. Search in Catalog
        if let service = p.settings.services.first(where: { $0.name.lowercased() == serviceType.rawValue.lowercased() }) {
            price = "\(Int(service.price))"
            duration = "\(Int(p.settings.defaultDuration))"
        } else {
            // 2. Business Default
            let rate = p.settings.defaultRate > 0 ? p.settings.defaultRate : 120
            price = "\(Int(rate))"
            duration = "\(Int(p.settings.defaultDuration > 0 ? p.settings.defaultDuration : 2))"
        }
    }

    private func saveJob() async {
        guard let client = selectedClient, let p = profileStore.profile else { return }
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
            _ = await jobsStore.insert(newJob, userId: p.id)
        } else {
            let rule = RecurrenceRule(
                id: UUID(),
                userId: p.id,
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
        dismiss()
    }
}
