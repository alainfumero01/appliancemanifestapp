import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    // MARK: - Derived data

    private var allManifests: [Manifest] { appViewModel.manifests }

    private var activeManifests: [Manifest] {
        allManifests.filter { $0.status != .sold }
    }
    private var soldManifests: [Manifest] {
        allManifests.filter { $0.status == .sold }
    }

    private var totalActiveItems: Int {
        activeManifests.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.quantity } }
    }
    private var totalActiveMSRP: Decimal {
        activeManifests.reduce(0) { $0 + $1.totalMSRP }
    }
    // Only manifests where load cost was entered via Load Pricing mode
    private var pricedSoldManifests: [Manifest] {
        soldManifests.filter { $0.loadCost != nil }
    }
    private var pricedActiveManifests: [Manifest] {
        activeManifests.filter { $0.loadCost != nil }
    }

    private var totalSoldRevenue: Decimal {
        pricedSoldManifests.reduce(0) { $0 + $1.totalOurPrice }
    }
    private var totalSoldCost: Decimal {
        pricedSoldManifests.compactMap(\.loadCost).reduce(0, +)
    }
    private var totalSoldProfit: Decimal {
        totalSoldRevenue - totalSoldCost
    }
    private var totalPipelineRevenue: Decimal {
        pricedActiveManifests.reduce(0) { $0 + $1.totalOurPrice }
    }
    private var totalPipelineCost: Decimal {
        pricedActiveManifests.compactMap(\.loadCost).reduce(0, +)
    }
    private var totalPipelineProfit: Decimal {
        totalPipelineRevenue - totalPipelineCost
    }

    // Sorted oldest → newest for aging view
    private var agingManifests: [Manifest] {
        activeManifests.sorted { $0.createdAt < $1.createdAt }
    }

    // Condition breakdown across all active items
    private var conditionCounts: [(condition: ItemCondition, count: Int)] {
        let all = activeManifests.flatMap(\.items)
        return ItemCondition.allCases.compactMap { condition in
            let count = all.filter { $0.condition == condition }.reduce(0) { $0 + $1.quantity }
            return count > 0 ? (condition, count) : nil
        }
    }
    private var totalConditionCount: Int { conditionCounts.reduce(0) { $0 + $1.count } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                dashboardHeader
                kpiGrid
                if !pricedSoldManifests.isEmpty || !pricedActiveManifests.isEmpty { revenueCard }
                if !activeManifests.isEmpty { agingSection }
                if !conditionCounts.isEmpty { conditionSection }
                if allManifests.isEmpty { emptyState }
            }
            .padding(.horizontal, EnterpriseTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(EnterpriseBackground())
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appViewModel.refreshManifests() }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EnterpriseTheme.textSecondary)
            Text("Inventory Overview")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textPrimary)
            Text(todayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(EnterpriseTheme.textTertiary)
        }
    }

    // MARK: - KPI Grid

    private var kpiGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                KPITile(
                    label: "Active Loads",
                    value: "\(activeManifests.count)",
                    icon: "shippingbox.fill",
                    color: EnterpriseTheme.accent
                )
                KPITile(
                    label: "Items in Stock",
                    value: "\(totalActiveItems)",
                    icon: "tag.fill",
                    color: EnterpriseTheme.warning
                )
            }
            HStack(spacing: 10) {
                KPITile(
                    label: "Stock Value",
                    value: Formatters.currencyString(totalActiveMSRP),
                    icon: "dollarsign.circle.fill",
                    color: EnterpriseTheme.success,
                    isMonospaced: true
                )
                KPITile(
                    label: "Loads Sold",
                    value: "\(soldManifests.count)",
                    icon: "checkmark.seal.fill",
                    color: Color(red: 0.4, green: 0.3, blue: 0.8)
                )
            }
        }
    }

    // MARK: - Revenue Card

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(label: "PROFIT & REVENUE", icon: "chart.line.uptrend.xyaxis", color: EnterpriseTheme.success)

            // Sold loads section
            if !pricedSoldManifests.isEmpty {
                VStack(spacing: 0) {
                    // Top: Cost → Revenue → Profit
                    HStack(spacing: 0) {
                        revenueStatCell(
                            label: "LOAD COST",
                            value: Formatters.currencyString(totalSoldCost),
                            color: EnterpriseTheme.danger
                        )
                        Divider().frame(height: 56)
                        revenueStatCell(
                            label: "REVENUE",
                            value: Formatters.currencyString(totalSoldRevenue),
                            color: EnterpriseTheme.accent
                        )
                        Divider().frame(height: 56)
                        revenueStatCell(
                            label: "PROFIT",
                            value: Formatters.currencyString(totalSoldProfit),
                            color: totalSoldProfit >= 0 ? EnterpriseTheme.success : EnterpriseTheme.danger
                        )
                    }
                    .padding(.vertical, 14)

                    // Margin bar
                    if totalSoldRevenue > 0 {
                        let marginPct = NSDecimalNumber(decimal: totalSoldProfit / totalSoldRevenue).doubleValue
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(pricedSoldManifests.count) sold load\(pricedSoldManifests.count == 1 ? "" : "s") · Profit margin")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(EnterpriseTheme.textSecondary)
                                Spacer()
                                Text(String(format: "%.1f%%", max(marginPct * 100, 0)))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(marginPct >= 0 ? EnterpriseTheme.success : EnterpriseTheme.danger)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(EnterpriseTheme.border)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(marginPct >= 0 ? EnterpriseTheme.success : EnterpriseTheme.danger)
                                        .frame(width: geo.size.width * min(max(marginPct, 0), 1), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                }
                .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
            }

            // Active pipeline section
            if !pricedActiveManifests.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(EnterpriseTheme.accent)
                        Text("PIPELINE — \(pricedActiveManifests.count) active load\(pricedActiveManifests.count == 1 ? "" : "s")")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.textSecondary)
                            .tracking(1.2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Divider()

                    HStack(spacing: 0) {
                        revenueStatCell(
                            label: "INVESTED",
                            value: Formatters.currencyString(totalPipelineCost),
                            color: EnterpriseTheme.warning
                        )
                        Divider().frame(height: 56)
                        revenueStatCell(
                            label: "EXPECTED REV",
                            value: Formatters.currencyString(totalPipelineRevenue),
                            color: EnterpriseTheme.accent
                        )
                        Divider().frame(height: 56)
                        revenueStatCell(
                            label: "EXPECTED PROFIT",
                            value: Formatters.currencyString(totalPipelineProfit),
                            color: totalPipelineProfit >= 0 ? EnterpriseTheme.success : EnterpriseTheme.danger
                        )
                    }
                    .padding(.vertical, 14)
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

    private func revenueStatCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Aging Section

    private var agingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(label: "AGING INVENTORY", icon: "clock.fill", color: EnterpriseTheme.warning)

            VStack(spacing: 0) {
                ForEach(Array(agingManifests.enumerated()), id: \.element.id) { index, manifest in
                    AgingRow(manifest: manifest)
                    if index < agingManifests.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
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

    // MARK: - Condition Section

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(label: "CONDITION BREAKDOWN", icon: "chart.bar.fill", color: EnterpriseTheme.accent)

            VStack(spacing: 0) {
                ForEach(Array(conditionCounts.enumerated()), id: \.element.condition) { index, entry in
                    ConditionRow(
                        condition: entry.condition,
                        count: entry.count,
                        total: totalConditionCount
                    )
                    if index < conditionCounts.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34))
                .foregroundStyle(EnterpriseTheme.textTertiary)
            VStack(spacing: 4) {
                Text("No data yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                Text("Create your first load manifest to see inventory analytics here.")
                    .font(.subheadline)
                    .foregroundStyle(EnterpriseTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(EnterpriseTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textSecondary)
                .tracking(1.6)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

// MARK: - KPI Tile

private struct KPITile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(isMonospaced
                          ? .system(size: 22, weight: .bold, design: .monospaced)
                          : .system(size: 26, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }
}

// MARK: - Aging Row

private struct AgingRow: View {
    let manifest: Manifest

    private var daysOld: Int {
        max(Calendar.current.dateComponents([.day], from: manifest.createdAt, to: Date()).day ?? 0, 0)
    }

    private var agingColor: Color {
        switch daysOld {
        case 0..<8:  return EnterpriseTheme.success
        case 8..<22: return EnterpriseTheme.warning
        case 22..<46: return Color(red: 1.0, green: 0.5, blue: 0.1)
        default:      return EnterpriseTheme.danger
        }
    }

    private var agingLabel: String {
        switch daysOld {
        case 0:      return "Today"
        case 1:      return "1 day"
        case 2..<8:  return "\(daysOld) days"
        case 8..<15: return "1 week+"
        case 15..<22: return "2 weeks+"
        case 22..<32: return "3 weeks+"
        case 32..<62: return "\(daysOld / 30)mo+"
        default:      return "\(daysOld / 30)mo+"
        }
    }

    private var urgencyLabel: String? {
        switch daysOld {
        case 22..<46: return "Aging"
        case 46...:   return "Stale"
        default:      return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Age indicator bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(agingColor)
                .frame(width: 4)
                .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(manifest.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                        .lineLimit(1)
                    if let urgency = urgencyLabel {
                        Text(urgency)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(agingColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(agingColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("\(manifest.items.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Text("·")
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                        .font(.footnote)
                    StatusBadge(text: manifest.status.displayLabel, tint: manifest.status.badgeTint)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.currencyString(manifest.totalMSRP))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(agingColor)
                    Text(agingLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(agingColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - Condition Row

private struct ConditionRow: View {
    let condition: ItemCondition
    let count: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(count) / Double(total) : 0 }

    private var conditionColor: Color {
        switch condition {
        case .new:            return EnterpriseTheme.success
        case .refurbished:    return EnterpriseTheme.accent
        case .used:           return EnterpriseTheme.warning
        case .scratchAndDent: return EnterpriseTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(conditionColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: conditionIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(conditionColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(condition.displayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Spacer()
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                    Text(String(format: "%.0f%%", fraction * 100))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                        .frame(width: 34, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(conditionColor.opacity(0.12))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(conditionColor)
                            .frame(width: geo.size.width * fraction, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var conditionIcon: String {
        switch condition {
        case .new:            return "sparkles"
        case .refurbished:    return "arrow.2.circlepath"
        case .used:           return "checkmark.circle"
        case .scratchAndDent: return "exclamationmark.triangle"
        }
    }
}
