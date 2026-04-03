import Foundation

// MARK: - Enums

enum JobStatus: String, CaseIterable {
    case scheduled   = "Scheduled"
    case inProgress  = "In Progress"
    case completed   = "Completed"
    case cancelled   = "Cancelled"
}

enum InvoiceStatus: String, CaseIterable {
    case paid    = "Paid"
    case unpaid  = "Unpaid"
    case overdue = "Overdue"
}

enum ServiceType: String, CaseIterable {
    case standard    = "Standard Clean"
    case deep        = "Deep Clean"
    case moveInOut   = "Move In/Out"
    case postConstruction = "Post Construction"
    case office      = "Office Clean"
}

// MARK: - Models

struct UserProfile: Identifiable {
    let id: UUID
    var fullName: String
    var businessName: String
    var email: String
    var phone: String
    var settings: AppSettings
}

struct AppSettings: Codable {
    var street: String = ""
    var city: String = ""
    var state: String = ""
    var zip: String = ""
    var services: [BusinessService] = []
    var defaultRate: Double = 0
    var defaultDuration: Double = 2.0
    var taxRate: Double = 0
    var paymentTerms: Int = 14
    var darkMode: Bool = false
}

struct BusinessService: Identifiable, Codable {
    var id = UUID()
    var name: String
    var price: Double
}

struct Client: Identifiable {
    let id: UUID
    var name: String
    var email: String
    var phone: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var preferredService: ServiceType?
    var entryInstructions: String
    var notes: String
}

struct Job: Identifiable, Codable {
    let id: UUID
    var clientId: UUID
    var clientName: String
    var serviceType: ServiceType
    var date: Date
    var duration: Double
    var price: Double
    var status: JobStatus
    var address: String
    var isRecurring: Bool
    var recurrenceRuleId: UUID? = nil
}

struct RecurrenceRule: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var clientId: UUID
    var serviceType: ServiceType
    var frequency: RecurrenceFrequency
    var intervalDays: Int
    var startDate: Date
    var endDate: Date?
    var price: Double
    var durationHours: Double
}

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case once      = "once"
    case weekly    = "weekly"
    case biweekly  = "biweekly"
    case monthly   = "monthly"
    case custom    = "custom"
}

struct Invoice: Identifiable {
    let id: UUID
    var clientId: UUID
    var clientName: String
    var amount: Double
    var status: InvoiceStatus
    var createdAt: Date
    var dueDate: Date
    var invoiceNumber: String
}

struct WeeklyRevenue: Identifiable {
    let id = UUID()
    var day: String
    var amount: Double
}
