import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case portuguese = "pt-BR"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .portuguese: return "Português (Brasil)"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .portuguese: return "🇧🇷"
        }
    }
}

struct LanguagePicker: View {
    @AppStorage("appLanguage") private var language: String = AppLanguage.english.rawValue
    
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        language = lang.rawValue
                    }
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.displayName)
                        if language == lang.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if let current = AppLanguage(rawValue: language) {
                HStack(spacing: 6) {
                    Text(current.flag)
                        .font(.system(size: 16))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.8))
                .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

struct LanguageToggle: View {
    @AppStorage("appLanguage") private var language: String = AppLanguage.english.rawValue
    
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        language = lang.rawValue
                    }
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.displayName)
                        if language == lang.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let current = AppLanguage(rawValue: language) {
                    Text(current.flag)
                }
                Text("Language")
                    .font(.system(size: 15))
                Spacer()
                if let current = AppLanguage(rawValue: language) {
                    Text(current.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.gray)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

extension String {
    func translated() -> String {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        guard lang == AppLanguage.portuguese.rawValue else { return self }
        return Localization.translate(self)
    }

    /// Use for strings with interpolation: "You have %d jobs".translated(with: count)
    func translated(with args: CVarArg...) -> String {
        let template = translated()
        return String(format: template, arguments: args)
    }
}