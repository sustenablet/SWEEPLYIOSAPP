import Foundation

// MARK: - Enums

enum JobStatus: String, CaseIterable, Codable, Hashable {
    case scheduled   = "Scheduled"
    case inProgress  = "In Progress"
    case completed   = "Completed"
    case cancelled   = "Cancelled"
}

enum InvoiceStatus: String, CaseIterable, Codable, Hashable {
    case paid    = "Paid"
    case unpaid  = "Unpaid"
    case overdue = "Overdue"
}

enum PaymentMethod: String, CaseIterable, Codable {
    case check   = "Check"
    case zelle  = "Zelle"
    case venmo  = "Venmo"
    case cash   = "Cash"
    case card   = "Card"
    case other  = "Other"
    
    var icon: String {
        switch self {
        case .check:  return "banknote"
        case .zelle: return "dollarsign.circle"
        case .venmo: return "v.circle"
        case .cash:  return "dollarsign.square"
        case .card:  return "creditcard"
        case .other: return "ellipsis.circle"
        }
    }
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
        BusinessService(name: "Clean Windows", price: 40, isAddon: true),
        BusinessService(name: "Do Laundry", price: 30, isAddon: true),
        BusinessService(name: "Clean Dishes", price: 15, isAddon: true),
        BusinessService(name: "Inside Fridge", price: 25, isAddon: true),
        BusinessService(name: "Inside Oven", price: 30, isAddon: true),
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
    var avatarToneRaw: String? = nil
    var isActive: Bool = true

    var avatarTone: ClientAvatarTone {
        ClientAvatarStyle.tone(
            storedRaw: avatarToneRaw,
            clientID: id,
            fallbackName: name
        )
    }

    var avatarInitials: String {
        let parts = name
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        switch parts.count {
        case 0:
            return "C"
        case 1:
            return String(parts[0].prefix(1)).uppercased()
        default:
            let first = parts.first?.prefix(1) ?? ""
            let last = parts.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        }
    }

    init(id: UUID, name: String, email: String, phone: String, address: String, city: String, state: String, zip: String, preferredService: ServiceType?, entryInstructions: String, notes: String, latitude: Double? = nil, longitude: Double? = nil, avatarToneRaw: String? = nil, isActive: Bool = true) {
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
        self.avatarToneRaw = avatarToneRaw
        self.isActive = isActive
    }

    // Linker compatibility for previous builds
    init(id: UUID, name: String, email: String, phone: String, address: String, city: String, state: String, zip: String, preferredService: ServiceType?, entryInstructions: String, notes: String, latitude: Double?, longitude: Double?, avatarToneRaw: String? = nil) {
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
        self.avatarToneRaw = avatarToneRaw
        self.isActive = true
    }
}

struct Job: Identifiable, Codable {
    let id: UUID
    var userId: UUID        // owner's auth user ID — used to filter own-business jobs vs assigned jobs
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
    var recurrenceFrequency: RecurrenceFrequency? = nil
    var assignedMemberId: UUID? = nil
    var assignedMemberName: String? = nil
    var assignedMemberIds: [UUID] = []
    var assignedMemberNames: [String] = []

    var effectiveAssignedMemberIds: [UUID] {
        if !assignedMemberIds.isEmpty { return assignedMemberIds }
        if let assignedMemberId { return [assignedMemberId] }
        return []
    }

    var effectiveAssignedMemberNames: [String] {
        if !assignedMemberNames.isEmpty { return assignedMemberNames }
        if let assignedMemberName, !assignedMemberName.isEmpty { return [assignedMemberName] }
        return []
    }

    func isAssigned(to memberId: UUID) -> Bool {
        effectiveAssignedMemberIds.contains(memberId)
    }
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
        case .once:     return "Does not repeat".translated()
        case .weekly:   return "Every week".translated()
        case .biweekly: return "Every 2 weeks".translated()
        case .monthly:  return "Every month".translated()
        case .custom:   return "Custom".translated()
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
    // Payment tracking
    var paidAmount: Double? = nil
    var paymentMethod: PaymentMethod? = nil
    var paidAt: Date? = nil

    var subtotal: Double {
        lineItems.isEmpty ? amount : lineItems.reduce(0) { $0 + $1.total }
    }

    var total: Double { subtotal }
    
    var isFullyPaid: Bool {
        guard let paid = paidAmount else { return status == .paid }
        return paid >= total
    }
}

struct WeeklyRevenue: Identifiable {
    let id = UUID()
    var day: String
    var amount: Double
}

// MARK: - Expenses

enum ExpenseCategory: String, CaseIterable, Codable {
    case supplies  = "supplies"
    case fuel      = "fuel"
    case equipment = "equipment"
    case insurance = "insurance"
    case marketing = "marketing"
    case other     = "other"

    var displayName: String {
        switch self {
        case .supplies:  return "Supplies".translated()
        case .fuel:      return "Fuel".translated()
        case .equipment: return "Equipment".translated()
        case .insurance: return "Insurance".translated()
        case .marketing: return "Marketing".translated()
        case .other:     return "Other".translated()
        }
    }

    var icon: String {
        switch self {
        case .supplies:  return "cart.fill"
        case .fuel:      return "fuelpump.fill"
        case .equipment: return "wrench.and.screwdriver.fill"
        case .insurance: return "shield.fill"
        case .marketing: return "megaphone.fill"
        case .other:     return "ellipsis.circle.fill"
        }
    }
}

struct Expense: Identifiable, Codable {
    var id       = UUID()
    var userId   : UUID
    var amount   : Double
    var category : ExpenseCategory
    var notes    : String
    var date     : Date
}

// MARK: - Team

enum TeamRole: String, CaseIterable, Codable {
    case owner  = "owner"
    case member = "member"

    var displayName: String {
        switch self {
        case .owner:  return "Owner".translated()
        case .member: return "Cleaner".translated()
        }
    }
}

enum TeamMemberStatus: String, Codable {
    case invited  = "invited"
    case active   = "active"
    case inactive = "inactive"

    var displayName: String {
        switch self {
        case .invited:  return "Invited".translated()
        case .active:   return "Active".translated()
        case .inactive: return "Inactive".translated()
        }
    }
}

enum PayRateType: String, CaseIterable, Codable {
    case perJob      = "per_job"
    case perDay     = "per_day"
    case perWeek    = "per_week"
    case custom     = "custom"

    var displayName: String {
        switch self {
        case .perJob:   return "Per Job".translated()
        case .perDay:   return "Per Day".translated()
        case .perWeek:  return "Per Week".translated()
        case .custom:   return "Custom".translated()
        }
    }
    
    var description: String {
        switch self {
        case .perJob:   return "Different rate per service type".translated()
        case .perDay:  return "$X for all jobs done that day".translated()
        case .perWeek: return "$X for all jobs done that week".translated()
        case .custom:  return "Owner enters custom amount".translated()
        }
    }
}

struct TeamMember: Identifiable, Codable {
    var id      = UUID()
    var ownerId : UUID
    var name    : String
    var email   : String
    var phone   : String = ""
    var role    : TeamRole
    var status  : TeamMemberStatus
    var addedAt : Date
    
    // Pay rate settings
    var payRateType: PayRateType = .perDay
    var payRateAmount: Double = 0
    var payRateEnabled: Bool = false
    // Which day of week to pay (Calendar weekday: 1=Sun, 2=Mon…7=Sat). Only used for .perWeek.
    var payDayOfWeek: Int? = nil
    // Per-service rates: ServiceType.rawValue → dollar amount. Only used for .perJob.
    var serviceRates: [String: Double] = [:]
    // Supabase auth user ID of the cleaner (set after they accept the invite)
    var cleanerUserId: UUID? = nil

    var initials: String {
        name.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }

    var avatarTone: ClientAvatarTone {
        TeamMemberAvatarStyle.tone(for: id)
    }

    var payRateDescription: String {
        guard payRateEnabled else { return "Not set".translated() }
        if payRateType == .perJob {
            let count = serviceRates.filter { $0.value > 0 }.count
            return count > 0 ? "%d service rates · %@".translated(with: count, "Per Job".translated()) : "Per Job".translated()
        }
        guard payRateAmount > 0 else { return "Not set".translated() }
        return "\(payRateAmount.currency) \(payRateType.displayName.lowercased())"
    }
}

extension Client: Hashable {
    static func == (lhs: Client, rhs: Client) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Client {
    var initials: String {
        name.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }
}
