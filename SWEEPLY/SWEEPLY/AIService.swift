import Foundation

// MARK: - AIService
// Calls the Supabase Edge Function `ai-chat`, which proxies to Groq server-side.
// The GROQ_API_KEY is stored as a Supabase secret — never in the app bundle.

@Observable
@MainActor
final class AIService {

    static let shared = AIService()

    private struct Config {
        let functionURL: URL
        let anonKey: String
    }

    private let config: Config? = {
        guard
            let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            let supabaseURL = dict["SUPABASE_URL"], !supabaseURL.isEmpty,
            let anonKey = dict["SUPABASE_ANON_KEY"], !anonKey.isEmpty,
            let fnURL = URL(string: "\(supabaseURL)/functions/v1/ai-chat")
        else { return nil }
        return Config(functionURL: fnURL, anonKey: anonKey)
    }()

    var isConfigured: Bool { config != nil }

    // MARK: - Chat (legacy single-turn)

    func chat(userMessage: String, systemPrompt: String) async -> String? {
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage],
        ]
        return await sendMessages(messages)
    }

    // MARK: - Chat with conversation history

    func chatWithHistory(messages: [[String: String]]) async -> String? {
        return await sendMessages(messages)
    }

    // MARK: - Private

    private func sendMessages(_ messages: [[String: String]]) async -> String? {
        guard let config else { return nil }

        let body: [String: Any] = ["messages": messages]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: config.functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                if let http = response as? HTTPURLResponse {
                    print("[AIService] Edge function error: \(http.statusCode)")
                }
                #endif
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["content"] as? String
        } catch {
            #if DEBUG
            print("[AIService] sendMessages() failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
