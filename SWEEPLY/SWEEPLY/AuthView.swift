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

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isSubmitting
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color.sweeplyBackground.ignoresSafeArea()

            // Brand area (top) — single spacer below keeps the mark grouped and nearer the sheet
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                brandMark
                Spacer(minLength: 0)
            }

            // Auth card (bottom sheet)
            authCard
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Brand Mark

    private var brandMark: some View {
        VStack(spacing: 12) {
            Image("SweeplyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Sweep")
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("ly")
                        .foregroundStyle(Color.sweeplyAccent)
                }
                .font(.system(size: 52, weight: .bold))
                .tracking(-1.4)

                Text("Run your cleaning business.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .padding(.horizontal, 8)
        // Reserve space for the bottom auth sheet without excess gap under the tagline.
        .padding(.bottom, 300)
    }

    // MARK: - Auth Card

    private var authCard: some View {
        VStack(spacing: 0) {
            // Pull handle
            Capsule()
                .fill(Color.sweeplyBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Tab switcher
            tabSwitcher
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Social sign-in
            VStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await session.signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            // Divider
            HStack(spacing: 12) {
                Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                Text("or continue with email")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .fixedSize()
                Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Fields
            VStack(spacing: 14) {
                emailField
                passwordField
            }
            .padding(.horizontal, 24)

            // Error
            if let err = session.lastAuthError, !err.isEmpty {
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
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }

            // CTA button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await submit() }
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    }
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSubmit ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: canSubmit ? Color.sweeplyNavy.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // Forgot password / toggle
            VStack(spacing: 4) {
                if !isSignUp {
                    Button("Forgot password?") {
                        resetEmail = email
                        resetSent = false
                        resetError = nil
                        showForgotPassword = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .padding(.top, 6)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSignUp.toggle()
                        session.lastAuthError = nil
                    }
                } label: {
                    Text(isSignUp ? "Already have an account? Sign in" : "Need an account? Create one")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 48)
        }
        .background(
            Color.sweeplySurface
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.2), value: isSignUp)
        .animation(.easeInOut(duration: 0.15), value: session.lastAuthError)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(resetEmail: $resetEmail, resetSent: $resetSent, resetError: $resetError)
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabPill(label: "Sign In", isActive: !isSignUp) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp = false
                    session.lastAuthError = nil
                }
            }
            tabPill(label: "Create Account", isActive: isSignUp) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp = true
                    session.lastAuthError = nil
                }
            }
        }
    }

    private func tabPill(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color.sweeplyNavy : Color.sweeplyTextSub)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(isActive ? Color.sweeplyAccent : Color.clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            TextField("you@example.com", text: $email)
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
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)
            SecureField("••••••••", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
            if isSignUp {
                Text("Use at least 6 characters.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.7))
            }
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
                        Text("Check your email")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("We sent a reset link to \(resetEmail). Check your inbox and follow the instructions.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reset Password")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text("Enter your email and we'll send you a reset link.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
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
                        Text("Send Reset Link")
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

            Spacer()
        }
        .background(Color.sweeplySurface.ignoresSafeArea())
    }
}

#Preview {
    AuthView()
        .environment(AppSession())
}
