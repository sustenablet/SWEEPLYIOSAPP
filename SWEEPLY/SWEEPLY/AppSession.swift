import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AppSession {
    var isAuthenticated: Bool = false
    var userId: UUID?
    var lastAuthError: String?

    private var authTask: Task<Void, Never>?

    init() {
        guard let client = SupabaseManager.shared else {
            lastAuthError = "Supabase is not configured."
            return
        }
        authTask = Task { await observeAuth(client: client) }
        Task { await refreshSession(client: client) }
    }

    deinit {
        authTask?.cancel()
    }

    func signOut() async {
        guard let client = SupabaseManager.shared else { return }
        do {
            try await client.auth.signOut()
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    private func refreshSession(client: SupabaseClient) async {
        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch {
            isAuthenticated = false
            userId = nil
        }
    }

    private func observeAuth(client: SupabaseClient) async {
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if let session {
                    apply(session: session)
                }
            case .signedOut, .userDeleted:
                isAuthenticated = false
                userId = nil
            case .passwordRecovery, .mfaChallengeVerified:
                break
            @unknown default:
                break
            }
        }
    }

    private func apply(session: Session) {
        userId = session.user.id
        isAuthenticated = true
        lastAuthError = nil
    }
}
