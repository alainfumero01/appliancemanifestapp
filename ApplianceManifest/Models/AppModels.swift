import Foundation

struct UserSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let user: AppUser
}

struct AppUser: Codable, Equatable {
    let id: UUID
    let email: String
}

struct Manifest: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var loadReference: String
    let ownerID: UUID
    let createdAt: Date
    var updatedAt: Date
    var status: ManifestStatus
    var items: [ManifestItem]

    var totalMSRP: Decimal {
        items.reduce(0) { $0 + $1.lineTotal }
    }
}

enum ManifestStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case completed

    var id: String { rawValue }
}

struct ManifestItem: Identifiable, Codable, Equatable {
    let id: UUID
    let manifestID: UUID
    var modelNumber: String
    var productName: String
    var msrp: Decimal
    var quantity: Int
    var photoPath: String?
    var lookupStatus: LookupStatus
    var createdAt: Date

    var lineTotal: Decimal {
        msrp * Decimal(quantity)
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
    case ocrFailed
    case lookupFailed(String)
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing configuration value for \(key)."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unauthenticated:
            return "Please sign in to continue."
        case .ocrFailed:
            return "The sticker could not be read. Please retake the photo or enter the model number manually."
        case .lookupFailed(let message):
            return message
        case .exportFailed:
            return "The manifest could not be exported."
        }
    }
}
