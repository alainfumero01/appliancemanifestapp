import SwiftUI

struct ManifestListView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isPresentingNewManifest = false
    @State private var manifestPendingDeletion: Manifest?
    @State private var isShowingDeleteAllConfirmation = false
    @State private var bannerVisible = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                dashboardHeader
                freeTierBanner
                kpiRow
                manifestsSection
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 110)
        }
        .background(EnterpriseBackground())
        .refreshable {
            await appViewModel.refreshManifests()
        }
        .safeAreaInset(edge: .bottom) {
            EnterpriseActionBar {
                Button {
                    if appViewModel.entitlement?.canCreateManifest == false {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            appViewModel.selectedTab = 2
                        }
                    } else {
                        isPresentingNewManifest = true
                    }
                } label: {
                    Label("New Load", systemImage: "plus")
                }
                .buttonStyle(EnterprisePrimaryButtonStyle())
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingNewManifest) {
            NewManifestView(isPresented: $isPresentingNewManifest, backend: appViewModel.backend)
                .environmentObject(appViewModel)
        }
        .confirmationDialog(
            "Delete Load",
            isPresented: Binding(
                get: { manifestPendingDeletion != nil },
                set: { if !$0 { manifestPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Load", role: .destructive) {
                if let m = manifestPendingDeletion {
                    Task { await appViewModel.deleteManifest(m) }
                }
                manifestPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                manifestPendingDeletion = nil
            }
        } message: {
            Text("This will permanently remove the load manifest and all of its scanned items.")
        }
        .confirmationDialog(
            "Delete All Loads",
            isPresented: $isShowingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Loads", role: .destructive) {
                Task { await appViewModel.deleteAllManifests() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove every load manifest and all scanned items.")
        }
        .task {
            await appViewModel.refreshEntitlement()
            let isActive = appViewModel.entitlement?.subscriptionStatus == .active
            if !isActive {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.3)) {
                    bannerVisible = true
                }
            }
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            LoadScanIconView(size: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(
                    color: Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.22),
                    radius: 10, x: 0, y: 4
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("LoadScan")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                Text(appViewModel.session?.user.email ?? "")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        HStack(spacing: 10) {
            EnterpriseMetricTile(
                label: "Manifests",
                value: "\(appViewModel.manifests.count)"
            )
            EnterpriseMetricTile(
                label: "Items",
                value: "\(appViewModel.manifests.reduce(0) { $0 + $1.items.count })"
            )
            EnterpriseMetricTile(
                label: "Total MSRP",
                value: Formatters.currencyString(appViewModel.manifests.reduce(0) { $0 + $1.totalMSRP }),
                accent: EnterpriseTheme.success
            )
        }
    }

    @ViewBuilder
    private var freeTierBanner: some View {
        let isActive = appViewModel.entitlement?.subscriptionStatus == .active
        if !isActive && bannerVisible {
            let remaining = appViewModel.entitlement?.remainingFreeManifests ?? 3
            let total = appViewModel.entitlement?.trialManifestLimit ?? 3
            let used = total - remaining
            let exhausted = remaining == 0
            let accent = exhausted ? EnterpriseTheme.danger : EnterpriseTheme.accent

            HStack(spacing: 12) {
                Image(systemName: exhausted ? "lock.fill" : "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exhausted ? "Free trial complete" : "\(remaining) free load\(remaining == 1 ? "" : "s") left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)

                    HStack(spacing: 4) {
                        ForEach(0..<total, id: \.self) { i in
                            Capsule()
                                .fill(i < used ? accent : EnterpriseTheme.border)
                                .frame(width: 18, height: 3)
                        }
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appViewModel.selectedTab = 2
                    }
                } label: {
                    Text(exhausted ? "Upgrade" : "View Plans")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Manifests Section

    private var manifestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(EnterpriseTheme.textTertiary)
                        .frame(width: 12, height: 2)
                    Text("RECENT LOADS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.6)
                }
                Spacer()
                if !appViewModel.manifests.isEmpty {
                    Button {
                        isShowingDeleteAllConfirmation = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Delete All")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(EnterpriseTheme.danger)
                    }
                } else {
                    Text("\(appViewModel.manifests.count) loads")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }

            if appViewModel.manifests.isEmpty {
                emptyState
            } else {
                ForEach(appViewModel.manifests) { manifest in
                    NavigationLink(destination: ManifestDetailView(manifestID: manifest.id)) {
                        ManifestRowCard(manifest: manifest)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if manifest.status != .sold {
                            Button {
                                var updated = manifest
                                updated.status = .sold
                                Task { await appViewModel.saveManifest(updated) }
                            } label: {
                                Label("Mark as Sold", systemImage: "dollarsign.circle")
                            }
                        } else {
                            Button {
                                var updated = manifest
                                updated.status = .completed
                                Task { await appViewModel.saveManifest(updated) }
                            } label: {
                                Label("Unmark as Sold", systemImage: "arrow.uturn.backward.circle")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            manifestPendingDeletion = manifest
                        } label: {
                            Label("Delete Load", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            var updated = manifest
                            updated.status = manifest.status == .sold ? .completed : .sold
                            Task { await appViewModel.saveManifest(updated) }
                        } label: {
                            Label(manifest.status == .sold ? "Unmark Sold" : "Mark Sold",
                                  systemImage: manifest.status == .sold ? "arrow.uturn.backward" : "dollarsign.circle.fill")
                        }
                        .tint(manifest.status == .sold ? EnterpriseTheme.textTertiary : Color(red: 0.4, green: 0.3, blue: 0.8))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            manifestPendingDeletion = manifest
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.2")
                .font(.system(size: 30))
                .foregroundStyle(EnterpriseTheme.textTertiary)
            VStack(spacing: 4) {
                Text("No manifests yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                Text("Tap New Load to begin your first manifest.")
                    .font(.subheadline)
                    .foregroundStyle(EnterpriseTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(EnterpriseTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
    }
}

// MARK: - Manifest Row Card

private struct ManifestRowCard: View {
    let manifest: Manifest

    var body: some View {
        EnterpriseCard(accentLeft: manifest.status.badgeTint) {
            HStack(alignment: .top) {
                // Left: title, load ref, badges
                VStack(alignment: .leading, spacing: 8) {
                    Text(manifest.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                        .lineLimit(1)

                    Text("LOAD \(manifest.loadReference.uppercased())")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textSecondary)

                    HStack(spacing: 8) {
                        StatusBadge(text: manifest.status.displayLabel, tint: manifest.status.badgeTint)
                        Text("·")
                            .font(.footnote)
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                        Text("\(manifest.items.count) items")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                    }
                    if let email = manifest.ownerEmail {
                        Label(email, systemImage: "person.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Right: value + date + chevron
                VStack(alignment: .trailing, spacing: 8) {
                    Text(Formatters.currencyString(manifest.totalMSRP))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text(Formatters.mediumDate.string(from: manifest.updatedAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }
        }
    }
}
