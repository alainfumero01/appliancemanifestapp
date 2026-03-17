import SwiftUI

@main
struct ApplianceManifestApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var subscriptionService = SubscriptionService()

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(viewModel)
                .environmentObject(subscriptionService)
                .task {
                    subscriptionService.backend = viewModel.backend
                    subscriptionService.onTransaction = { result in
                        await viewModel.syncSubscription(
                            productID: result.productID,
                            transactionJWS: result.transactionJWS
                        )
                    }
                    subscriptionService.startListeningForTransactions()
                    refreshSubscriptionContext()
                }
                .onChange(of: viewModel.session?.user.orgID) {
                    refreshSubscriptionContext()
                }
                .onChange(of: viewModel.entitlement?.orgID) {
                    refreshSubscriptionContext()
                }
        }
    }

    private func refreshSubscriptionContext() {
        subscriptionService.appAccountToken = viewModel.entitlement?.orgID ?? viewModel.session?.user.orgID
    }
}
