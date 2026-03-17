import StoreKit
import SwiftUI
import UIKit

// MARK: - Membership Tab

struct MembershipView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var isPurchasing = false
    @State private var purchasingPlanID: LoadScanPlanID?
    @State private var isOpeningManageSubscriptions = false

    private let upgradeablePlans: [LoadScanPlanID] = [
        .individualMonthly,
        .enterprise5Monthly,
        .enterprise10Monthly,
        .enterprise15Monthly
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                accountHeader
                planStatusCard
                plansSection
                if isEnterpriseOwner { teamSection }
                if isEnterpriseOwner { inviteCodesSection }
                accountFooter
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background(EnterpriseBackground())
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await subscriptionService.loadProducts()
            await appViewModel.refreshEntitlement()
            if appViewModel.entitlement?.isEnterprise == true {
                await appViewModel.loadOrgMembers()
                await appViewModel.loadInviteCodes()
            }
        }
    }

    private var isEnterpriseOwner: Bool {
        appViewModel.entitlement?.isEnterprise == true &&
        appViewModel.entitlement?.isOwner == true
    }

    private var currentPlan: LoadScanPlanID? {
        guard appViewModel.entitlement?.subscriptionStatus == .active else { return nil }
        return appViewModel.entitlement?.currentPlan
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        let email = appViewModel.session?.user.email ?? ""
        let initial = String(email.prefix(1)).uppercased()
        let isActive = appViewModel.entitlement?.subscriptionStatus == .active
        let planName = appViewModel.entitlement?.currentPlan.displayName ?? "Free Trial"

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(EnterpriseTheme.accentDim)
                    .frame(width: 46, height: 46)
                Text(initial)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(email)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(isActive ? EnterpriseTheme.success : EnterpriseTheme.warning)
                        .frame(width: 6, height: 6)
                    Text(planName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? EnterpriseTheme.success : EnterpriseTheme.warning)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }

    // MARK: - Plan Status Card

    @ViewBuilder
    private var planStatusCard: some View {
        if let entitlement = appViewModel.entitlement, entitlement.subscriptionStatus == .active {
            activePlanCard(entitlement: entitlement)
        } else {
            freeTierCard
        }
    }

    private func activePlanCard(entitlement: OrganizationEntitlement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(EnterpriseTheme.success)
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.success)
                            .tracking(1.4)
                    }
                    Text(entitlement.currentPlan.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                }
                Spacer()
                Text(Formatters.currencyString(entitlement.currentPlan.monthlyPrice) + "/mo")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .padding(.top, 2)
            }

            Rectangle()
                .fill(EnterpriseTheme.border)
                .frame(height: 1)

            HStack(spacing: 24) {
                planStat(label: "Seats", value: "\(entitlement.memberCount)/\(entitlement.seatLimit)")
                planStat(label: "Manifests", value: "Unlimited")
                if let expiry = entitlement.subscriptionExpiresAt {
                    planStat(label: "Renews", value: Formatters.mediumDate.string(from: expiry))
                }
            }

            Text("Need a different plan? You can switch tiers below at any time.")
                .font(.system(size: 12))
                .foregroundStyle(EnterpriseTheme.textSecondary)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EnterpriseTheme.success.opacity(0.28), lineWidth: 1.5)
        }
        .shadow(color: EnterpriseTheme.success.opacity(0.07), radius: 6, x: 0, y: 2)
    }

    private var freeTierCard: some View {
        let remaining = appViewModel.entitlement?.remainingFreeManifests ?? 3
        let total = appViewModel.entitlement?.trialManifestLimit ?? 3
        let used = total - remaining
        let fraction = min(Double(used) / Double(max(total, 1)), 1.0)
        let exhausted = remaining == 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FREE TRIAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                        .tracking(1.4)
                    Text(exhausted ? "Trial complete" : "\(remaining) load\(remaining == 1 ? "" : "s") remaining")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(exhausted ? EnterpriseTheme.danger : EnterpriseTheme.textPrimary)
                }
                Spacer()
                Text("\(used)/\(total)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .padding(.top, 2)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(EnterpriseTheme.backgroundSecondary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(exhausted ? EnterpriseTheme.danger : EnterpriseTheme.accent)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0), height: 6)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
                }
            }
            .frame(height: 6)

            Text("Upgrade for unlimited loads and optional team access.")
                .font(.system(size: 13))
                .foregroundStyle(EnterpriseTheme.textSecondary)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }

    // MARK: - Plans Section

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(currentPlan == nil ? "CHOOSE A PLAN" : "CHANGE PLAN")

            ForEach(upgradeablePlans) { plan in
                planCard(plan)
            }

            purchaseHelpCard

            Button {
                Task { await restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(EnterpriseTheme.border, lineWidth: 1)
                    }
            }

            Button {
                Task { await manageSubscriptions() }
            } label: {
                if isOpeningManageSubscriptions {
                    ProgressView()
                        .tint(EnterpriseTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Manage App Store Subscriptions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
            .disabled(isOpeningManageSubscriptions)
        }
    }

    private var purchaseHelpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions are billed through the App Store.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EnterpriseTheme.textPrimary)
            Text("Apple uses the App Store account signed into Media & Purchases on this device. If Apple asks for a password, that's the App Store account confirmation step, not your LoadScan login.")
                .font(.system(size: 12))
                .foregroundStyle(EnterpriseTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
    }

    private func planCard(_ plan: LoadScanPlanID) -> some View {
        let isEnterprise = plan.isEnterprise
        let accentColor = isEnterprise ? EnterpriseTheme.warning : EnterpriseTheme.accent
        let isPurchasingThis = purchasingPlanID == plan
        let isCurrentPlan = currentPlan == plan
        let buttonTitle: String = {
            if isCurrentPlan { return "Current Plan" }
            return currentPlan == nil ? "Subscribe" : "Switch Plan"
        }()

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(plan.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)

                    if isCurrentPlan {
                        Text("Current")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(EnterpriseTheme.success.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text(plan.marketingDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(priceLabel(for: plan))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textPrimary)

                Button {
                    Task { await purchase(plan) }
                } label: {
                    ZStack {
                        if isPurchasingThis {
                            ProgressView().tint(.white).scaleEffect(0.75)
                        } else {
                            Text(buttonTitle)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 32)
                    .background(isCurrentPlan ? EnterpriseTheme.textTertiary : accentColor)
                    .clipShape(Capsule())
                }
                .disabled(isPurchasing || isCurrentPlan)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    (isCurrentPlan ? EnterpriseTheme.success : accentColor)
                        .opacity(isCurrentPlan ? 0.25 : (isEnterprise ? 0.25 : 0.15)),
                    lineWidth: 1
                )
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }

    // MARK: - Team Section

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("TEAM")

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite your team")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text("Generate invite codes for teammates to join your organization.")
                        .font(.system(size: 12))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                }

                Button("Generate Invite Codes") {
                    Task { await appViewModel.generateInviteLink() }
                }
                .buttonStyle(EnterprisePrimaryButtonStyle())
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
            .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)

            if !appViewModel.orgMembers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(appViewModel.orgMembers) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.email)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(EnterpriseTheme.textPrimary)
                                Text(member.role.capitalized)
                                    .font(.system(size: 11))
                                    .foregroundStyle(EnterpriseTheme.textTertiary)
                            }
                            Spacer()
                            if member.role.lowercased() != "owner" {
                                Button("Remove") {
                                    Task { await appViewModel.removeOrgMember(member) }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(EnterpriseTheme.danger)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if member.id != appViewModel.orgMembers.last?.id {
                            Rectangle()
                                .fill(EnterpriseTheme.border)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                }
                .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
            }
        }
        .task {
            await appViewModel.loadOrgMembers()
            await appViewModel.loadInviteCodes()
        }
    }

    // MARK: - Invite Codes Section

    @ViewBuilder
    private var inviteCodesSection: some View {
        let codes = appViewModel.inviteCodes.filter { $0.isActive || $0.usageCount > 0 }
        if !codes.isEmpty && appViewModel.entitlement?.isOwner == true {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("TEAM INVITE CODES")

                VStack(spacing: 0) {
                    ForEach(Array(codes.enumerated()), id: \.element.id) { index, code in
                        if index > 0 {
                            Rectangle()
                                .fill(EnterpriseTheme.border)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                        HStack(spacing: 12) {
                            Text(code.code)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(code.isUsed ? EnterpriseTheme.textTertiary : EnterpriseTheme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(code.isUsed ? "Used" : "Available")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(code.isUsed ? EnterpriseTheme.textTertiary : EnterpriseTheme.success)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background((code.isUsed ? EnterpriseTheme.textTertiary : EnterpriseTheme.success).opacity(0.1))
                                .clipShape(Capsule())

                            if !code.isUsed {
                                Button {
                                    UIPasteboard.general.string = code.code
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(EnterpriseTheme.accent)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                }
                .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
            }
        }
    }

    // MARK: - Account Footer

    private var accountFooter: some View {
        Button {
            Task { await appViewModel.signOut() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                Text("Sign Out")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(EnterpriseTheme.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(EnterpriseTheme.danger.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EnterpriseTheme.danger.opacity(0.15), lineWidth: 1)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(EnterpriseTheme.textTertiary)
            .tracking(1.4)
    }

    private func planStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EnterpriseTheme.textPrimary)
        }
    }

    private func priceLabel(for plan: LoadScanPlanID) -> String {
        if let product = subscriptionService.product(for: plan) {
            return "\(product.displayPrice)/mo"
        }
        return "\(Formatters.currencyString(plan.monthlyPrice))/mo"
    }

    private func purchase(_ plan: LoadScanPlanID) async {
        isPurchasing = true
        purchasingPlanID = plan
        defer { isPurchasing = false; purchasingPlanID = nil }
        do {
            let result = try await subscriptionService.purchase(plan: plan)
            await appViewModel.syncSubscription(productID: result.productID, transactionJWS: result.transactionJWS)
        } catch is CancellationError {
            // Closing Apple's purchase sheet is an expected user action.
        } catch {
            appViewModel.errorMessage = error.userMessage
        }
    }

    private func restorePurchases() async {
        do {
            try await subscriptionService.restorePurchases()
            await appViewModel.refreshEntitlement()
            if appViewModel.entitlement?.isEnterprise == true {
                await appViewModel.loadOrgMembers()
                await appViewModel.loadInviteCodes()
            }
        } catch {
            guard !error.isExpectedCancellation else { return }
            appViewModel.errorMessage = error.userMessage
        }
    }

    private func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            appViewModel.errorMessage = "We couldn't open App Store subscriptions right now."
            return
        }

        isOpeningManageSubscriptions = true
        defer { isOpeningManageSubscriptions = false }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            guard !error.isExpectedCancellation else { return }
            appViewModel.errorMessage = error.userMessage
        }
    }
}
