import AuthenticationServices
import Foundation
import Observation
import Supabase

// MARK: - Team membership models

struct PendingInvite: Identifiable {
    let id: UUID          // team_members.id
    let businessName: String
    let role: String
}

struct TeamMembership: Identifiable {
    let id: UUID          // team_members.id
    let ownerId: UUID     // owner's auth user ID (needed for owner notifications)
    let businessName: String
    let role: String
    // Pay rate set by the owner — visible to the member
    let payRateType: PayRateType
    let payRateAmount: Double
    let payRateEnabled: Bool
    let payDayOfWeek: Int?    // Calendar weekday: 1=Sun, 2=Mon…7=Sat (perWeek only)
}

enum ViewMode: Equatable {
    case ownBusiness
    case memberOf(TeamMembership)

    static func == (lhs: ViewMode, rhs: ViewMode) -> Bool {
        switch (lhs, rhs) {
        case (.ownBusiness, .ownBusiness): return true
        case (.memberOf(let a), .memberOf(let b)): return a.id == b.id
        default: return false
        }
    }
}

// MARK: - AppSession

@Observable
@MainActor
final class AppSession {
    var isAuthenticated: Bool = false
    var userId: UUID?
    var lastAuthError: String?
    
    var isWaitingForEmailConfirmation: Bool = false
    var pendingConfirmationEmail: String = ""
    var confirmationResendCooldown: Int = 0
    var confirmationDeadline: Date?
    
    private var confirmationTask: Task<Void, Never>?
    private var resendCooldownTask: Task<Void, Never>?

    var currentViewMode: ViewMode = .ownBusiness
    var pendingInvites: [PendingInvite] = []
    var activeMemberships: [TeamMembership] = []

    /// Becomes true after the first auth state is resolved (session or no session).
    var hasResolvedInitialSession: Bool = false

    private var authTask: Task<Void, Never>?

    init() {
        guard SupabaseManager.shared != nil else {
            lastAuthError = "Unable to sign in. Please try again."
            hasResolvedInitialSession = true
            return
        }
        authTask = Task { await observeAuth() }
        Task { await refreshSession() }
    }

    // MARK: - Auth

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
            pendingConfirmationEmail = email
            isWaitingForEmailConfirmation = true
            confirmationDeadline = Date().addingTimeInterval(600)
            startConfirmationPolling()
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }
    
    func resendConfirmation() async {
        guard let client = SupabaseManager.shared else { return }
        guard confirmationResendCooldown == 0 else { return }
        do {
            _ = try await client.auth.resend(email: pendingConfirmationEmail, type: .signup)
            confirmationResendCooldown = 60
            resendCooldownTask?.cancel()
            resendCooldownTask = Task {
                for i in (0..<60).reversed() {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    confirmationResendCooldown = i
                }
                confirmationResendCooldown = 0
            }
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }
    
    func signInWithGoogle() async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            try await client.auth.signInWithOAuth(provider: .google)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // user dismissed — no error shown
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
        } catch {
            lastAuthError = humanizedAuthError(error)
        }
    }

    func cancelConfirmation() {
        confirmationTask?.cancel()
        resendCooldownTask?.cancel()
        isWaitingForEmailConfirmation = false
        pendingConfirmationEmail = ""
        confirmationDeadline = nil
        confirmationResendCooldown = 0
    }
    
    private func startConfirmationPolling() {
        confirmationTask?.cancel()
        confirmationTask = Task {
            for _ in (0..<120) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                guard isWaitingForEmailConfirmation else { break }
                if isAuthenticated {
                    cancelConfirmation()
                    break
                }
            }
        }
    }

    func signOut() async {
        guard let client = SupabaseManager.shared else { return }
        lastAuthError = nil
        do {
            try await client.auth.signOut()
            resetTeamState()
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    func deleteAccount() async -> Bool {
        guard let client = SupabaseManager.shared else { return false }
        lastAuthError = nil
        do {
            try await client.functions.invoke("delete-account")
            resetTeamState()
            return true
        } catch {
            lastAuthError = error.localizedDescription
            return false
        }
    }

    // MARK: - View mode switching

    func switchToOwnBusiness() {
        currentViewMode = .ownBusiness
        UserDefaults.standard.removeObject(forKey: "persistedActiveMembershipId")
    }

    func switchToMembership(_ membership: TeamMembership) {
        currentViewMode = .memberOf(membership)
        UserDefaults.standard.set(membership.id.uuidString, forKey: "persistedActiveMembershipId")
    }

    // MARK: - Invite actions

    func acceptInvite(memberId: UUID) async {
        guard let client = SupabaseManager.shared, let uid = userId else { return }
        do {
            // Fetch member name + owner before updating (needed for the notification)
            struct MemberInfo: Decodable {
                let name: String
                let ownerId: UUID
                enum CodingKeys: String, CodingKey {
                    case name
                    case ownerId = "owner_id"
                }
            }
            let info = try? await client
                .from("team_members")
                .select("name, owner_id")
                .eq("id", value: memberId.uuidString)
                .single()
                .execute()
                .value as MemberInfo

            struct StatusPatch: Encodable { let status: String }
            try await client
                .from("team_members")
                .update(StatusPatch(status: "active"))
                .eq("id", value: memberId.uuidString)
                .execute()
            await resolveTeamMemberships(userId: uid)

            if let membership = activeMemberships.first(where: { $0.id == memberId }) {
                currentViewMode = .memberOf(membership)
                UserDefaults.standard.set(membership.id.uuidString, forKey: "persistedActiveMembershipId")
            }

            // Notify the owner that the cleaner accepted
            if let info {
                await NotificationHelper.insert(
                    userId: info.ownerId,
                    title: "Team Update",
                    message: "\(info.name) accepted your invite and joined the team — you can now assign them jobs.",
                    kind: "team"
                )
            }
        } catch {
            print("[AppSession] acceptInvite error: \(error)")
        }
    }

    func declineInvite(memberId: UUID) async {
        guard let client = SupabaseManager.shared else { return }
        do {
            struct DeclinePatch: Encodable {
                let cleanerUserId: String?
                enum CodingKeys: String, CodingKey { case cleanerUserId = "cleaner_user_id" }
            }
            try await client
                .from("team_members")
                .update(DeclinePatch(cleanerUserId: nil))
                .eq("id", value: memberId.uuidString)
                .execute()
            pendingInvites.removeAll { $0.id == memberId }
        } catch {}
    }

    // MARK: - Internal auth flow

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

    private func refreshSession() async {
        guard let client = SupabaseManager.shared else {
            hasResolvedInitialSession = true
            return
        }
        do {
            let session = try await client.auth.session
            await apply(session: session)
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
                    await apply(session: session)
                }
            case .signedOut, .userDeleted:
                isAuthenticated = false
                userId = nil
                resetTeamState()
            case .passwordRecovery, .mfaChallengeVerified:
                break
            @unknown default:
                break
            }
            hasResolvedInitialSession = true
        }
    }

    private func apply(session: Session) async {
        userId = session.user.id
        isAuthenticated = true
        lastAuthError = nil
        // Link any pending invites that were sent to this user's email
        // before they had an account (or before the RPC ran)
        await selfLinkInvites(userId: session.user.id, email: session.user.email ?? "")
        await resolveTeamMemberships(userId: session.user.id)
    }

    private func selfLinkInvites(userId: UUID, email: String) async {
        guard let client = SupabaseManager.shared,
              !email.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Use a SECURITY DEFINER RPC so RLS doesn't block the update —
        // a direct UPDATE is rejected because the row is owned by the inviting business.
        try? await client.rpc("link_invites_by_email").execute()
    }

    private func resetTeamState() {
        currentViewMode = .ownBusiness
        pendingInvites = []
        activeMemberships = []
    }

    // MARK: - Team membership resolution

    private func resolveTeamMemberships(userId: UUID) async {
        guard let client = SupabaseManager.shared else { return }

        struct MemberRow: Decodable {
            let id: UUID
            let ownerId: UUID
            let status: String
            let role: String
            let payRateType: String?
            let payRateAmount: Double?
            let payRateEnabled: Bool?
            let payDayOfWeek: Int?
            enum CodingKeys: String, CodingKey {
                case id, status, role
                case ownerId        = "owner_id"
                case payRateType    = "pay_rate_type"
                case payRateAmount  = "pay_rate_amount"
                case payRateEnabled = "pay_rate_enabled"
                case payDayOfWeek   = "pay_day_of_week"
            }
        }

        struct ProfileRow: Decodable {
            let id: UUID
            let businessName: String?
            enum CodingKeys: String, CodingKey {
                case id
                case businessName = "business_name"
            }
        }

        do {
            // Step 1: get all team_member rows for this user
            let rows: [MemberRow] = try await client
                .from("team_members")
                .select("id, owner_id, status, role, pay_rate_type, pay_rate_amount, pay_rate_enabled, pay_day_of_week")
                .eq("cleaner_user_id", value: userId.uuidString)
                .execute()
                .value

            guard !rows.isEmpty else {
                pendingInvites = []
                activeMemberships = []
                return
            }

            // Step 2: fetch owner profiles for business names
            let ownerIds = Array(Set(rows.map { $0.ownerId.uuidString }))
            let profiles: [ProfileRow] = (try? await client
                .from("profiles")
                .select("id, business_name")
                .in("id", values: ownerIds)
                .execute()
                .value) ?? []

            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.businessName ?? "A Team") })

            pendingInvites = rows
                .filter { $0.status == "invited" }
                .map { PendingInvite(id: $0.id, businessName: profileMap[$0.ownerId] ?? "A Team", role: $0.role) }

            activeMemberships = rows
                .filter { $0.status == "active" }
                .map { row in
                    TeamMembership(
                        id: row.id,
                        ownerId: row.ownerId,
                        businessName: profileMap[row.ownerId] ?? "A Team",
                        role: row.role,
                        payRateType: PayRateType(rawValue: row.payRateType ?? "per_day") ?? .perDay,
                        payRateAmount: row.payRateAmount ?? 0,
                        payRateEnabled: row.payRateEnabled ?? false,
                        payDayOfWeek: row.payDayOfWeek
                    )
                }

            // Restore persisted view mode from previous session
            if case .memberOf(let m) = currentViewMode {
                if !activeMemberships.contains(where: { $0.id == m.id }) {
                    currentViewMode = .ownBusiness
                    UserDefaults.standard.removeObject(forKey: "persistedActiveMembershipId")
                }
            } else if currentViewMode == .ownBusiness,
                      let savedId = UserDefaults.standard.string(forKey: "persistedActiveMembershipId"),
                      let uuid = UUID(uuidString: savedId),
                      let membership = activeMemberships.first(where: { $0.id == uuid }) {
                currentViewMode = .memberOf(membership)
            }
        } catch {
            pendingInvites = []
            activeMemberships = []
        }
    }
}

