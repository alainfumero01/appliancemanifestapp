import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @AppStorage("loadscan.defaultCondition") private var defaultCondition = ItemCondition.used.rawValue
    @AppStorage("loadscan.hapticsEnabled")   private var hapticsEnabled   = true
    @State private var showDeleteConfirmation = false
    @State private var showPasswordResetConfirmation = false
    @State private var isSendingPasswordReset = false
    @State private var biometricEnabled: Bool = false
    @State private var inviteCodeInput = ""
    @State private var isJoiningOrg = false
    @State private var joinOrgError: String?
    @State private var showJoinOrgSuccess = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                profileHeader
                accountSection
                securitySection
                preferencesSection
                supportSection
                joinOrgSection
                aboutSection
                dangerSection
                versionFooter
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background(EnterpriseBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            biometricEnabled = appViewModel.biometricService.isEnabled
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                Task { await appViewModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all associated data. This cannot be undone.")
        }
        .alert("Password Reset Sent", isPresented: $showPasswordResetConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your email for a link to reset your password.")
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        let email = appViewModel.session?.user.email ?? ""
        let initial = String(email.prefix(1)).uppercased()

        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(EnterpriseTheme.accentDim)
                    .frame(width: 64, height: 64)
                Text(initial)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.accent)
            }
            VStack(spacing: 3) {
                Text(email)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                Text(appViewModel.entitlement?.currentPlan.displayName ?? "Free Trial")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection(label: "ACCOUNT") {
            SettingsRow(
                icon: "envelope",
                iconColor: EnterpriseTheme.accent,
                title: "Email Address",
                trailing: {
                    Text(appViewModel.session?.user.email ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                        .lineLimit(1)
                }
            )

            SettingsDivider()

            SettingsRow(
                icon: "key",
                iconColor: Color(red: 0.4, green: 0.6, blue: 1.0),
                title: isSendingPasswordReset ? "Sending…" : "Change Password",
                showChevron: !isSendingPasswordReset,
                action: {
                    guard !isSendingPasswordReset,
                          let email = appViewModel.session?.user.email else { return }
                    isSendingPasswordReset = true
                    Task {
                        try? await appViewModel.sendPasswordReset(email: email)
                        isSendingPasswordReset = false
                        showPasswordResetConfirmation = true
                    }
                }
            )
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        SettingsSection(label: "SECURITY") {
            if appViewModel.biometricService.canUseBiometrics {
                let typeName = appViewModel.biometricService.biometricType == .faceID
                    ? "Face ID"
                    : "Touch ID"

                SettingsRow(
                    icon: appViewModel.biometricService.biometricType == .faceID
                        ? "faceid" : "touchid",
                    iconColor: EnterpriseTheme.success,
                    title: typeName,
                    trailing: {
                        Toggle("", isOn: $biometricEnabled)
                            .labelsHidden()
                            .tint(EnterpriseTheme.accent)
                            .onChange(of: biometricEnabled) { _, newValue in
                                appViewModel.biometricService.isEnabled = newValue
                            }
                    }
                )
            } else {
                SettingsRow(
                    icon: "faceid",
                    iconColor: EnterpriseTheme.textTertiary,
                    title: "Biometrics Unavailable",
                    trailing: {
                        Text("Not supported")
                            .font(.system(size: 12))
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                    }
                )
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSection(label: "PREFERENCES") {
            SettingsRow(
                icon: "tag",
                iconColor: EnterpriseTheme.warning,
                title: "Default Item Condition",
                trailing: {
                    Picker("", selection: $defaultCondition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Text(condition.displayLabel).tag(condition.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(EnterpriseTheme.accent)
                }
            )

            SettingsDivider()

            SettingsRow(
                icon: "water.waves",
                iconColor: Color(red: 0.3, green: 0.7, blue: 0.9),
                title: "Haptic Feedback",
                trailing: {
                    Toggle("", isOn: $hapticsEnabled)
                        .labelsHidden()
                        .tint(EnterpriseTheme.accent)
                }
            )
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        SettingsSection(label: "SUPPORT") {
            SettingsRow(
                icon: "questionmark.circle",
                iconColor: Color(red: 0.2, green: 0.7, blue: 0.6),
                title: "Help & FAQ",
                showChevron: true,
                action: { openURL("https://load-scan.com/help") }
            )

            SettingsDivider()

            SettingsRow(
                icon: "envelope.badge",
                iconColor: EnterpriseTheme.accent,
                title: "Contact Support",
                showChevron: true,
                action: { openURL("mailto:support@load-scan.com") }
            )

            SettingsDivider()

            SettingsRow(
                icon: "star",
                iconColor: Color(red: 1.0, green: 0.75, blue: 0.2),
                title: "Rate LoadScan",
                showChevron: true,
                action: { openURL("https://apps.apple.com/app/loadscan") }
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(label: "ABOUT") {
            SettingsRow(
                icon: "info.circle",
                iconColor: EnterpriseTheme.accent,
                title: "Version",
                trailing: {
                    Text(appVersion)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            )

            SettingsDivider()

            SettingsRow(
                icon: "lock.shield",
                iconColor: Color(red: 0.4, green: 0.5, blue: 0.8),
                title: "Privacy Policy",
                showChevron: true,
                action: { openURL("https://load-scan.com/privacy") }
            )

            SettingsDivider()

            SettingsRow(
                icon: "doc.text",
                iconColor: EnterpriseTheme.textTertiary,
                title: "Terms of Service",
                showChevron: true,
                action: { openURL("https://load-scan.com/terms") }
            )
        }
    }

    // MARK: - Join Organization

    private var joinOrgSection: some View {
        SettingsSection(label: "ORGANIZATION") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Have an enterprise invite code? Enter it below to join your team's organization.")
                    .font(.system(size: 13))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                HStack(spacing: 10) {
                    TextField("Invite code (e.g. ABC-123)", text: $inviteCodeInput)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Button {
                        Task {
                            isJoiningOrg = true
                            joinOrgError = nil
                            do {
                                _ = try await appViewModel.joinOrgWithInvite(code: inviteCodeInput.trimmingCharacters(in: .whitespaces))
                                inviteCodeInput = ""
                                showJoinOrgSuccess = true
                            } catch {
                                joinOrgError = error.localizedDescription
                            }
                            isJoiningOrg = false
                        }
                    } label: {
                        if isJoiningOrg {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 60, height: 36)
                        } else {
                            Text("Join")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 36)
                        }
                    }
                    .background(inviteCodeInput.trimmingCharacters(in: .whitespaces).isEmpty ? EnterpriseTheme.accent.opacity(0.4) : EnterpriseTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .disabled(inviteCodeInput.trimmingCharacters(in: .whitespaces).isEmpty || isJoiningOrg)
                }
                .padding(.horizontal, 16)

                if let error = joinOrgError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(EnterpriseTheme.danger)
                        .padding(.horizontal, 16)
                }

                Spacer().frame(height: 2)
            }
        }
        .alert("Joined Organization", isPresented: $showJoinOrgSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You've successfully joined the organization. Your plan has been updated.")
        }
    }

    // MARK: - Danger

    private var dangerSection: some View {
        SettingsSection(label: "ACCOUNT ACTIONS") {
            SettingsRow(
                icon: "rectangle.portrait.and.arrow.right",
                iconColor: EnterpriseTheme.danger,
                title: "Sign Out",
                titleColor: EnterpriseTheme.danger,
                action: { Task { await appViewModel.signOut() } }
            )

            SettingsDivider()

            SettingsRow(
                icon: "trash",
                iconColor: EnterpriseTheme.danger,
                title: "Delete Account",
                titleColor: EnterpriseTheme.danger,
                action: { showDeleteConfirmation = true }
            )
        }
    }

    // MARK: - Footer

    private var versionFooter: some View {
        Text("LoadScan \(appVersion)\nMade with care.")
            .font(.system(size: 11))
            .foregroundStyle(EnterpriseTheme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Reusable Section Shell

private struct SettingsSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1.4)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
            .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Row

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var titleColor: Color = EnterpriseTheme.textPrimary
    var showChevron: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    init(
        icon: String,
        iconColor: Color,
        title: String,
        titleColor: Color = EnterpriseTheme.textPrimary,
        showChevron: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon        = icon
        self.iconColor   = iconColor
        self.title       = title
        self.titleColor  = titleColor
        self.showChevron = showChevron
        self.action      = action
        self.trailing    = trailing()
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 13) {
                // Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(titleColor)

                Spacer()

                trailing

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Divider

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(EnterpriseTheme.border)
            .frame(height: 1)
            .padding(.leading, 61)
    }
}
