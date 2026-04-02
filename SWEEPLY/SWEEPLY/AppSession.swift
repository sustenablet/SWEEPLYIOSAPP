import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AppSession {
    var isAuthenticated: Bool = false
    var userId: UUID?
    var lastAuthError: String?

    /// Becomes true after the first auth state is resolved (session or no session).
    var hasResolvedInitialSession: Bool = false

    private var authTask: Task<Void, Never>?

    init() {
        guard SupabaseManager.shared != nil else {
            lastAuthError = "Supabase is not configured."
            hasResolvedInitialSession = true
            return
        }
        authTask = Task { await observeAuth() }
        Task { await refreshSession() }
    }

    deinit {
        authTask?.cancel()
    }

    func signIn(email: String, password: String) async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            try await client.auth.signOut()
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    private func refreshSession() async {
        guard let client = SupabaseManager.shared else {
            hasResolvedInitialSession = true
            return
        }
        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch {
            isAuthenticated = false
            userId = nil
        }
        hasResolvedInitialSession = true
    }

    private func observeAuth() async {
        guard let client = SupabaseManager.shared else { return }
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
            hasResolvedInitialSession = true
        }
    }

    private func apply(session: Session) {
        userId = session.user.id
        isAuthenticated = true
        lastAuthError = nil
    }
}
