import SwiftUI

struct AuthView: View {
    @Environment(AppSession.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sweeply")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(isSignUp ? "Create an account" : "Sign in to continue")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 14) {
                    emailField
                    passwordField
                    Text("Use at least 6 characters.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyTextSub)
                }

                if let err = session.lastAuthError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyDestructive)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSignUp ? "Create account" : "Sign in")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit && !isSubmitting ? Color.sweeplyNavy : Color.sweeplyTextSub.opacity(0.35))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!canSubmit || isSubmitting)

                Button {
                    isSignUp.toggle()
                    session.lastAuthError = nil
                } label: {
                    Text(isSignUp ? "Already have an account? Sign in" : "Need an account? Sign up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sweeplyAccent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sweeplyTextSub)
            SecureField("••••••••", text: $password)
                .textContentType(.password)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

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
    }
}

#Preview {
    AuthView()
        .environment(AppSession())
}
