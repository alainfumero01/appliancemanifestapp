import Foundation

struct UserSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let user: AppUser
    /// Set by the sign-in / sign-up edge functions. A new nonce is written to
    /// the DB on every login; if the stored nonce no longer matches the DB the
    /// session has been displaced by a login on another device.
    let sessionNonce: UUID?
}

struct AppUser: Codable, Equatable {
    let id: UUID
    let email: String
    /// The organization this user belongs to.
    let orgID: UUID?
}

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case wholesale
    case seller

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .wholesale: return "Wholesale"
        case .seller: return "Seller"
        }
    }
}

enum SellerModeAccessState: String, Equatable {
    case unknown
    case loading
    case active
    case inactive
}

enum SellerInventoryRoute: String, Identifiable {
    case inventoryIntake
    case quickLoadBuilder
    case importLoads

    var id: String { rawValue }
}

enum OrganizationSubscriptionType: String, Codable, Equatable, CaseIterable, Identifiable {
    case individual
    case enterprise

    var id: String { rawValue }
}

enum SubscriptionStatus: String, Codable, Equatable, CaseIterable, Identifiable {
    case free
    case active
    case expired
    case pastDue = "past_due"
    case canceled

    var id: String { rawValue }
}

enum BillingPlatform: String, Codable, Equatable, CaseIterable, Identifiable {
    case appStore = "app_store"
    case none

    var id: String { rawValue }
}

enum LoadScanPlanID: String, Codable, Equatable, CaseIterable, Identifiable {
    case free
    case individualMonthly = "com.alainfumero.loadscan.individual.monthly"
    case enterprise5Monthly = "com.alainfumero.loadscan.enterprise5.monthly"
    case enterprise10Monthly = "com.alainfumero.loadscan.enterprise10.monthly"
    case enterprise15Monthly = "com.alainfumero.loadscan.enterprise15.monthly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .individualMonthly: return "LoadScan Individual"
        case .enterprise5Monthly: return "LoadScan Enterprise 5"
        case .enterprise10Monthly: return "LoadScan Enterprise 10"
        case .enterprise15Monthly: return "LoadScan Enterprise 15"
        }
    }

    var monthlyPrice: Decimal {
        switch self {
        case .free: return 0
        case .individualMonthly: return 19.99
        case .enterprise5Monthly: return 39.99
        case .enterprise10Monthly: return 64.99
        case .enterprise15Monthly: return 89.99
        }
    }

    var includedSeats: Int {
        switch self {
        case .free, .individualMonthly: return 1
        case .enterprise5Monthly: return 6
        case .enterprise10Monthly: return 11
        case .enterprise15Monthly: return 16
        }
    }

    var isEnterprise: Bool {
        switch self {
        case .enterprise5Monthly, .enterprise10Monthly, .enterprise15Monthly: return true
        case .free, .individualMonthly: return false
        }
    }

    var marketingDescription: String {
        switch self {
        case .free:
            return "Save up to 3 manifests free before upgrading."
        case .individualMonthly:
            return "Unlimited manifests for a single operator."
        case .enterprise5Monthly:
            return "Unlimited manifests with 5 additional teammates included."
        case .enterprise10Monthly:
            return "Enterprise access for larger crews with 10 additional teammates included."
        case .enterprise15Monthly:
            return "Expanded enterprise access for high-volume teams with 15 additional teammates included."
        }
    }
}

struct OrganizationEntitlement: Codable, Equatable {
    let orgID: UUID
    let organizationName: String
    let ownerID: UUID
    let subscriptionType: OrganizationSubscriptionType
    let billingPlatform: BillingPlatform
    let subscriptionStatus: SubscriptionStatus
    let appStoreProductID: String?
    let subscriptionExpiresAt: Date?
    let seatLimit: Int
    let extraSeats: Int
    let trialManifestLimit: Int
    let trialManifestsUsed: Int
    let memberCount: Int
    let isOwner: Bool

    var remainingFreeManifests: Int {
        max(trialManifestLimit - trialManifestsUsed, 0)
    }

    var canCreateManifest: Bool {
        subscriptionStatus == .active || remainingFreeManifests > 0
    }

    var isEnterprise: Bool {
        subscriptionType == .enterprise
    }

    var currentPlan: LoadScanPlanID {
        guard let appStoreProductID,
              let plan = LoadScanPlanID(rawValue: appStoreProductID) else {
            return .free
        }
        return plan
    }
}

struct OrganizationMember: Codable, Equatable, Identifiable {
    let id: UUID
    let email: String
    let role: String
    let joinedAt: Date?
}

struct EnterpriseInviteLink: Codable, Equatable {
    let code: String
    let inviteURL: String
    let seatLimit: Int
    let currentMemberCount: Int
}

struct InviteCode: Codable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let isActive: Bool
    let usageCount: Int
    let usageLimit: Int?

    var isUsed: Bool { (usageLimit.map { usageCount >= $0 } ?? false) || !isActive }
}

struct Manifest: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var loadReference: String
    let ownerID: UUID
    /// Email of the user who created this manifest. Populated from profiles table.
    var ownerEmail: String?
    /// The organization this manifest belongs to. All org members can view it.
    let orgID: UUID?
    let createdAt: Date
    var updatedAt: Date
    var status: ManifestStatus
    var items: [ManifestItem]
    /// Set only when the operator used Load Pricing mode.
    var loadCost: Decimal?
    var targetMarginPct: Decimal?

    var totalMSRP: Decimal {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    var totalOurPrice: Decimal {
        items.reduce(0) { $0 + $1.ourLineTotal }
    }

    /// Only meaningful when loadCost was entered via Load Pricing mode.
    var profit: Decimal? {
        guard let cost = loadCost else { return nil }
        return totalOurPrice - cost
    }
}

enum ManifestStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case completed
    case sold

    var id: String { rawValue }
}

struct ManifestItem: Identifiable, Codable, Equatable {
    let id: UUID
    let manifestID: UUID
    var modelNumber: String
    var productName: String
    var brand: String?
    var applianceCategory: String?
    var msrp: Decimal
    var ourPrice: Decimal
    var condition: ItemCondition
    var quantity: Int
    var photoPath: String?
    var lookupStatus: LookupStatus
    var createdAt: Date

    var lineTotal: Decimal {
        msrp * Decimal(quantity)
    }

    var ourLineTotal: Decimal {
        ourPrice * Decimal(quantity)
    }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable {
    case new
    case used
    case refurbished
    case scratchAndDent

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .new: return "New"
        case .used: return "Used"
        case .refurbished: return "Refurbished"
        case .scratchAndDent: return "Scratch & Dent"
        }
    }
}

enum LookupStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case cached
    case aiSuggested
    case confirmed
    case needsReview

    var id: String { rawValue }
}

struct CatalogProduct: Codable, Equatable {
    let normalizedModelNumber: String
    var productName: String
    var brand: String?
    var applianceCategory: String?
    var msrp: Decimal
    var source: String
    var confidence: Double
}

struct LookupSuggestion: Codable, Equatable {
    var normalizedModelNumber: String
    var productName: String
    var brand: String?
    var applianceCategory: String?
    var msrp: Decimal
    var source: String
    var confidence: Double
    var status: LookupStatus
}

struct DraftManifestItem: Identifiable, Equatable, Codable {
    let id: UUID
    var imageData: Data
    var previewName: String
    var observedModelNumber: String?
    var modelNumber: String
    var productName: String
    var brand: String?
    var applianceCategory: String?
    var msrpText: String
    var ourPriceText: String
    var condition: ItemCondition
    var quantity: Int
    var lookupStatus: LookupStatus
    var source: String
    var confidence: Double

    init(
        id: UUID = UUID(),
        imageData: Data,
        previewName: String = "Sticker",
        observedModelNumber: String? = nil,
        modelNumber: String = "",
        productName: String = "",
        brand: String? = nil,
        applianceCategory: String? = nil,
        msrpText: String = "",
        ourPriceText: String = "",
        condition: ItemCondition = .used,
        quantity: Int = 1,
        lookupStatus: LookupStatus = .pending,
        source: String = "",
        confidence: Double = 0
    ) {
        self.id = id
        self.imageData = imageData
        self.previewName = previewName
        self.observedModelNumber = observedModelNumber
        self.modelNumber = modelNumber
        self.productName = productName
        self.brand = brand
        self.applianceCategory = applianceCategory
        self.msrpText = msrpText
        self.ourPriceText = ourPriceText
        self.condition = condition
        self.quantity = quantity
        self.lookupStatus = lookupStatus
        self.source = source
        self.confidence = confidence
    }
}

enum InventoryStatus: String, Codable, CaseIterable, Identifiable {
    case inStock = "in_stock"
    case listed
    case reserved
    case sold

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .inStock: return "In Stock"
        case .listed: return "Listed"
        case .reserved: return "Reserved"
        case .sold: return "Sold"
        }
    }

    var isAvailableForQuickLoad: Bool {
        switch self {
        case .inStock, .listed: return true
        case .reserved, .sold: return false
        }
    }
}

struct InventoryUnit: Identifiable, Codable, Equatable {
    let id: UUID
    let orgID: UUID
    var sourceManifestID: UUID?
    var sourceManifestItemID: UUID?
    var sourceManifestItemIndex: Int?
    var modelNumber: String
    var productName: String
    var brand: String?
    var applianceCategory: String?
    var msrp: Decimal
    var askingPrice: Decimal
    var costBasis: Decimal?
    var soldPrice: Decimal?
    var condition: ItemCondition
    var status: InventoryStatus
    var photoPath: String?
    let createdAt: Date
    var updatedAt: Date
    var listedAt: Date?
    var reservedAt: Date?
    var soldAt: Date?

    var isAvailableForQuickLoad: Bool { status.isAvailableForQuickLoad }
    var displayBrand: String { brand?.nilIfBlank ?? productName.brandFallback }
    var displayCategory: String { applianceCategory?.categoryDisplayName ?? "Other" }
    var realizedRevenue: Decimal { soldPrice ?? 0 }
    var realizedProfit: Decimal? {
        guard let soldPrice, let costBasis else { return nil }
        return soldPrice - costBasis
    }
}

struct InventoryGroupRow: Identifiable, Equatable {
    let brand: String
    let applianceCategory: String
    let modelNumber: String
    let productName: String
    let condition: ItemCondition
    let askingPrice: Decimal
    let msrp: Decimal
    let availableUnits: [InventoryUnit]
    let reservedUnits: [InventoryUnit]
    let soldUnits: [InventoryUnit]

    var id: String {
        [
            applianceCategory,
            modelNumber,
            condition.rawValue,
            NSDecimalNumber(decimal: askingPrice).stringValue
        ].joined(separator: "|")
    }

    var availableCount: Int { availableUnits.count }
    var reservedCount: Int { reservedUnits.count }
    var soldCount: Int { soldUnits.count }
    var representativePhotoPath: String? {
        availableUnits.first?.photoPath ?? reservedUnits.first?.photoPath ?? soldUnits.first?.photoPath
    }
}

enum SellerAnalyticsWindow: String, CaseIterable, Identifiable {
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
    case all = "All"

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .all: return nil
        }
    }

    var shortLabel: String {
        switch self {
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .ninetyDays: return "90 Days"
        case .all: return "All Time"
        }
    }

    var displayLabel: String {
        switch self {
        case .sevenDays: return "Past 7 Days"
        case .thirtyDays: return "Past 30 Days"
        case .ninetyDays: return "Past 90 Days"
        case .all: return "All Time"
        }
    }
}

struct SellerAnalytics {
    var inStockCount: Int
    var listedCount: Int
    var reservedCount: Int
    var soldCount: Int
    var activeInventoryValue: Decimal
    var soldRevenue: Decimal
    var soldProfit: Decimal?
    var averageDaysToSell: Double?
    var stale30Count: Int
    var stale60Count: Int
    var stale90Count: Int
    var topBrands: [(String, Int)]
    var topCategories: [(String, Int)]
    var topModels: [(String, Int)]
}

struct SellerTrendPoint: Identifiable, Equatable {
    let date: Date
    let addedUnits: Int
    let soldUnits: Int
    let soldRevenue: Decimal
    let soldProfit: Decimal
    let cumulativeRevenue: Decimal

    var id: Date { date }
    var netUnitFlow: Int { addedUnits - soldUnits }
    var soldRevenueValue: Double { NSDecimalNumber(decimal: soldRevenue).doubleValue }
    var soldProfitValue: Double { NSDecimalNumber(decimal: soldProfit).doubleValue }
    var cumulativeRevenueValue: Double { NSDecimalNumber(decimal: cumulativeRevenue).doubleValue }
    var soldUnitsValue: Double { Double(soldUnits) }
    var netUnitFlowValue: Double { Double(netUnitFlow) }
}

struct SellerTrendSnapshot: Equatable {
    let points: [SellerTrendPoint]
    let hasProfitData: Bool
}

struct InventoryImportSummary: Equatable {
    let selectedLoadCount: Int
    let importedLoadCount: Int
    let alreadyImportedLoadCount: Int
    let importedUnitCount: Int

    var title: String {
        if importedUnitCount > 0 {
            return "Inventory Imported"
        }
        if alreadyImportedLoadCount > 0 {
            return "Inventory Already Up To Date"
        }
        return "No Inventory Imported"
    }

    var message: String {
        if importedUnitCount > 0 {
            var parts = ["Imported \(importedUnitCount) unit\(importedUnitCount == 1 ? "" : "s")"]
            if importedLoadCount > 0 {
                parts.append("from \(importedLoadCount) load\(importedLoadCount == 1 ? "" : "s")")
            }
            if alreadyImportedLoadCount > 0 {
                parts.append("(\(alreadyImportedLoadCount) already up to date)")
            }
            return parts.joined(separator: " ")
        }
        if alreadyImportedLoadCount > 0 {
            return "\(alreadyImportedLoadCount) selected load\(alreadyImportedLoadCount == 1 ? "" : "s") were already imported into Seller Mode."
        }
        return "We didn't find any new units to import from the selected loads."
    }
}

enum SellerToastStyle: Equatable {
    case success
    case info
    case warning
}

struct SellerToast: Identifiable, Equatable {
    let id = UUID()
    let style: SellerToastStyle
    let symbol: String
    let title: String
    let message: String

    static func inventoryImported(_ summary: InventoryImportSummary) -> SellerToast {
        SellerToast(
            style: summary.importedUnitCount > 0 ? .success : .info,
            symbol: summary.importedUnitCount > 0 ? "shippingbox.fill" : "info.circle.fill",
            title: summary.title,
            message: summary.message
        )
    }

    static func quickLoadCreated(unitCount: Int, groupCount: Int) -> SellerToast {
        let unitLabel = "\(unitCount) unit\(unitCount == 1 ? "" : "s")"
        let groupLabel = "\(groupCount) group\(groupCount == 1 ? "" : "s")"
        return SellerToast(
            style: .success,
            symbol: "bolt.fill",
            title: "Quick Load Created",
            message: "Reserved \(unitLabel) from \(groupLabel) into a new load."
        )
    }
}

extension Array where Element == InventoryUnit {
    func groupedInventoryRows() -> [InventoryGroupRow] {
        let grouped = Dictionary(grouping: self) { unit in
            [
                unit.applianceCategory?.categoryDisplayName ?? "Other",
                unit.modelNumber,
                unit.condition.rawValue,
                NSDecimalNumber(decimal: unit.askingPrice).stringValue
            ].joined(separator: "|")
        }

        return grouped.values.map { units in
            let available = units.filter { $0.status == .inStock || $0.status == .listed }
            let reserved = units.filter { $0.status == .reserved }
            let sold = units.filter { $0.status == .sold }
            let sample = available.first ?? reserved.first ?? sold.first!
            return InventoryGroupRow(
                brand: sample.displayBrand,
                applianceCategory: sample.displayCategory,
                modelNumber: sample.modelNumber,
                productName: sample.productName,
                condition: sample.condition,
                askingPrice: sample.askingPrice,
                msrp: sample.msrp,
                availableUnits: available.sorted(by: { $0.createdAt < $1.createdAt }),
                reservedUnits: reserved.sorted(by: { $0.createdAt < $1.createdAt }),
                soldUnits: sold.sorted(by: { $0.createdAt < $1.createdAt })
            )
        }
        .sorted {
            if $0.applianceCategory != $1.applianceCategory {
                return $0.applianceCategory < $1.applianceCategory
            }
            if $0.brand != $1.brand {
                return $0.brand < $1.brand
            }
            return $0.productName < $1.productName
        }
    }

    func sellerAnalytics(window: SellerAnalyticsWindow, now: Date = Date()) -> SellerAnalytics {
        let availableUnits = filter { $0.status == .inStock || $0.status == .listed || $0.status == .reserved }
        let soldUnits: [InventoryUnit]
        if let dayCount = window.dayCount {
            let threshold = Calendar.current.date(byAdding: .day, value: -dayCount, to: now) ?? now
            soldUnits = filter { $0.status == .sold && ($0.soldAt ?? $0.updatedAt) >= threshold }
        } else {
            soldUnits = filter { $0.status == .sold }
        }

        let profitValues = soldUnits.compactMap(\.realizedProfit)
        let datedSoldUnits = soldUnits.compactMap { unit -> Double? in
            guard let soldAt = unit.soldAt else { return nil }
            return soldAt.timeIntervalSince(unit.createdAt) / 86_400
        }

        func topCounts(for values: [String]) -> [(String, Int)] {
            Dictionary(grouping: values, by: { $0 })
                .map { ($0.key, $0.value.count) }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 > $1.1 }
                    return $0.0 < $1.0
                }
                .prefix(5)
                .map { $0 }
        }

        return SellerAnalytics(
            inStockCount: filter { $0.status == .inStock }.count,
            listedCount: filter { $0.status == .listed }.count,
            reservedCount: filter { $0.status == .reserved }.count,
            soldCount: soldUnits.count,
            activeInventoryValue: availableUnits.reduce(0) { $0 + $1.askingPrice },
            soldRevenue: soldUnits.reduce(0) { $0 + ($1.soldPrice ?? 0) },
            soldProfit: profitValues.isEmpty ? nil : profitValues.reduce(0, +),
            averageDaysToSell: datedSoldUnits.isEmpty ? nil : datedSoldUnits.reduce(0, +) / Double(datedSoldUnits.count),
            stale30Count: availableUnits.filter { now.timeIntervalSince($0.createdAt) >= 30 * 86_400 }.count,
            stale60Count: availableUnits.filter { now.timeIntervalSince($0.createdAt) >= 60 * 86_400 }.count,
            stale90Count: availableUnits.filter { now.timeIntervalSince($0.createdAt) >= 90 * 86_400 }.count,
            topBrands: topCounts(for: soldUnits.map(\.displayBrand)),
            topCategories: topCounts(for: soldUnits.map(\.displayCategory)),
            topModels: topCounts(for: soldUnits.map(\.modelNumber))
        )
    }

    func sellerTrendSnapshot(window: SellerAnalyticsWindow, now: Date = Date()) -> SellerTrendSnapshot {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: now)

        let startDate: Date = {
            if let dayCount = window.dayCount,
               let threshold = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDate) {
                return threshold
            }

            let eventDates = compactMap { unit -> Date? in
                if unit.status == .sold {
                    return unit.soldAt ?? unit.updatedAt
                }
                return unit.createdAt
            }
            let earliest = eventDates.min() ?? endDate
            return calendar.startOfDay(for: earliest)
        }()

        guard startDate <= endDate else {
            return SellerTrendSnapshot(points: [], hasProfitData: false)
        }

        var addedUnitsByDay: [Date: Int] = [:]
        var soldUnitsByDay: [Date: Int] = [:]
        var soldRevenueByDay: [Date: Decimal] = [:]
        var soldProfitByDay: [Date: Decimal] = [:]
        var hasProfitData = false

        for unit in self {
            let createdDay = calendar.startOfDay(for: unit.createdAt)
            if createdDay >= startDate && createdDay <= endDate {
                addedUnitsByDay[createdDay, default: 0] += 1
            }

            guard unit.status == .sold else { continue }
            let soldEventDate = calendar.startOfDay(for: unit.soldAt ?? unit.updatedAt)
            guard soldEventDate >= startDate && soldEventDate <= endDate else { continue }

            soldUnitsByDay[soldEventDate, default: 0] += 1
            soldRevenueByDay[soldEventDate, default: 0] += unit.soldPrice ?? 0

            if let realizedProfit = unit.realizedProfit {
                soldProfitByDay[soldEventDate, default: 0] += realizedProfit
                hasProfitData = true
            }
        }

        var points: [SellerTrendPoint] = []
        var cursor = startDate
        var cumulativeRevenue: Decimal = 0

        while cursor <= endDate {
            let dailyRevenue = soldRevenueByDay[cursor, default: 0]
            cumulativeRevenue += dailyRevenue

            points.append(
                SellerTrendPoint(
                    date: cursor,
                    addedUnits: addedUnitsByDay[cursor, default: 0],
                    soldUnits: soldUnitsByDay[cursor, default: 0],
                    soldRevenue: dailyRevenue,
                    soldProfit: soldProfitByDay[cursor, default: 0],
                    cumulativeRevenue: cumulativeRevenue
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return SellerTrendSnapshot(points: points, hasProfitData: hasProfitData)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var brandFallback: String {
        split(separator: " ").first.map(String.init) ?? self
    }

    var categoryDisplayName: String {
        replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

struct NewManifestDraftSnapshot: Codable, Equatable {
    var title: String
    var loadReference: String
    var draftItems: [DraftManifestItem]
    var manualModelNumber: String
    var pricingMode: PricingMode
    var loadCostText: String
    var targetMarginText: String
    var savedAt: Date
}

struct ExportedManifest: Equatable {
    let fileURL: URL
    let filename: String

    var id: String { fileURL.absoluteString }
}

extension ExportedManifest: Identifiable {}

struct EmptyResponse: Decodable {}

enum AppError: LocalizedError, Equatable {
    case missingConfiguration(String)
    case invalidResponse
    case unauthenticated
    case sessionInvalidated
    case ocrFailed
    case notAppliance
    case lookupFailed(String)
    case exportFailed
    case paywallRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing configuration value for \(key)."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unauthenticated:
            return "Please sign in to continue."
        case .sessionInvalidated:
            return "Your session was signed in on another device. Please sign in again."
        case .ocrFailed:
            return "The sticker could not be read. Please retake the photo or enter the model number manually."
        case .notAppliance:
            return "The scanned sticker is not for an appliance."
        case .lookupFailed(let message):
            return UserFacingError.sanitize(message)
        case .exportFailed:
            return "The manifest could not be exported."
        case .paywallRequired(let message):
            return message
        }
    }
}

enum UserFacingError {
    static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.errorDescription ?? fallbackMessage
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return "Check your internet connection and try again."
            case .timedOut:
                return "That took too long. Please try again."
            case .cancelled:
                return "That action was canceled."
            default:
                return "We couldn't complete that right now. Please try again."
            }
        }

        if error is DecodingError {
            return "We hit a temporary issue loading your data. Please try again."
        }

        return sanitize(error.localizedDescription)
    }

    static func sanitize(_ rawMessage: String) -> String {
        let extracted = extractMessage(from: rawMessage)
        let normalized = extracted
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
        guard !normalized.isEmpty else { return fallbackMessage }

        let lowercase = normalized.lowercased()

        if lowercase.contains("invalid login credentials")
            || lowercase.contains("invalid email or password")
            || lowercase.contains("wrong password")
            || lowercase.contains("invalid_credentials") {
            return "That email or password doesn't look right. Please try again."
        }

        if lowercase.contains("already registered")
            || lowercase.contains("already exists")
            || lowercase.contains("user already registered")
            || lowercase.contains("account already exists") {
            return "An account with this email already exists. Try signing in instead."
        }

        if lowercase.contains("password should be at least")
            || lowercase.contains("password is too short")
            || lowercase.contains("weak password") {
            return "Choose a stronger password with at least 6 characters."
        }

        if lowercase.contains("invalid email")
            || lowercase.contains("email address is invalid") {
            return "Enter a valid email address and try again."
        }

        if lowercase.contains("rate limit")
            || lowercase.contains("too many requests")
            || lowercase.contains("security purposes") {
            return "Too many attempts were made. Please wait a moment and try again."
        }

        if lowercase.contains("email not confirmed")
            || lowercase.contains("confirm your email") {
            return "Please confirm your email address before signing in."
        }

        if lowercase.contains("jwt expired")
            || lowercase.contains("token expired")
            || lowercase.contains("session expired")
            || lowercase.contains("unauthorized")
            || lowercase.contains("invalid jwt")
            || lowercase.contains("no auth credentials found") {
            return "Your session expired. Please sign in again."
        }

        if lowercase.contains("invite")
            && (lowercase.contains("invalid")
                || lowercase.contains("expired")
                || lowercase.contains("used")
                || lowercase.contains("not found")) {
            return "That invite code isn't valid anymore. Double-check it and try again."
        }

        if lowercase.contains("already a member")
            || lowercase.contains("already belongs to")
            || lowercase.contains("already in organization") {
            return "This account is already on a team."
        }

        if lowercase.contains("only organization owners can create invite")
            || lowercase.contains("only the owner can create invite") {
            return "Only the team owner can generate invite codes."
        }

        if lowercase.contains("no organization found")
            || lowercase.contains("organization not found") {
            return "We couldn't find your organization yet. Please try again in a moment."
        }

        if lowercase.contains("requested function was not found")
            || lowercase == "not_found"
            || lowercase.contains("\"code\":\"not_found\"") {
            return "This feature is still being set up. Please try again shortly."
        }

        if lowercase.contains("unknown app store product")
            || lowercase.contains("product is not available")
            || lowercase.contains("configure it in app store connect") {
            return "This subscription option isn't available right now. Please try again shortly."
        }

        if lowercase.contains("in-app purchases are not available on this device") {
            return "Subscriptions aren't available on this device right now. Check Screen Time or App Store restrictions and try again."
        }

        if lowercase.contains("transaction product does not match")
            || lowercase.contains("transaction appaccounttoken does not match")
            || lowercase.contains("purchase could not be verified") {
            return "We couldn't verify that purchase. Please try again."
        }

        if lowercase.contains("purchase was canceled") {
            return "Purchase canceled."
        }

        if lowercase.contains("purchase is pending approval") {
            return "Your purchase is pending approval."
        }

        if lowercase.contains("unexpected purchase result") {
            return "We couldn't finish that purchase right now. Please try again."
        }

        if lowercase.contains("manifest insert failed")
            || lowercase.contains("manifest item insert failed")
            || lowercase.contains("photo upload failed") {
            return "We couldn't save everything for this load. Please try again."
        }

        if lowercase.contains("failed to fetch")
            || lowercase.contains("network request failed")
            || lowercase.contains("fetcherror") {
            return "We couldn't reach the server right now. Please try again."
        }

        if normalized.first == "{"
            || normalized.first == "[" {
            return fallbackMessage
        }

        return normalized
    }

    private static var fallbackMessage: String {
        "We couldn't complete that right now. Please try again."
    }

    private static func extractMessage(from rawMessage: String) -> String {
        guard let data = rawMessage.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return rawMessage
        }

        if let dictionary = json as? [String: Any] {
            for key in ["error_description", "error", "message", "msg"] {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }

        if let array = json as? [[String: Any]] {
            for item in array {
                for key in ["error_description", "error", "message", "msg"] {
                    if let value = item[key] as? String, !value.isEmpty {
                        return value
                    }
                }
            }
        }

        return rawMessage
    }
}

extension Error {
    var userMessage: String {
        UserFacingError.message(for: self)
    }

    var isExpectedCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        return false
    }

    var isNotApplianceIssue: Bool {
        if let appError = self as? AppError, appError == .notAppliance {
            return true
        }

        return userMessage == AppError.notAppliance.errorDescription
    }

    var isOrganizationAccessIssue: Bool {
        let message: String
        if let appError = self as? AppError, case let .lookupFailed(raw) = appError {
            message = raw.lowercased()
        } else {
            message = userMessage.lowercased()
        }

        return message.contains("organization access not found")
            || message.contains("no organization found for user")
            || message.contains("organization not found")
    }
}
