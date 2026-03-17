import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    @Published private(set) var products: [Product] = []

    var appAccountToken: UUID?
    var backend: (any BackendServicing)?
    var onTransaction: ((PurchaseResult) async -> Void)?

    private var updatesTask: Task<Void, Never>?

    private let productIDs = LoadScanPlanID.allCases
        .filter { $0 != .free }
        .map(\.rawValue)

    deinit {
        updatesTask?.cancel()
    }

    func startListeningForTransactions() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { break }
                await self?.handleTransactionUpdate(verification)
            }
        }
    }

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
                return await handleVerifiedTransaction(transaction, sendEmail: true, finish: true)
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

    private func handleTransactionUpdate(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        _ = await handleVerifiedTransaction(transaction, sendEmail: true, finish: true)
    }

    private func handleVerifiedTransaction(
        _ transaction: Transaction,
        sendEmail: Bool,
        finish: Bool
    ) async -> PurchaseResult {
        let result = PurchaseResult(productID: transaction.productID, transactionJWS: nil)

        if sendEmail {
            await backend?.sendSubscriptionEmail(plan: transaction.productID)
        }
        await onTransaction?(result)

        if finish {
            await transaction.finish()
        }

        return result
    }
}

struct PurchaseResult: Equatable {
    let productID: String
    let transactionJWS: String?
}
