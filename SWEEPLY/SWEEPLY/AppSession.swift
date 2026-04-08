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

    func signIn(email: String, password: String) async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }

    func signUp(email: String, password: String) async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }

    private func humanizedAuthError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("Invalid login credentials") || msg.contains("invalid_grant") {
            return "Wrong email or password. Please try again."
        }
        if msg.contains("Email not confirmed") || msg.contains("email_not_confirmed") {
            return "Check your email and confirm your account first."
        }
        if msg.contains("User already registered") || msg.contains("already registered") {
            return "An account with this email already exists. Try signing in."
        }
        if msg.contains("Password should be at least") {
            return "Password must be at least 6 characters."
        }
        if msg.lowercased().contains("network") || msg.contains("The Internet connection") {
            return "No internet connection. Check your network and try again."
        }
        if msg.lowercased().contains("rate limit") || msg.lowercased().contains("too many requests") {
            return "Too many attempts. Please wait a moment and try again."
        }
        return msg
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
