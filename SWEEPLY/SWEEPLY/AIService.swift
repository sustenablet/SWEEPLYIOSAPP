import Foundation

// MARK: - AIService
// Calls Groq's free API (OpenAI-compatible) for intelligent fallback responses.
// Key is stored in SupabaseConfig.plist under GROQ_API_KEY.
// Get a free key at console.groq.com — no credit card required.

@Observable
@MainActor
final class AIService {

    static let shared = AIService()

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let model = "llama-3.3-70b-versatile"

    private let apiKey: String = {
        guard
            let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            let key = dict["GROQ_API_KEY"], !key.isEmpty, !key.hasPrefix("ADD_")
        else { return "" }
        return key
    }()

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Chat

    /// Sends a message to Groq and returns the response string, or nil on failure.
    func chat(userMessage: String, systemPrompt: String) async -> String? {
        guard isConfigured else { return nil }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 300,
            "temperature": 0.7
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 7

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                if let http = response as? HTTPURLResponse {
                    print("[AIService] Non-200 status: \(http.statusCode)")
                }
                #endif
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return message?["content"] as? String
        } catch {
            #if DEBUG
            print("[AIService] chat() failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
