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
        ZStack {
            Color.sweeplySurface.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                brandMark
                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            authCard
        }
        .animation(.easeInOut(duration: 0.2), value: isSignUp)
        .animation(.easeInOut(duration: 0.15), value: session.lastAuthError)
    }

    // MARK: - Decorative Blobs

    private var accentBlobs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.sweeplyWordmarkBlue.opacity(0.09))
                    .frame(width: 340)
                    .offset(x: geo.size.width * 0.5, y: -geo.size.height * 0.12)
                    .blur(radius: 2)

                Circle()
                    .fill(Color.sweeplyWordmarkBlue.opacity(0.05))
                    .frame(width: 180)
                    .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.08)
                    .blur(radius: 1)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Brand Mark

    private var brandMark: some View {
        VStack(spacing: 18) {
            Image("SweeplyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.95)

            VStack(spacing: 7) {
                HStack(spacing: 0) {
                    Text("Sweep".translated())
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("ly".translated())
                        .foregroundStyle(Color.sweeplyWordmarkBlue)
                }
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.2)

                Text("Run your cleaning business.".translated())
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.1)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42).delay(0.08)) {
                appeared = true
            }
        }
    }

    // MARK: - Auth Card

    private var authCard: some View {
        VStack(spacing: 0) {
            // Pull handle
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 22)

            // Animated tab switcher
            tabSwitcher
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

            // Form fields
            VStack(spacing: 14) {
                emailField
                passwordField
            }
            .padding(.horizontal, 24)

            // Error banner
            if let err = session.lastAuthError, !err.isEmpty {
                errorBanner(err)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Primary CTA
            ctaButton
                .padding(.horizontal, 24)
                .padding(.top, 20)

            // Footer links
            footerLinks
                .padding(.top, 6)
                .padding(.bottom, 40)
        }
        .background(
            Color.sweeplySurface
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: -4)
        )
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(
                resetEmail: $resetEmail,
                resetSent: $resetSent,
                resetError: $resetError
            )
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        ZStack {
            // Track
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.sweeplyBackground)
                .frame(height: 44)

            // Sliding pill — splits space evenly with a Spacer
            HStack(spacing: 0) {
                if isSignUp { Spacer() }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.sweeplySurface)
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1.5)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                if !isSignUp { Spacer() }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: isSignUp)

            // Labels on top
            HStack(spacing: 0) {
                tabPill("Sign In".translated(), isActive: !isSignUp) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { isSignUp = false; session.lastAuthError = nil }
                }
                tabPill("Create Account".translated(), isActive: isSignUp) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { isSignUp = true; session.lastAuthError = nil }
                }
            }
        }
        .frame(height: 44)
    }

    private func tabPill(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.sweeplyNavy : Color.sweeplyTextSub)
                .animation(.easeInOut(duration: 0.15), value: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EMAIL".translated())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            emailError != nil ? Color.sweeplyDestructive : Color.sweeplyBorder,
                            lineWidth: 1
                        )
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
            Text("PASSWORD".translated())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            SecureField("••••••••", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .font(.system(size: 16))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(password.count > 0 && password.count < 6 ? Color.sweeplyDestructive : Color.sweeplyBorder, lineWidth: 1)
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
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                canSubmit
                    ? Color.sweeplyNavy
                    : Color.sweeplyNavy.opacity(0.28)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: canSubmit ? Color.sweeplyNavy.opacity(0.28) : .clear,
                radius: 10, x: 0, y: 4
            )
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        VStack(spacing: 2) {
            if !isSignUp {
                Button("Forgot password?".translated()) {
                    resetEmail = email
                    resetSent = false
                    resetError = nil
                    showForgotPassword = true
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .padding(.top, 10)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp.toggle()
                    session.lastAuthError = nil
                }
            } label: {
                Text(isSignUp
                     ? "Already have an account? Sign in"
                     : "Need an account? Create one")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.top, 6)
        }
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

            if resetSent {
                sentState
            } else {
                formState
            }

            Spacer()
        }
        .background(Color.sweeplySurface.ignoresSafeArea())
    }

    private var sentState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            VStack(spacing: 8) {
                Text("Check your email".translated())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("We sent a reset link to \(resetEmail). Check your inbox and follow the instructions.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Button("Done".translated()) { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Enter your email and we'll send you a reset link.".translated())
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email".translated())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                TextField("you@example.com", text: $resetEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            if let err = resetError, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(err)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.sweeplyDestructive)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sweeplyDestructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 28)
                .padding(.top, 12)
            }

            Button {
                guard !resetEmail.isEmpty else { return }
                isSending = true
                Task {
                    do {
                        guard let client = SupabaseManager.shared else {
                            await MainActor.run {
                                resetError = "Not connected. Please try again."
                                isSending = false
                            }
                            return
                        }
                        try await client.auth.resetPasswordForEmail(resetEmail)
                        await MainActor.run { resetSent = true; isSending = false }
                    } catch {
                        await MainActor.run {
                            resetError = error.localizedDescription
                            isSending = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isSending { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text("Send Reset Link".translated())
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(resetEmail.contains("@") ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isSending || !resetEmail.contains("@"))
            .padding(.horizontal, 28)
            .padding(.top, 24)
        }
    }
}

#Preview {
    AuthView()
        .environment(AppSession())
}
