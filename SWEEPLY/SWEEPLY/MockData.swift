import Foundation

// MARK: - Mock Data
enum MockData {

    static let profile = UserProfile(
        id: UUID(),
        fullName: "João Leite",
        businessName: "Sweeply Cleaning Co.",
        email: "joao@sweeply.com",
        phone: "+1 (305) 555-0192",
        settings: AppSettings(
            street: "123 Ocean Drive",
            city: "Miami",
            state: "FL",
            zip: "33139",
            services: [
                BusinessService(name: "Standard Clean", price: 150),
                BusinessService(name: "Deep Clean", price: 280),
                BusinessService(name: "Office/Commercial", price: 350)
            ],
            defaultRate: 150,
            defaultDuration: 2.0,
            taxRate: 7.0,
            paymentTerms: 14
        )
    )

    static let clients: [Client] = [
        Client(id: UUID(), name: "Sarah Mitchell",  email: "sarah.m@email.com",    phone: "305-555-0101", address: "142 Coral Way",       city: "Miami",       state: "FL", zip: "33145", preferredService: .standard,        entryInstructions: "Key under the front mat.",          notes: "Has 2 dogs. Key under mat."),
        Client(id: UUID(), name: "James Thornton",  email: "j.thornton@email.com", phone: "305-555-0182", address: "88 Brickell Ave",     city: "Miami",       state: "FL", zip: "33131", preferredService: .deep,             entryInstructions: "Call on arrival.",                  notes: "Prefers afternoon slots."),
        Client(id: UUID(), name: "Maria Gonzalez",  email: "maria.g@email.com",    phone: "786-555-0243", address: "2201 Collins Ave",    city: "Miami Beach", state: "FL", zip: "33139", preferredService: .standard,        entryInstructions: "Doorman will let you up.",          notes: "Allergy to citrus products."),
        Client(id: UUID(), name: "David Park",      email: "dpark@email.com",      phone: "305-555-0364", address: "505 Brickell Key Dr", city: "Miami",       state: "FL", zip: "33131", preferredService: .office,           entryInstructions: "Concierge desk — ask for access.",  notes: "Concierge access required."),
        Client(id: UUID(), name: "Olivia Bennett",  email: "o.bennett@email.com",  phone: "786-555-0415", address: "19 Star Island Dr",   city: "Miami Beach", state: "FL", zip: "33109", preferredService: .deep,             entryInstructions: "Gate code: 4821.",                  notes: "Weekly recurring — biweekly deep clean."),
    ]

    static func makeJobs() -> [Job] {
        let c = clients
        let today = Calendar.current.startOfDay(for: Date())
        let cal   = Calendar.current

        return [
            Job(id: UUID(), clientId: c[0].id, clientName: c[0].name, serviceType: .standard,
                date: cal.date(byAdding: .hour, value: 8, to: today)!,
                duration: 2.5, price: 180, status: .scheduled,
                address: c[0].address, isRecurring: true),

            Job(id: UUID(), clientId: c[1].id, clientName: c[1].name, serviceType: .deep,
                date: cal.date(byAdding: .hour, value: 11, to: today)!,
                duration: 4, price: 320, status: .scheduled,
                address: c[1].address, isRecurring: false),

            Job(id: UUID(), clientId: c[2].id, clientName: c[2].name, serviceType: .standard,
                date: cal.date(byAdding: .hour, value: 14, to: today)!,
                duration: 2, price: 160, status: .inProgress,
                address: c[2].address, isRecurring: true),

            Job(id: UUID(), clientId: c[3].id, clientName: c[3].name, serviceType: .office,
                date: cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: .hour, value: 9, to: today)!)!,
                duration: 3, price: 240, status: .scheduled,
                address: c[3].address, isRecurring: true),

            Job(id: UUID(), clientId: c[4].id, clientName: c[4].name, serviceType: .deep,
                date: cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .hour, value: 10, to: today)!)!,
                duration: 4, price: 320, status: .completed,
                address: c[4].address, isRecurring: false),

            Job(id: UUID(), clientId: c[0].id, clientName: c[0].name, serviceType: .standard,
                date: cal.date(byAdding: .day, value: -3, to: cal.date(byAdding: .hour, value: 8, to: today)!)!,
                duration: 2.5, price: 180, status: .completed,
                address: c[0].address, isRecurring: true),
        ]
    }

    static func makeInvoices() -> [Invoice] {
        let c = clients
        let cal = Calendar.current
        let today = Date()

        return [
            Invoice(id: UUID(), clientId: c[0].id, clientName: c[0].name,
                    amount: 180, status: .paid,
                    createdAt: cal.date(byAdding: .day, value: -14, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value:  -7, to: today)!,
                    invoiceNumber: "INV-0041"),
            Invoice(id: UUID(), clientId: c[1].id, clientName: c[1].name,
                    amount: 320, status: .unpaid,
                    createdAt: cal.date(byAdding: .day, value: -7, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value:  7, to: today)!,
                    invoiceNumber: "INV-0042"),
            Invoice(id: UUID(), clientId: c[2].id, clientName: c[2].name,
                    amount: 160, status: .overdue,
                    createdAt: cal.date(byAdding: .day, value: -21, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value:  -7, to: today)!,
                    invoiceNumber: "INV-0039"),
            Invoice(id: UUID(), clientId: c[3].id, clientName: c[3].name,
                    amount: 240, status: .unpaid,
                    createdAt: cal.date(byAdding: .day, value: -3, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value: 11, to: today)!,
                    invoiceNumber: "INV-0043"),
            Invoice(id: UUID(), clientId: c[4].id, clientName: c[4].name,
                    amount: 320, status: .paid,
                    createdAt: cal.date(byAdding: .day, value: -10, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value:  -3, to: today)!,
                    invoiceNumber: "INV-0040"),
        ]
    }

    static let weeklyRevenue: [WeeklyRevenue] = [
        WeeklyRevenue(day: "Mon", amount: 340),
        WeeklyRevenue(day: "Tue", amount: 520),
        WeeklyRevenue(day: "Wed", amount: 180),
        WeeklyRevenue(day: "Thu", amount: 680),
        WeeklyRevenue(day: "Fri", amount: 440),
        WeeklyRevenue(day: "Sat", amount: 320),
        WeeklyRevenue(day: "Sun", amount: 0),
    ]

    static let monthlyRevenue: [WeeklyRevenue] = [
        WeeklyRevenue(day: "W1", amount: 1240),
        WeeklyRevenue(day: "W2", amount: 1860),
        WeeklyRevenue(day: "W3", amount: 980),
        WeeklyRevenue(day: "W4", amount: 1520),
    ]

    static func makeAllInvoices() -> [Invoice] {
        let base = makeInvoices()
        let c = clients
        let cal = Calendar.current
        let today = Date()

        let extra: [Invoice] = [
            Invoice(id: UUID(), clientId: c[1].id, clientName: c[1].name,
                    amount: 280, status: .paid,
                    createdAt: cal.date(byAdding: .day, value: -28, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value: -21, to: today)!,
                    invoiceNumber: "INV-0038"),
            Invoice(id: UUID(), clientId: c[2].id, clientName: c[2].name,
                    amount: 160, status: .unpaid,
                    createdAt: cal.date(byAdding: .day, value: -2, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value: 12, to: today)!,
                    invoiceNumber: "INV-0044"),
            Invoice(id: UUID(), clientId: c[4].id, clientName: c[4].name,
                    amount: 480, status: .overdue,
                    createdAt: cal.date(byAdding: .day, value: -30, to: today)!,
                    dueDate:   cal.date(byAdding: .day, value: -16, to: today)!,
                    invoiceNumber: "INV-0037"),
        ]
        return base + extra
    }
}
