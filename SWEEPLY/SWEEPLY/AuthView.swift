import SwiftUI
import Supabase

struct AuthView: View {
    @Environment(AppSession.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isSubmitting = false
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false
    @State private var resetError: String? = nil
    @State private var appeared = false
    @State private var keyboardHeight: CGFloat = 0

    private var canSubmit: Bool {
        isValidEmail(email) && password.count >= 6 && !isSubmitting
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        return isValidEmail(email) ? nil : "Enter a valid email address"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // White background fills everything
                Color.white
                    .ignoresSafeArea()

                // Blue color above the image only
                Color(red: 0.827, green: 0.867, blue: 0.992)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)

                // Image with tint and text
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        Image("SignupImage")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .offset(y: 40)
                            .overlay(Color.sweeplyWordmarkBlue.opacity(0.35))

                        Text(isSignUp ? "Create your account and simplify your workday" : "Welcome back! Sign in to continue")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(height: 120)

                    Spacer()
                }

                // White card (overlays image)
                authCard
                    .frame(maxWidth: .infinity)
                    .offset(y: appeared ? -keyboardHeight + 160 : 220 - keyboardHeight)
                    .opacity(appeared ? 1 : 0)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                keyboardHeight = keyboardFrame.height * 0.5
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                keyboardHeight = 0
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSignUp)
        .animation(.easeInOut(duration: 0.15), value: session.lastAuthError)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                appeared = true
            }
        }
        .overlay {
            if session.isWaitingForEmailConfirmation {
                WaitingForConfirmationView(
                    email: session.pendingConfirmationEmail,
                    cooldown: session.confirmationResendCooldown,
                    deadline: session.confirmationDeadline,
                    onResend: { Task { await session.resendConfirmation() } },
                    onCancel: { session.cancelConfirmation() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.isWaitingForEmailConfirmation)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(
                resetEmail: $resetEmail,
                resetSent: $resetSent,
                resetError: $resetError
            )
        }
    }

    // MARK: - Hero

    private func heroSection(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.sweeplyWordmarkBlue
                    .frame(height: geo.size.height * 0.46)

                // Decorative circles
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220)
                    .offset(x: geo.size.width * 0.6, y: -40)

                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 140)
                    .offset(x: geo.size.width * 0.75, y: 20)

                // Headline
                VStack(alignment: .leading, spacing: 10) {
                    Image("SweeplyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .opacity(0.9)

                    Text(isSignUp
                         ? "Create your\nSweeply account."
                         : "Sign in to manage\nyour business.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(-0.5)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.2), value: isSignUp)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Auth Card

    private var authCard: some View {
        VStack(spacing: 0) {
            // Title row
            VStack(alignment: .leading, spacing: 4) {
                Text(isSignUp ? "Create Account" : "Login")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                    .tracking(-0.4)

                HStack(spacing: 4) {
                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            session.lastAuthError = nil
                        }
                    } label: {
                        Text(isSignUp ? "Sign In" : "Sign Up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.sweeplyWordmarkBlue)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 22)

            // Fields
            VStack(spacing: 14) {
                emailField
                passwordField
            }
            .padding(.horizontal, 28)

            // Forgot / error row
            if !isSignUp {
                HStack {
                    Spacer()
                    Button("Forgot Password?".translated()) {
                        resetEmail = email
                        resetSent = false
                        resetError = nil
                        showForgotPassword = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyWordmarkBlue)
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
            }

            // Error banner
            if let err = session.lastAuthError, !err.isEmpty {
                errorBanner(err)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

// CTA button
            ctaButton
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 40)
        }
        .background(
            Color.white
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -6)
        )
    }

    // MARK: - Fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 20)

                TextField("Enter your email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(emailError != nil ? Color.sweeplyDestructive : Color.clear, lineWidth: 1)
            )

            if let err = emailError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .padding(.leading, 4)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(width: 20)

                SecureField("••••••••", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(password.count > 0 && password.count < 6 ? Color.sweeplyDestructive : Color.clear, lineWidth: 1)
            )

            if isSignUp {
                passwordStrengthIndicator
            }
        }
    }

    private var passwordStrengthIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Rectangle()
                    .fill(passwordStrengthColor(for: index))
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            Spacer()
            Text(passwordStrengthLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(passwordStrengthLabelColor)
        }
    }

    private func passwordStrengthColor(for index: Int) -> Color {
        let strength = passwordStrength
        if password.count == 0 { return Color.sweeplyBorder }
        if index < strength { return strengthColor }
        return Color.sweeplyBorder.opacity(0.4)
    }

    private var passwordStrength: Int {
        if password.count < 6 { return 0 }
        if password.count < 10 { return 1 }
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        if hasSpecial && password.count >= 10 { return 3 }
        return 2
    }

    private var strengthColor: Color {
        switch passwordStrength {
        case 1: return Color.sweeplyWarning
        case 2: return Color.sweeplySuccess
        case 3: return Color.sweeplySuccess
        default: return Color.sweeplyBorder
        }
    }

    private var passwordStrengthLabel: String {
        switch passwordStrength {
        case 0: return "Too short"
        case 1: return "Weak"
        case 2: return "Good"
        case 3: return "Strong"
        default: return ""
        }
    }

    private var passwordStrengthLabelColor: Color {
        switch passwordStrength {
        case 0: return Color.sweeplyDestructive
        case 1: return Color.sweeplyWarning
        case 2: return Color.sweeplySuccess
        case 3: return Color.sweeplySuccess
        default: return Color.sweeplyTextSub
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.sweeplyDestructive)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sweeplyDestructive.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await submit() }
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Text(isSignUp ? "Create Account" : "Login")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                canSubmit
                    ? Color.sweeplyWordmarkBlue
                    : Color.sweeplyWordmarkBlue.opacity(0.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        if isSignUp {
            await session.signUp(email: e, password: p)
        } else {
            await session.signIn(email: e, password: p)
        }
        if session.lastAuthError == nil || session.lastAuthError?.isEmpty == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Waiting For Confirmation View

private struct WaitingForConfirmationView: View {
    let email: String
    let cooldown: Int
    let deadline: Date?
    let onResend: () -> Void
    let onCancel: () -> Void

    @State private var dots: Int = 1
    @State private var remainingSeconds: Int = 600
    @State private var timer: Timer?

    private var maskedEmail: String {
        guard let at = email.firstIndex(of: "@") else { return email }
        let local = email[..<at]
        let domain = email[at...]
        let masked: String
        if local.count <= 2 {
            masked = String(local)
        } else {
            masked = String(local.prefix(1)) + String(repeating: "*", count: max(0, local.count - 2)) + String(local.suffix(1))
        }
        return masked + String(domain)
    }

    private var dotAnimation: String { String(repeating: ".", count: dots) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyAccent.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Color.sweeplyAccent)
                    }

                    VStack(spacing: 8) {
                        Text("Check your email".translated())
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("We sent a confirmation link to:".translated())
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                        Text(maskedEmail)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                    }

                    Text("Tap the link to verify your account and sign in.".translated())
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    if deadline != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text("Link expires in \(formatTime(remainingSeconds))")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.sweeplyTextSub)
                    }
                    Text("Waiting for verification\(dotAnimation)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
                        .animation(.none)
                }

                VStack(spacing: 10) {
                    Button { onResend() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 13))
                            Text(cooldown > 0 ? "Resend (\(cooldown)s)" : "Resend email".translated())
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(cooldown > 0 ? Color.sweeplyTextSub : Color.sweeplyAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                    .disabled(cooldown > 0)

                    Button { onCancel() } label: {
                        Text("Cancel".translated())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .onAppear { startDotsAnimation(); startCountdown() }
        .onDisappear { timer?.invalidate() }
    }

    private func startDotsAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            dots = dots >= 3 ? 1 : dots + 1
        }
    }

    private func startCountdown() {
        if let deadline { remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow)) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 { remainingSeconds -= 1 } else { timer?.invalidate(); onCancel() }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Forgot Password Sheet

private struct ForgotPasswordSheet: View {
    @Binding var resetEmail: String
    @Binding var resetSent: Bool
    @Binding var resetError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 28)

            if resetSent { sentState } else { formState }
            Spacer()
        }
        .background(Color.sweeplySurface.ignoresSafeArea())
    }

    private var sentState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.sweeplyAccent.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Color.sweeplyAccent)
            }
            VStack(spacing: 8) {
                Text("Check your email".translated())
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Color.sweeplyNavy)
                Text("We sent a reset link to \(resetEmail). Check your inbox and follow the instructions.")
                    .font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }
            Button("Done".translated()) { dismiss() }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.sweeplyNavy)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
        }
        .padding(.horizontal, 28)
    }

    private var formState: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset Password".translated())
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Color.sweeplyNavy)
                Text("Enter your email and we'll send you a reset link.".translated())
                    .font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email".translated())
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sweeplyTextSub)
                TextField("you@example.com", text: $resetEmail)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
            .padding(.horizontal, 28).padding(.top, 24)

            if let err = resetError, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                    Text(err).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.sweeplyDestructive)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sweeplyDestructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 28).padding(.top, 12)
            }

            Button {
                guard !resetEmail.isEmpty else { return }
                isSending = true
                Task {
                    do {
                        guard let client = SupabaseManager.shared else {
                            await MainActor.run { resetError = "Not connected. Please try again."; isSending = false }
                            return
                        }
                        try await client.auth.resetPasswordForEmail(resetEmail)
                        await MainActor.run { resetSent = true; isSending = false }
                    } catch {
                        await MainActor.run { resetError = error.localizedDescription; isSending = false }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isSending { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text("Send Reset Link".translated()).font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(resetEmail.contains("@") ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isSending || !resetEmail.contains("@"))
            .padding(.horizontal, 28).padding(.top, 24)
        }
    }
}

#Preview {
    AuthView()
        .environment(AppSession())
}
