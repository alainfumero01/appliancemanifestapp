import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    @Published private(set) var products: [Product] = []

    var appAccountToken: UUID?
    var backend: (any BackendServicing)?
    var onTransaction: ((PurchaseResult) async -> Void)?

    private var updatesTask: Task<Void, Never>?
    private var processedTransactionIDs = Set<UInt64>()

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

        let restoredTransactions = await currentActiveTransactions()
        for transaction in restoredTransactions {
            _ = await handleVerifiedTransaction(
                transaction,
                sendEmail: false,
                finish: false,
                allowRepeatSync: true
            )
        }
    }

    private func handleTransactionUpdate(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        _ = await handleVerifiedTransaction(transaction, sendEmail: false, finish: true)
    }

    private func handleVerifiedTransaction(
        _ transaction: Transaction,
        sendEmail: Bool,
        finish: Bool,
        allowRepeatSync: Bool = false
    ) async -> PurchaseResult {
        let result = PurchaseResult(productID: transaction.productID, transactionJWS: nil)

        // Upgrades can emit multiple transaction updates. Ignore stale or already-
        // handled transactions so an older plan doesn't overwrite the new one.
        let didInsert = processedTransactionIDs.insert(transaction.id).inserted
        if shouldIgnore(transaction) || (!allowRepeatSync && !didInsert) {
            if finish {
                await transaction.finish()
            }
            return result
        }

        if sendEmail {
            await backend?.sendSubscriptionEmail(plan: transaction.productID)
        }
        await onTransaction?(result)

        if finish {
            await transaction.finish()
        }

        return result
    }

    private func currentActiveTransactions() async -> [Transaction] {
        var transactions: [Transaction] = []

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            guard shouldRestore(transaction) else { continue }
            transactions.append(transaction)
        }

        return transactions.sorted { lhs, rhs in
            lhs.purchaseDate > rhs.purchaseDate
        }
    }

    private func shouldIgnore(_ transaction: Transaction) -> Bool {
        if transaction.isUpgraded || transaction.revocationDate != nil {
            return true
        }

        if let expirationDate = transaction.expirationDate, expirationDate < Date() {
            return true
        }

        return false
    }

    private func shouldRestore(_ transaction: Transaction) -> Bool {
        guard !shouldIgnore(transaction) else { return false }

        guard let appAccountToken else { return true }
        return transaction.appAccountToken == nil || transaction.appAccountToken == appAccountToken
    }
}

struct PurchaseResult: Equatable {
    let productID: String
    let transactionJWS: String?
}
