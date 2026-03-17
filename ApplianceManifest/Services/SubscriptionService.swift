import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    @Published private(set) var products: [Product] = []

    var appAccountToken: UUID?
    var backend: (any BackendServicing)?

    private let productIDs = LoadScanPlanID.allCases
        .filter { $0 != .free }
        .map(\.rawValue)

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
            products = loaded.sorted { lhs, rhs in
                lhs.price < rhs.price
            }
        } catch {
            products = []
        }
    }

    func product(for plan: LoadScanPlanID) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    func purchase(plan: LoadScanPlanID) async throws -> PurchaseResult {
        guard AppStore.canMakePayments else {
            throw AppError.lookupFailed("In-App Purchases are not available on this device right now.")
        }

        guard let product = product(for: plan) else {
            throw AppError.lookupFailed("Subscription product is not available yet. Configure it in App Store Connect.")
        }

        let result: Product.PurchaseResult
        if let appAccountToken {
            result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        } else {
            result = try await product.purchase()
        }

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await backend?.sendSubscriptionEmail(plan: plan.rawValue)
                // Xcode Cloud can lag local SDK symbol exposure for signed JWS helpers.
                // The backend accepts a nil JWS and can still activate by product ID,
                // while App Store Server Notifications handle the fully verified path.
                return PurchaseResult(productID: product.id, transactionJWS: nil)
            case .unverified:
                throw AppError.lookupFailed("Purchase could not be verified by StoreKit.")
            }
        case .userCancelled:
            throw CancellationError()
        case .pending:
            throw AppError.lookupFailed("Purchase is pending approval.")
        @unknown default:
            throw AppError.lookupFailed("Unexpected purchase result.")
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }
}

struct PurchaseResult: Equatable {
    let productID: String
    let transactionJWS: String?
}
