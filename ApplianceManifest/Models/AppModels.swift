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
    var msrp: Decimal
    var source: String
    var confidence: Double
}

struct LookupSuggestion: Codable, Equatable {
    var normalizedModelNumber: String
    var productName: String
    var msrp: Decimal
    var source: String
    var confidence: Double
    var status: LookupStatus
}

struct DraftManifestItem: Identifiable, Equatable {
    let id: UUID
    var imageData: Data
    var previewName: String
    var modelNumber: String
    var productName: String
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
        modelNumber: String = "",
        productName: String = "",
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
        self.modelNumber = modelNumber
        self.productName = productName
        self.msrpText = msrpText
        self.ourPriceText = ourPriceText
        self.condition = condition
        self.quantity = quantity
        self.lookupStatus = lookupStatus
        self.source = source
        self.confidence = confidence
    }
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
            return message
        case .exportFailed:
            return "The manifest could not be exported."
        case .paywallRequired(let message):
            return message
        }
    }
}
