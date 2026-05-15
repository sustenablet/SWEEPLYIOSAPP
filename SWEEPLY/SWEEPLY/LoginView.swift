import AuthenticationServices
import CryptoKit
import SwiftUI

struct LoginView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(AppSession.self) private var session

    @State private var step = 0
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isSubmitting = false
    @State private var isSocialSubmitting = false
    @State private var appleSignInNonce = ""
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: regex, options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            Color.sweeplyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                ZStack {
                    if step == 0 { emailStep.transition(forwardTransition).id(0) }
                    if step == 1 { passwordStep.transition(forwardTransition).id(1) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture {
            emailFocused = false
            passwordFocused = false
        }
        .animation(.easeInOut(duration: 0.15), value: session.lastAuthError)
        .onChange(of: step) { _, _ in session.lastAuthError = nil }
    }

    private var forwardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if step == 0 { onDismiss?() } else {
                    withAnimation(.easeInOut(duration: 0.22)) { step = 0 }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.sweeplyNavy)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Email Step

    private var emailStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log In")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.6)
                        Text("Your business, right where you left it.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)

                    VStack(spacing: 16) {
                        loginField(
                            placeholder: "your@email.com",
                            text: $email,
                            icon: "envelope",
                            keyboardType: .emailAddress
                        )
                        .focused($emailFocused, equals: true)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit {
                            emailFocused = false
                            if isValidEmail(email) {
                                withAnimation(.easeInOut(duration: 0.28)) { step = 1 }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // Apple sign-in + Continue — kept outside ScrollView for reliable hit-testing
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                    Text("or")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Rectangle().fill(Color.sweeplyBorder).frame(height: 1)
                }
                .padding(.horizontal, 24)

                appleButton
                    .padding(.horizontal, 24)

                Divider().opacity(0.5).padding(.top, 4)

                primaryButton(
                    label: "Continue",
                    isEnabled: isValidEmail(email)
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.28)) { step = 1 }
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Password Step

    private var passwordStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter your\npassword")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                            .tracking(-0.6)
                        Text(email.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.sweeplyTextSub)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)

                    VStack(spacing: 12) {
                        // Password field
                        HStack(spacing: 12) {
                            Image(systemName: "lock")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .frame(width: 24)

                            if showPassword {
                                TextField("••••••••", text: $password)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)
                                    .focused($passwordFocused, equals: true)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .submitLabel(.go)
                                    .onSubmit { Task { await submit() } }
                            } else {
                                SecureField("••••••••", text: $password)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Color.sweeplyNavy)
                                    .focused($passwordFocused, equals: true)
                                    .textContentType(.password)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await submit() } }
                            }

                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )

                        // Error
                        if let err = session.lastAuthError, !err.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 14))
                                Text(err)
                                    .font(.system(size: 13, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Color.sweeplyDestructive)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.sweeplyDestructive.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Forgot password
                        HStack {
                            Spacer()
                            Button("Forgot password?") {
                                // TODO: forgot password
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sweeplyWordmarkBlue)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Divider().opacity(0.5)

            primaryButton(
                label: isSubmitting ? "Signing in…" : "Log In",
                isEnabled: password.count >= 6 && !isSubmitting
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await submit() }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { passwordFocused = true }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func loginField(
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.sweeplyNavy)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }

    private func primaryButton(label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isEnabled ? Color.sweeplyNavy : Color.sweeplyNavy.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(
                    color: isEnabled ? Color.sweeplyNavy.opacity(0.22) : .clear,
                    radius: 8, x: 0, y: 4
                )
        }
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
        .padding(.horizontal, 24)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = randomNonce()
            appleSignInNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    session.lastAuthError = "Apple Sign In failed. Please try again."
                    return
                }
                isSocialSubmitting = true
                Task {
                    await session.signInWithApple(idToken: idToken, nonce: appleSignInNonce)
                    isSocialSubmitting = false
                }
            case .failure(let error):
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    session.lastAuthError = nil
                } else {
                    session.lastAuthError = "Apple Sign In failed: \(error.localizedDescription)"
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(isSocialSubmitting)
        .opacity(isSocialSubmitting ? 0.6 : 1)
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await session.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        if session.lastAuthError == nil || session.lastAuthError?.isEmpty == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Nonce

    private func randomNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    LoginView()
        .environment(AppSession())
}
