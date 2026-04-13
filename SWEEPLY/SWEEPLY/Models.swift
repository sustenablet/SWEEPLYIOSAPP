import Foundation

// MARK: - Enums

enum JobStatus: String, CaseIterable, Codable {
    case scheduled   = "Scheduled"
    case inProgress  = "In Progress"
    case completed   = "Completed"
    case cancelled   = "Cancelled"
}

enum InvoiceStatus: String, CaseIterable, Codable {
    case paid    = "Paid"
    case unpaid  = "Unpaid"
    case overdue = "Overdue"
}

enum ServiceType: RawRepresentable, Hashable, CaseIterable, Codable {
    case standard
    case deep
    case moveInOut
    case postConstruction
    case office
    case custom(String)

    static var allCases: [ServiceType] {
        [.standard, .deep, .moveInOut, .postConstruction, .office]
    }

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        switch trimmed {
        case "Standard Clean":
            self = .standard
        case "Deep Clean":
            self = .deep
        case "Move In/Out":
            self = .moveInOut
        case "Post Construction":
            self = .postConstruction
        case "Office Clean":
            self = .office
        default:
            self = .custom(trimmed)
        }
    }

    var rawValue: String {
        switch self {
        case .standard:
            return "Standard Clean"
        case .deep:
            return "Deep Clean"
        case .moveInOut:
            return "Move In/Out"
        case .postConstruction:
            return "Post Construction"
        case .office:
            return "Office Clean"
        case .custom(let name):
            return name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ServiceType(rawValue: value) ?? .custom(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
    static let defaultServiceCatalog: [BusinessService] = [
        BusinessService(name: ServiceType.standard.rawValue, price: 150),
        BusinessService(name: ServiceType.deep.rawValue, price: 280),
        BusinessService(name: ServiceType.moveInOut.rawValue, price: 320),
        BusinessService(name: ServiceType.postConstruction.rawValue, price: 380),
        BusinessService(name: ServiceType.office.rawValue, price: 350),
        BusinessService(name: "Clean Windows", price: 40),
        BusinessService(name: "Do Laundry", price: 30)
    ]

    var hydratedServiceCatalog: [BusinessService] {
        services.isEmpty ? Self.defaultServiceCatalog : services
    }

    var availableServiceTypes: [ServiceType] {
        let mapped = hydratedServiceCatalog.compactMap { ServiceType(rawValue: $0.name) }
        return mapped.isEmpty ? ServiceType.allCases : mapped
    }

    func service(for serviceType: ServiceType?) -> BusinessService? {
        guard let serviceType else { return nil }
        return hydratedServiceCatalog.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(serviceType.rawValue) == .orderedSame
        }
    }
}

struct BusinessService: Identifiable, Codable {
    var id = UUID()
    var name: String
    var price: Double
    var isAddon: Bool = false  // "Extra Cost" add-ons shown separately in the catalog
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
    var latitude: Double?
    var longitude: Double?
    var isActive: Bool = true

    init(id: UUID, name: String, email: String, phone: String, address: String, city: String, state: String, zip: String, preferredService: ServiceType?, entryInstructions: String, notes: String, latitude: Double? = nil, longitude: Double? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.preferredService = preferredService
        self.entryInstructions = entryInstructions
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.isActive = isActive
    }

    // Linker compatibility for previous builds
    init(id: UUID, name: String, email: String, phone: String, address: String, city: String, state: String, zip: String, preferredService: ServiceType?, entryInstructions: String, notes: String, latitude: Double?, longitude: Double?) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.preferredService = preferredService
        self.entryInstructions = entryInstructions
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.isActive = true
    }
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

    var displayName: String {
        switch self {
        case .once:     return "Does not repeat"
        case .weekly:   return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly:  return "Every month"
        case .custom:   return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .once:     return "minus"
        case .weekly:   return "repeat"
        case .biweekly: return "repeat.circle"
        case .monthly:  return "calendar.badge.clock"
        case .custom:   return "slider.horizontal.3"
        }
    }
}

struct InvoiceLineItem: Identifiable, Codable {
    var id = UUID()
    var description: String
    var quantity: Double
    var unitPrice: Double

    var total: Double { quantity * unitPrice }
}

struct Invoice: Identifiable {
    let id: UUID
    var clientId: UUID
    var clientName: String
    var amount: Double          // always equals subtotal; kept for backward compat with all views
    var status: InvoiceStatus
    var createdAt: Date
    var dueDate: Date
    var invoiceNumber: String
    var notes: String = ""
    var lineItems: [InvoiceLineItem] = []

    var subtotal: Double {
        lineItems.isEmpty ? amount : lineItems.reduce(0) { $0 + $1.total }
    }

    var total: Double { subtotal }
}

struct WeeklyRevenue: Identifiable {
    let id = UUID()
    var day: String
    var amount: Double
}

// MARK: - Team

enum TeamRole: String, CaseIterable, Codable {
    case owner  = "owner"
    case member = "member"

    var displayName: String {
        switch self {
        case .owner:  return "Owner"
        case .member: return "Cleaner"
        }
    }
}

enum TeamMemberStatus: String, Codable {
    case invited = "invited"
    case active  = "active"

    var displayName: String {
        switch self {
        case .invited: return "Invited"
        case .active:  return "Active"
        }
    }
}

struct TeamMember: Identifiable, Codable {
    var id      = UUID()
    var ownerId : UUID
    var name    : String
    var email   : String
    var role    : TeamRole
    var status  : TeamMemberStatus
    var addedAt : Date

    var initials: String {
        name.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }
}
