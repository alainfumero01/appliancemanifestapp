import SwiftUI

@main
struct ApplianceManifestApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(viewModel)
        }
    }
}
