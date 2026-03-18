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
    private var upgradeFloor: (rank: Int, expiresAt: Date)?

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

        let previousPlanRank = await canonicalActiveTransaction()
            .map(planRank(for:))
            ?? 0

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
                let selectedPlanRank = plan.includedSeats
                if selectedPlanRank > previousPlanRank {
                    armUpgradeFloor(for: selectedPlanRank)
                }

                let synced = await handleVerifiedTransaction(transaction, sendEmail: true, finish: true)
                if selectedPlanRank > previousPlanRank {
                    return PurchaseResult(productID: plan.rawValue, transactionJWS: synced.transactionJWS)
                }
                return synced
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

        if let transaction = await canonicalActiveTransaction() {
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
        let syncTransaction = await canonicalActiveTransaction(preferred: transaction) ?? transaction
        let result = PurchaseResult(productID: syncTransaction.productID, transactionJWS: nil)

        // If Apple surfaces more than one active entitlement, always sync the
        // highest-value LoadScan plan instead of stacking lower plans beside it.
        let didInsert = processedTransactionIDs.insert(syncTransaction.id).inserted
        if shouldIgnore(syncTransaction) || (!allowRepeatSync && !didInsert) {
            if finish {
                await transaction.finish()
            }
            return result
        }

        if sendEmail {
            await backend?.sendSubscriptionEmail(plan: syncTransaction.productID)
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

    private func canonicalActiveTransaction(preferred: Transaction? = nil) async -> Transaction? {
        var transactions = await currentActiveTransactions()

        if let preferred, shouldRestore(preferred), !transactions.contains(where: { $0.id == preferred.id }) {
            transactions.append(preferred)
        }

        return transactions.max(by: isLowerPriority(_:_:))
    }

    private func shouldIgnore(_ transaction: Transaction) -> Bool {
        if transaction.isUpgraded || transaction.revocationDate != nil {
            return true
        }

        if let expirationDate = transaction.expirationDate, expirationDate < Date() {
            return true
        }

        if let floorRank = activeUpgradeFloorRank(), planRank(for: transaction) < floorRank {
            return true
        }

        return false
    }

    private func shouldRestore(_ transaction: Transaction) -> Bool {
        guard !shouldIgnore(transaction) else { return false }

        guard let appAccountToken else { return true }
        return transaction.appAccountToken == nil || transaction.appAccountToken == appAccountToken
    }

    private func isLowerPriority(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        let lhsRank = planRank(for: lhs)
        let rhsRank = planRank(for: rhs)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        if lhs.purchaseDate != rhs.purchaseDate {
            return lhs.purchaseDate < rhs.purchaseDate
        }

        return lhs.id < rhs.id
    }

    private func planRank(for transaction: Transaction) -> Int {
        guard let plan = LoadScanPlanID(rawValue: transaction.productID) else { return 0 }
        return plan.includedSeats
    }

    private func armUpgradeFloor(for rank: Int) {
        upgradeFloor = (rank: rank, expiresAt: Date().addingTimeInterval(45))
    }

    private func activeUpgradeFloorRank() -> Int? {
        guard let upgradeFloor else { return nil }
        guard upgradeFloor.expiresAt > Date() else {
            self.upgradeFloor = nil
            return nil
        }
        return upgradeFloor.rank
    }
}

struct PurchaseResult: Equatable {
    let productID: String
    let transactionJWS: String?
}
