import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $appViewModel.authMode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode == .signIn ? "Sign In" : "Sign Up").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 16) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if appViewModel.authMode == .signUp {
                    SecureField("Invite code", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button(action: submit) {
                if appViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(appViewModel.authMode == .signIn ? "Sign In" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || (appViewModel.authMode == .signUp && inviteCode.isEmpty))

            Text("Your team members need your private invite code before they can create an account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func submit() {
        Task {
            if appViewModel.authMode == .signIn {
                await appViewModel.signIn(email: email, password: password)
            } else {
                await appViewModel.signUp(email: email, password: password, inviteCode: inviteCode)
            }
        }
    }
}
