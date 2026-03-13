import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if appViewModel.session == nil {
                    AuthView()
                } else {
                    ManifestListView()
                }
            }
            .navigationTitle(appViewModel.session == nil ? "Appliance Manifest" : "Manifests")
        }
        .overlay(alignment: .top) {
            if let errorMessage = appViewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    appViewModel.errorMessage = nil
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
