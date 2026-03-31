import SwiftUI
import UIKit

struct ManifestListView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isPresentingNewManifest = false
    @State private var manifestPendingDeletion: Manifest?
    @State private var isShowingDeleteAllConfirmation = false
    @State private var bannerVisible = false

    var body: some View {
        Group {
            if appViewModel.appMode == .seller {
                SellerInventoryHubView(backend: appViewModel.backend)
            } else {
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

private enum SellerInventorySegment: String, CaseIterable, Identifiable {
    case inventory = "Inventory"
    case loads = "Loads"

    var id: String { rawValue }
}

private struct SellerInventoryHubView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var selectedSegment: SellerInventorySegment = .inventory
    @State private var isPresentingQuickLoadBuilder = false
    @State private var isPresentingInventoryIntake = false
    @State private var isPresentingNewManifest = false

    let backend: BackendServicing

    private var groupedByCategory: [(String, [InventoryGroupRow])] {
        Dictionary(grouping: appViewModel.inventoryGroups, by: \.applianceCategory)
            .map { ($0.key, $0.value.sorted { $0.productName < $1.productName }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                header

                if appViewModel.canAccessSellerMode {
                    segmentPicker

                    if selectedSegment == .inventory {
                        inventorySummary
                        inventorySection
                    } else {
                        loadsSection
                    }
                } else {
                    lockedState
                }
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(EnterpriseBackground())
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await appViewModel.refreshEntitlement()
            await appViewModel.refreshManifests()
            await appViewModel.ensureSellerDataReady()
        }
        .safeAreaInset(edge: .bottom) {
            sellerActionBar
        }
        .sheet(isPresented: $isPresentingQuickLoadBuilder) {
            QuickLoadBuilderView(isPresented: $isPresentingQuickLoadBuilder)
                .environmentObject(appViewModel)
        }
        .sheet(isPresented: $isPresentingInventoryIntake) {
            SellerInventoryIntakeView(isPresented: $isPresentingInventoryIntake, backend: backend)
                .environmentObject(appViewModel)
        }
        .sheet(isPresented: $isPresentingNewManifest) {
            NewManifestView(isPresented: $isPresentingNewManifest, backend: backend)
                .environmentObject(appViewModel)
        }
        .task {
            await appViewModel.ensureSellerDataReady()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppModePicker(selection: Binding(
                get: { appViewModel.appMode },
                set: { newValue in
                    appViewModel.setAppMode(newValue)
                    if newValue == .seller {
                        Task { await appViewModel.ensureSellerDataReady() }
                    }
                }
            ))

            Text("Seller Inventory")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EnterpriseTheme.textSecondary)
            Text("Stock you can act on right now")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textPrimary)
            Text("Track available units, reserve them into quick loads, and keep your current wholesale load flow intact.")
                .font(.subheadline)
                .foregroundStyle(EnterpriseTheme.textSecondary)
        }
    }

    private var segmentPicker: some View {
        Picker("Seller Segment", selection: $selectedSegment) {
            ForEach(SellerInventorySegment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .tint(EnterpriseTheme.accent)
    }

    private var inventorySummary: some View {
        HStack(spacing: 10) {
            EnterpriseMetricTile(label: "Active Units", value: "\(appViewModel.inventoryUnits.filter { $0.status != .sold }.count)")
            EnterpriseMetricTile(label: "Available for Load", value: "\(appViewModel.inventoryUnits.filter(\.isAvailableForQuickLoad).count)", accent: EnterpriseTheme.success)
            EnterpriseMetricTile(label: "Groups", value: "\(appViewModel.inventoryGroups.count)", accent: EnterpriseTheme.warning)
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        if groupedByCategory.isEmpty {
            EnterpriseCard {
                EnterpriseSectionHeader(
                    eyebrow: "Inventory",
                    title: "No stock in seller inventory yet",
                    subtitle: "Import your existing loads or add appliances directly by scan or manual lookup."
                )

                HStack(spacing: 12) {
                    Button {
                        isPresentingInventoryIntake = true
                    } label: {
                        Label("Add Inventory", systemImage: "plus")
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())

                    Button {
                        Task { await appViewModel.ensureSellerDataReady() }
                    } label: {
                        Label("Import My Loads", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(EnterpriseSecondaryButtonStyle())
                }
            }
        } else {
            ForEach(groupedByCategory, id: \.0) { category, rows in
                VStack(alignment: .leading, spacing: 12) {
                    Text(category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.4)

                    ForEach(rows) { row in
                        NavigationLink(destination: InventoryGroupDetailView(group: row)) {
                            InventoryGroupCard(group: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loadsSection: some View {
        EnterpriseCard {
            EnterpriseSectionHeader(
                eyebrow: "Quick Loads",
                title: "Seller loads stay standard",
                subtitle: "Quick Load Builder creates the same manifest type you already use. Seller mode just helps you build it from live stock faster."
            )

            HStack(spacing: 12) {
                Button {
                    isPresentingQuickLoadBuilder = true
                } label: {
                    Label("Quick Load Builder", systemImage: "bolt.fill")
                }
                .buttonStyle(EnterprisePrimaryButtonStyle())

                Button {
                    isPresentingNewManifest = true
                } label: {
                    Label("Manual New Load", systemImage: "square.and.pencil")
                }
                .buttonStyle(EnterpriseSecondaryButtonStyle())
            }
        }

        if appViewModel.manifests.isEmpty {
            EnterpriseCard {
                Text("No manifests yet. Build one from inventory or start a manual load.")
                    .font(.subheadline)
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT LOADS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .tracking(1.4)

                ForEach(appViewModel.manifests.prefix(12)) { manifest in
                    NavigationLink(destination: ManifestDetailView(manifestID: manifest.id)) {
                        ManifestRowCard(manifest: manifest)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lockedState: some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.warning) {
            EnterpriseSectionHeader(
                eyebrow: "Seller Mode",
                title: "Upgrade to manage appliance inventory",
                subtitle: "Seller mode is part of paid Individual and Enterprise plans so you can track stock, reserve units into loads, and see what is moving."
            )

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    appViewModel.selectedTab = 2
                }
            } label: {
                Label("View Membership", systemImage: "creditcard")
            }
            .buttonStyle(EnterprisePrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var sellerActionBar: some View {
        if appViewModel.canAccessSellerMode {
            EnterpriseActionBar {
                if selectedSegment == .inventory {
                    Button {
                        isPresentingInventoryIntake = true
                    } label: {
                        Label("Add Inventory", systemImage: "plus")
                    }
                    .buttonStyle(EnterpriseSecondaryButtonStyle())

                    Button {
                        isPresentingQuickLoadBuilder = true
                    } label: {
                        Label("Quick Load Builder", systemImage: "bolt.fill")
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                } else {
                    Button {
                        isPresentingNewManifest = true
                    } label: {
                        Label("Manual New Load", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(EnterpriseSecondaryButtonStyle())

                    Button {
                        isPresentingQuickLoadBuilder = true
                    } label: {
                        Label("Quick Load Builder", systemImage: "bolt.fill")
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                }
            }
        }
    }
}

private struct InventoryGroupCard: View {
    let group: InventoryGroupRow

    var body: some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.accent) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.productName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text("\(group.brand) · \(group.modelNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                    HStack(spacing: 8) {
                        StatusBadge(text: group.condition.displayLabel, tint: EnterpriseTheme.warning)
                        StatusBadge(text: group.applianceCategory, tint: EnterpriseTheme.accent)
                    }
                    HStack(spacing: 16) {
                        inventoryCount(label: "Available", value: group.availableCount, tint: EnterpriseTheme.success)
                        inventoryCount(label: "Reserved", value: group.reservedCount, tint: Color(red: 0.51, green: 0.33, blue: 0.86))
                        inventoryCount(label: "Sold", value: group.soldCount, tint: EnterpriseTheme.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(Formatters.currencyString(group.askingPrice))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text("MSRP \(Formatters.currencyString(group.msrp))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }
        }
    }

    private func inventoryCount(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1.1)
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }
}

private struct InventoryGroupDetailView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    let group: InventoryGroupRow
    @State private var selectedUnit: InventoryUnit?

    private var units: [InventoryUnit] {
        (group.availableUnits + group.reservedUnits + group.soldUnits)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                EnterpriseCard {
                    EnterpriseSectionHeader(
                        eyebrow: group.applianceCategory,
                        title: group.productName,
                        subtitle: "\(group.brand) · \(group.modelNumber)"
                    )

                    HStack(spacing: 12) {
                        metric(label: "Available", value: "\(group.availableCount)", tint: EnterpriseTheme.success)
                        metric(label: "Reserved", value: "\(group.reservedCount)", tint: Color(red: 0.51, green: 0.33, blue: 0.86))
                        metric(label: "Sold", value: "\(group.soldCount)", tint: EnterpriseTheme.textSecondary)
                    }
                }

                ForEach(units) { unit in
                    Button {
                        selectedUnit = unit
                    } label: {
                        EnterpriseCard(accentLeft: unit.status.tint) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(unit.status.displayLabel)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(unit.status.tint)
                                    Text("Condition: \(unit.condition.displayLabel)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(EnterpriseTheme.textSecondary)
                                    if let costBasis = unit.costBasis {
                                        Text("Cost Basis \(Formatters.currencyString(costBasis))")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(EnterpriseTheme.textTertiary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    Text(Formatters.currencyString(unit.askingPrice))
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundStyle(EnterpriseTheme.textPrimary)
                                    if let soldPrice = unit.soldPrice {
                                        Text("Sold \(Formatters.currencyString(soldPrice))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(EnterpriseTheme.success)
                                    }
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(EnterpriseTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(EnterpriseBackground())
        .navigationTitle("Group Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedUnit) { unit in
            InventoryUnitEditorView(unit: unit) { updated in
                await appViewModel.updateInventoryUnit(updated)
            }
        }
    }

    private func metric(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1.1)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(EnterpriseTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct InventoryUnitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var unit: InventoryUnit
    @State private var askingPriceText: String
    @State private var costBasisText: String
    @State private var soldPriceText: String
    @State private var isSaving = false
    let onSave: (InventoryUnit) async -> Bool

    init(unit: InventoryUnit, onSave: @escaping (InventoryUnit) async -> Bool) {
        _unit = State(initialValue: unit)
        _askingPriceText = State(initialValue: NSDecimalNumber(decimal: unit.askingPrice).stringValue)
        _costBasisText = State(initialValue: unit.costBasis.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _soldPriceText = State(initialValue: unit.soldPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: unit.displayCategory,
                            title: unit.productName,
                            subtitle: "\(unit.displayBrand) · \(unit.modelNumber)"
                        )

                        EnterpriseField(
                            title: "Asking Price",
                            prompt: "0.00",
                            text: $askingPriceText,
                            keyboardType: .decimalPad,
                            capitalization: .never
                        )

                        EnterpriseField(
                            title: "Cost Basis (Optional)",
                            prompt: "0.00",
                            text: $costBasisText,
                            keyboardType: .decimalPad,
                            capitalization: .never
                        )

                        if unit.status == .sold {
                            EnterpriseField(
                                title: "Sold Price",
                                prompt: "0.00",
                                text: $soldPriceText,
                                keyboardType: .decimalPad,
                                capitalization: .never
                            )
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("STATUS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textSecondary)
                                .tracking(1.2)

                            Picker("Status", selection: $unit.status) {
                                ForEach(InventoryStatus.allCases) { status in
                                    Text(status.displayLabel).tag(status)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(EnterpriseTheme.accent)
                        }
                        .padding(14)
                        .background(EnterpriseTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                                .stroke(EnterpriseTheme.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 140)
            }
            .navigationTitle("Edit Unit")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    Button("Save Changes") {
                        save()
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(isSaving || askingPriceText.decimalValue == nil)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .enterpriseScreen()
        }
    }

    private func save() {
        guard let askingPrice = askingPriceText.decimalValue else { return }
        isSaving = true
        var updated = unit
        updated.askingPrice = askingPrice
        updated.costBasis = costBasisText.decimalValue
        updated.soldPrice = unit.status == .sold ? (soldPriceText.decimalValue ?? askingPrice) : nil

        Task {
            defer { isSaving = false }
            if await onSave(updated) {
                dismiss()
            }
        }
    }
}

private struct QuickLoadBuilderView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var loadReference = ""
    @State private var selectedCounts: [String: Int] = [:]
    @State private var isSaving = false

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    private var groups: [InventoryGroupRow] {
        appViewModel.inventoryGroups.filter { $0.availableCount > 0 }
    }

    private var selectedUnitIDs: [UUID] {
        groups.flatMap { group in
            let count = min(selectedCounts[group.id] ?? 0, group.availableCount)
            return Array(group.availableUnits.prefix(count).map(\.id))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: "Quick Load",
                            title: "Build a load from available stock",
                            subtitle: "Pick quantities from grouped inventory. LoadScan will reserve those exact units into a standard manifest."
                        )

                        EnterpriseField(
                            title: "Load Title",
                            prompt: "Friday floor load",
                            text: $title
                        )

                        EnterpriseField(
                            title: "Load Reference (Optional)",
                            prompt: "LOAD-102",
                            text: $loadReference,
                            capitalization: .never
                        )
                    }

                    if groups.isEmpty {
                        EnterpriseCard {
                            Text("No in-stock or listed units are available for a quick load.")
                                .font(.subheadline)
                                .foregroundStyle(EnterpriseTheme.textSecondary)
                        }
                    } else {
                        ForEach(groups) { group in
                            EnterpriseCard(accentLeft: EnterpriseTheme.accent) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(group.productName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(EnterpriseTheme.textPrimary)
                                        Text("\(group.brand) · \(group.modelNumber)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(EnterpriseTheme.textSecondary)
                                        HStack(spacing: 10) {
                                            StatusBadge(text: group.condition.displayLabel, tint: EnterpriseTheme.warning)
                                            Text("\(group.availableCount) available")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(EnterpriseTheme.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(Formatters.currencyString(group.askingPrice))
                                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                                            .foregroundStyle(EnterpriseTheme.textPrimary)
                                        Stepper(
                                            value: Binding(
                                                get: { selectedCounts[group.id] ?? 0 },
                                                set: { selectedCounts[group.id] = $0 }
                                            ),
                                            in: 0...group.availableCount
                                        ) {
                                            Text("Qty \(selectedCounts[group.id] ?? 0)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(EnterpriseTheme.accent)
                                        }
                                        .labelsHidden()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 140)
            }
            .navigationTitle("Quick Load Builder")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    Button("Create Quick Load") {
                        save()
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(isSaving || selectedUnitIDs.isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .enterpriseScreen()
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Quick Load" : title
            let resolvedReference = loadReference.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = await appViewModel.createQuickLoad(
                title: resolvedTitle,
                loadReference: resolvedReference.isEmpty ? "LOAD-\(Int(Date().timeIntervalSince1970))" : resolvedReference,
                inventoryUnitIDs: selectedUnitIDs
            )
            if success {
                isPresented = false
                dismiss()
            }
        }
    }
}

private struct SellerInventoryIntakeView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @StateObject private var viewModel: NewManifestViewModel
    @State private var isShowingCamera = false
    @State private var selectedSourceType: UIImagePickerController.SourceType = .camera
    @State private var isChoosingPhotoSource = false
    @State private var showNotApplianceToast = false
    @State private var pendingPhotoLookup: SellerPendingPhotoLookup?
    @FocusState private var focusedField: SellerField?
    @State private var isSavingInventory = false

    private enum SellerField {
        case manualModel
    }

    init(isPresented: Binding<Bool>, backend: BackendServicing) {
        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue: NewManifestViewModel(backend: backend))
    }

    private var canSaveInventory: Bool {
        !viewModel.draftItems.isEmpty && viewModel.draftItems.allSatisfy {
            !$0.modelNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.quantity > 0 &&
            $0.ourPriceText.decimalValue != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intakeHeader
                    scanCard
                    queueSection
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 140)
            }
            .navigationTitle("Add Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    if focusedField != nil {
                        Button("Dismiss Keyboard") { focusedField = nil }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())
                    }
                    Button("Save to Inventory") {
                        focusedField = nil
                        saveInventory()
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(!canSaveInventory || isSavingInventory)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Choose Photo Source",
                isPresented: $isChoosingPhotoSource,
                titleVisibility: .visible
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        selectedSourceType = .camera
                        isShowingCamera = true
                    }
                }
                Button("Choose From Camera Roll") {
                    selectedSourceType = .photoLibrary
                    isShowingCamera = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Pick how you want to add the appliance sticker image.")
            }
            .sheet(isPresented: $isShowingCamera) {
                SellerCameraPicker(sourceType: selectedSourceType) { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        Task { await prepareScannedPhoto(data) }
                    }
                }
            }
            .sheet(item: $pendingPhotoLookup) { pending in
                SellerDetectedModelReviewView(pending: pending) { reviewed in
                    await confirmScannedPhoto(reviewed)
                }
            }
            .sheet(item: selectedDraftBinding) { draft in
                SellerDraftReviewView(draft: draft) { updated in
                    await viewModel.saveReviewedDraft(updated)
                }
            }
            .overlay {
                if viewModel.isScanning || isSavingInventory {
                    SellerScanningOverlay(message: isSavingInventory ? "Saving inventory…" : "Reading sticker and checking MSRP…")
                }
            }
            .alert("Inventory Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .overlay(alignment: .top) {
                if showNotApplianceToast {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Not an appliance — type the model number below")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EnterpriseTheme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(EnterpriseTheme.border, lineWidth: 1)
                    }
                    .shadow(color: EnterpriseTheme.shadow, radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .enterpriseScreen()
        }
    }

    private var intakeHeader: some View {
        EnterpriseCard {
            EnterpriseSectionHeader(
                eyebrow: "Seller Intake",
                title: "Add units directly to inventory",
                subtitle: "Scan a sticker or look up a model number, review the result, then save each unit into seller inventory."
            )
        }
    }

    private var scanCard: some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.accent) {
            HStack(spacing: 12) {
                Button {
                    isChoosingPhotoSource = true
                } label: {
                    Label("Scan Sticker", systemImage: "camera.fill")
                }
                .buttonStyle(EnterprisePrimaryButtonStyle())

                Button {
                    Task { await viewModel.lookupManualModelNumber() }
                } label: {
                    Label("Lookup Model", systemImage: "magnifyingglass")
                }
                .buttonStyle(EnterpriseSecondaryButtonStyle())
                .disabled(viewModel.manualModelNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            EnterpriseField(
                title: "Manual Model Number",
                prompt: "WDT750SAKZ",
                text: $viewModel.manualModelNumber,
                capitalization: .characters
            )
            .focused($focusedField, equals: .manualModel)
            .onSubmit {
                Task { await viewModel.lookupManualModelNumber() }
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        if viewModel.draftItems.isEmpty {
            EnterpriseCard {
                Text("Nothing queued yet. Scan a sticker or look up a model number to start building inventory.")
                    .font(.subheadline)
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("ITEMS TO SAVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .tracking(1.4)

                ForEach(viewModel.draftItems) { draft in
                    EnterpriseCard {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(draft.productName.isEmpty ? "Review needed" : draft.productName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(EnterpriseTheme.textPrimary)
                                Text(draft.modelNumber)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(EnterpriseTheme.textSecondary)
                                HStack(spacing: 8) {
                                    StatusBadge(text: draft.condition.displayLabel, tint: EnterpriseTheme.warning)
                                    StatusBadge(text: draft.lookupStatus.displayLabel, tint: draft.lookupStatus.badgeTint)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(Formatters.currencyString(draft.ourPriceText.decimalValue ?? 0))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(EnterpriseTheme.textPrimary)
                                Text("Qty \(draft.quantity)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(EnterpriseTheme.textTertiary)
                                Button(role: .destructive) {
                                    viewModel.removeDraft(id: draft.id)
                                } label: {
                                    Text("Remove")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        viewModel.selectedDraftID = draft.id
                    }
                }
            }
        }
    }

    private var selectedDraftBinding: Binding<DraftManifestItem?> {
        Binding(
            get: {
                guard let id = viewModel.selectedDraftID else { return nil }
                return viewModel.draftItems.first(where: { $0.id == id })
            },
            set: { newValue in
                if let newValue {
                    viewModel.updateDraft(newValue)
                }
                viewModel.selectedDraftID = nil
            }
        )
    }

    private func prepareScannedPhoto(_ data: Data) async {
        do {
            let detectedModel = try await viewModel.detectModelNumberForPhoto(data: data)
            pendingPhotoLookup = SellerPendingPhotoLookup(
                imageData: data,
                detectedModelNumber: detectedModel,
                modelNumber: detectedModel,
                helperText: "Confirm the detected model number before LoadScan looks up the product."
            )
        } catch AppError.notAppliance {
            try? await Task.sleep(nanoseconds: 600_000_000)
            showNotApplianceToast = true
            focusedField = .manualModel
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                showNotApplianceToast = false
            }
        } catch {
            pendingPhotoLookup = SellerPendingPhotoLookup(
                imageData: data,
                detectedModelNumber: "",
                modelNumber: "",
                helperText: "LoadScan could not confidently read the sticker. Enter the model number manually to continue."
            )
        }
    }

    private func confirmScannedPhoto(_ pending: SellerPendingPhotoLookup) async -> Bool {
        do {
            try await viewModel.lookupScannedModelNumber(
                pending.modelNumber,
                imageData: pending.imageData,
                observedModelNumber: pending.detectedModelNumber
            )
            pendingPhotoLookup = nil
            return true
        } catch {
            viewModel.errorMessage = error.userMessage
            return false
        }
    }

    private func saveInventory() {
        isSavingInventory = true
        Task {
            defer { isSavingInventory = false }
            while let draft = viewModel.draftItems.first {
                let askingPrice = draft.ourPriceText.decimalValue ?? draft.msrpText.decimalValue ?? 0
                let succeeded = await appViewModel.createInventoryUnits(
                    from: draft,
                    quantity: draft.quantity,
                    askingPrice: askingPrice,
                    costBasis: nil,
                    status: .inStock
                )
                if !succeeded {
                    return
                }
                viewModel.removeDraft(id: draft.id)
            }
            isPresented = false
            dismiss()
        }
    }
}

private struct SellerPendingPhotoLookup: Identifiable, Equatable {
    let id = UUID()
    let imageData: Data
    let detectedModelNumber: String
    var modelNumber: String
    let helperText: String
}

private struct SellerDetectedModelReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: SellerPendingPhotoLookup
    @FocusState private var focusedField: Bool
    let onConfirm: (SellerPendingPhotoLookup) async -> Bool

    init(pending: SellerPendingPhotoLookup, onConfirm: @escaping (SellerPendingPhotoLookup) async -> Bool) {
        _pending = State(initialValue: pending)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: "Scan Check",
                            title: "Confirm model number",
                            subtitle: pending.helperText
                        )

                        if let image = UIImage(data: pending.imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                                }
                        }

                        EnterpriseField(
                            title: "Detected Model Number",
                            prompt: "Enter model number",
                            text: $pending.modelNumber,
                            capitalization: .characters
                        )
                        .focused($focusedField)
                    }
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Sticker Read")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    Button("Search Product") {
                        pending.modelNumber = ModelNumberNormalizer.normalize(pending.modelNumber)
                        Task {
                            if await onConfirm(pending) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(pending.modelNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .enterpriseScreen()
        }
    }
}

private struct SellerDraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: DraftManifestItem
    @FocusState private var focusedField: Field?
    let onSave: (DraftManifestItem) async -> Void

    private enum Field {
        case model, name, msrp, ourPrice
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: "Review",
                            title: "Confirm inventory details",
                            subtitle: "Asking price comes from the Our Price field."
                        )

                        EnterpriseField(title: "Model Number", prompt: "Enter model number", text: $draft.modelNumber, capitalization: .characters)
                            .focused($focusedField, equals: .model)
                        EnterpriseField(title: "Product Name", prompt: "Enter product name", text: $draft.productName)
                            .focused($focusedField, equals: .name)
                        EnterpriseField(title: "MSRP", prompt: "0.00", text: $draft.msrpText, keyboardType: .decimalPad, capitalization: .never)
                            .focused($focusedField, equals: .msrp)
                        EnterpriseField(title: "Asking Price", prompt: "0.00", text: $draft.ourPriceText, keyboardType: .decimalPad, capitalization: .never)
                            .focused($focusedField, equals: .ourPrice)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("CONDITION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textSecondary)
                                .tracking(1.2)

                            Picker("Condition", selection: $draft.condition) {
                                ForEach(ItemCondition.allCases) { condition in
                                    Text(condition.displayLabel).tag(condition)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(EnterpriseTheme.accent)
                        }
                        .padding(14)
                        .background(EnterpriseTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                                .stroke(EnterpriseTheme.border, lineWidth: 1)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("QUANTITY")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(EnterpriseTheme.textSecondary)
                                    .tracking(1.2)
                                Text("\(draft.quantity)")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .foregroundStyle(EnterpriseTheme.textPrimary)
                            }
                            Spacer()
                            Stepper("", value: $draft.quantity, in: 1...50)
                                .labelsHidden()
                                .tint(EnterpriseTheme.accent)
                        }
                        .padding(14)
                        .background(EnterpriseTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                                .stroke(EnterpriseTheme.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Review Item")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    Button("Save Item") {
                        draft.modelNumber = ModelNumberNormalizer.normalize(draft.modelNumber)
                        Task {
                            await onSave(draft)
                            dismiss()
                        }
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .enterpriseScreen()
        }
    }
}

private struct SellerScanningOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(EnterpriseTheme.accent)
                    .scaleEffect(1.2)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct SellerCameraPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }
    }
}

private extension InventoryStatus {
    var tint: Color {
        switch self {
        case .inStock: return EnterpriseTheme.success
        case .listed: return EnterpriseTheme.warning
        case .reserved: return Color(red: 0.51, green: 0.33, blue: 0.86)
        case .sold: return EnterpriseTheme.textSecondary
        }
    }
}

private extension String {
    var decimalValue: Decimal? {
        Decimal(string: trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
