import AuthenticationServices
import CryptoKit
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var email           = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var inviteCode      = ""
    @State private var currentNonce    = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirmPassword, inviteCode }

    var body: some View {
        ZStack {
            EnterpriseBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    logoMark
                    Spacer().frame(height: 40)
                    formCard
                    Spacer().frame(height: 20)
                    if appViewModel.authMode == .signIn &&
                       appViewModel.biometricService.isEnabled &&
                       appViewModel.biometricService.canUseBiometrics {
                        biometricSignInButton
                        Spacer().frame(height: 8)
                    }
                    modeToggleFooter
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
        .onChange(of: appViewModel.authMode) {
            email           = ""
            password        = ""
            confirmPassword = ""
            inviteCode      = ""
            appViewModel.errorMessage = nil
        }
    }

    // MARK: - Logo mark

    private var logoMark: some View {
        VStack(spacing: 18) {
            // The actual app icon — matches the home screen tile exactly
            LoadScanIconView(size: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(
                    color: Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.22),
                    radius: 8, x: 0, y: 4
                )

            VStack(spacing: 6) {
                Text("LoadScan")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textPrimary)

                Text("Load tracking and manifest creation")
                    .font(.system(size: 14))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 22) {
            modeTabs
            fields
            if let err = appViewModel.errorMessage { errorRow(err) }
            submitButton
            if appViewModel.authMode == .signIn { forgotPasswordRow }
            orDivider
            appleSignInButton
        }
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 3)
    }

    // MARK: - Underline tab switcher

    private var modeTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AuthMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appViewModel.authMode = mode
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Text(mode == .signIn ? "Sign In" : "Sign Up")
                                .font(.system(size: 15,
                                              weight: appViewModel.authMode == mode ? .semibold : .regular))
                                .foregroundStyle(
                                    appViewModel.authMode == mode
                                        ? EnterpriseTheme.textPrimary
                                        : EnterpriseTheme.textTertiary
                                )
                                .frame(maxWidth: .infinity)

                            // Animated underline only
                            Rectangle()
                                .fill(appViewModel.authMode == mode
                                      ? EnterpriseTheme.accent
                                      : Color.clear)
                                .frame(height: 2)
                                .animation(.easeInOut(duration: 0.15), value: appViewModel.authMode)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Full-width hairline sits under both tabs
            Rectangle()
                .fill(EnterpriseTheme.border)
                .frame(height: 1)
                .padding(.top, -1) // overlap so the active tab covers it
        }
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: 14) {
            AuthField(
                label: "Email address",
                placeholder: "you@company.com",
                text: $email,
                keyboardType: .emailAddress,
                capitalization: .never,
                submitLabel: .next
            )
            .focused($focus, equals: .email)
            .onSubmit { focus = .password }

            AuthField(
                label: "Password",
                placeholder: "Enter your password",
                text: $password,
                capitalization: .never,
                submitLabel: appViewModel.authMode == .signUp ? .next : .go,
                isSecure: true
            )
            .focused($focus, equals: .password)
            .onSubmit {
                if appViewModel.authMode == .signUp {
                    focus = .confirmPassword
                } else {
                    submit()
                }
            }

            if appViewModel.authMode == .signUp {
                AuthField(
                    label: "Confirm Password",
                    placeholder: "Re-enter your password",
                    text: $confirmPassword,
                    capitalization: .never,
                    submitLabel: .go,
                    isSecure: true
                )
                .focused($focus, equals: .confirmPassword)
                .onSubmit(submit)

                if !confirmPassword.isEmpty && password != confirmPassword {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                        Text("Passwords do not match")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(EnterpriseTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

                AuthField(
                    label: "Enterprise Invite Code (Optional)",
                    placeholder: "Paste team invite code",
                    text: $inviteCode,
                    capitalization: .characters,
                    submitLabel: .go
                )
                .focused($focus, equals: .inviteCode)
                .onSubmit(submit)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: appViewModel.authMode)
    }

    // MARK: - Error

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(EnterpriseTheme.danger)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EnterpriseTheme.danger.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    // MARK: - Submit button

    private var submitButton: some View {
        let passwordsMatch = appViewModel.authMode == .signIn || password == confirmPassword
        let isDisabled = email.isEmpty || password.isEmpty
            || (appViewModel.authMode == .signUp && confirmPassword.isEmpty)
            || !passwordsMatch
            || appViewModel.isLoading

        return Button(action: submit) {
            ZStack {
                if appViewModel.isLoading {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    HStack(spacing: 7) {
                        Text(appViewModel.authMode == .signIn ? "Sign In" : "Create Account")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(EnterpriseTheme.accent.opacity(isDisabled ? 0.45 : 1))
            )
            .animation(.easeInOut(duration: 0.15), value: isDisabled)
        }
        .disabled(isDisabled)
    }

    // MARK: - Forgot password

    private var forgotPasswordRow: some View {
        Button("Forgot your password?") {
            // Wire to Supabase password reset
        }
        .font(.system(size: 13))
        .foregroundStyle(EnterpriseTheme.textSecondary)
    }

    // MARK: - Footer mode toggle

    private var modeToggleFooter: some View {
        HStack(spacing: 5) {
            Text(appViewModel.authMode == .signIn
                 ? "Don't have an account?"
                 : "Already have an account?")
                .font(.system(size: 13))
                .foregroundStyle(EnterpriseTheme.textSecondary)

            Button(appViewModel.authMode == .signIn ? "Sign up" : "Sign in") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appViewModel.authMode = appViewModel.authMode == .signIn ? .signUp : .signIn
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(EnterpriseTheme.accent)
        }
    }

    // MARK: - Or divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(EnterpriseTheme.border).frame(height: 1)
            Text("or")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EnterpriseTheme.textTertiary)
            Rectangle().fill(EnterpriseTheme.border).frame(height: 1)
        }
    }

    // MARK: - Sign in with Apple

    private var appleSignInButton: some View {
        SignInWithAppleButton(
            appViewModel.authMode == .signIn ? .signIn : .signUp
        ) { request in
            let nonce = Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                appViewModel.errorMessage = "Apple sign-in failed. Please try again."
                return
            }
            Task {
                await appViewModel.signInWithApple(identityToken: identityToken, nonce: currentNonce)
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                appViewModel.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Face ID / biometric sign-in

    private var biometricSignInButton: some View {
        Button {
            Task { await appViewModel.signInWithBiometrics() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appViewModel.biometricService.biometricType == .faceID
                      ? "faceid" : "touchid")
                    .font(.system(size: 16))
                Text(appViewModel.biometricService.biometricType == .faceID
                     ? "Sign in with Face ID"
                     : "Sign in with Touch ID")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(EnterpriseTheme.accent)
        }
    }

    // MARK: - Nonce helpers (Sign in with Apple)

    private static func randomNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Action

    private func submit() {
        focus = nil
        appViewModel.errorMessage = nil
        Task {
            if appViewModel.authMode == .signIn {
                await appViewModel.signIn(email: email, password: password)
            } else {
                let normalizedInvite = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                await appViewModel.signUp(
                    email: email,
                    password: password,
                    inviteCode: normalizedInvite.isEmpty ? nil : normalizedInvite
                )
            }
        }
    }
}

// MARK: - Reusable auth field

private struct AuthField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var keyboardType:  UIKeyboardType                = .default
    var capitalization: TextInputAutocapitalization  = .sentences
    var submitLabel:   SubmitLabel                   = .next
    var isSecure:      Bool                          = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EnterpriseTheme.textSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(EnterpriseTheme.textPrimary)
            .tint(EnterpriseTheme.accent)
            .textInputAutocapitalization(capitalization)
            .keyboardType(keyboardType)
            .submitLabel(submitLabel)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(EnterpriseTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
        }
    }
}
