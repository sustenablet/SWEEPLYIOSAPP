import SwiftUI

enum ClientAvatarTone: String, CaseIterable {
    case slate
    case blue

    var backgroundColor: Color {
        switch self {
        case .slate:
            return Color.sweeplyNavy
        case .blue:
            return Color.sweeplyAccent
        }
    }

    var foregroundColor: Color {
        Color.white
    }

    var label: String {
        switch self {
        case .slate:
            return "Slate"
        case .blue:
            return "Blue"
        }
    }
}

enum ClientAvatarStyle {
    private static let storagePrefix = "clientAvatarTone."

    static func tone(for client: Client) -> ClientAvatarTone {
        if let storedRaw = UserDefaults.standard.string(forKey: storagePrefix + client.id.uuidString),
           let stored = ClientAvatarTone(rawValue: storedRaw) {
            return stored
        }
        return defaultTone(for: client.name)
    }

    static func tone(for clientID: UUID, fallbackName: String) -> ClientAvatarTone {
        if let storedRaw = UserDefaults.standard.string(forKey: storagePrefix + clientID.uuidString),
           let stored = ClientAvatarTone(rawValue: storedRaw) {
            return stored
        }
        return defaultTone(for: fallbackName)
    }

    static func save(_ tone: ClientAvatarTone, for clientID: UUID) {
        UserDefaults.standard.set(tone.rawValue, forKey: storagePrefix + clientID.uuidString)
    }

    static func defaultTone(for name: String) -> ClientAvatarTone {
        let hashValue = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return hashValue.isMultiple(of: 2) ? .slate : .blue
    }
}
