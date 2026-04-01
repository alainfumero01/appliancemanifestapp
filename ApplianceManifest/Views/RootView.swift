import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @AppStorage("loadscan.hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if appViewModel.session == nil {
                NavigationStack {
                    AuthView()
                        .navigationBarTitleDisplayMode(.inline)
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
            } else {
                mainTabView
                    .fullScreenCover(isPresented: .constant(!hasSeenOnboarding)) {
                        OnboardingView()
                    }
            }
        }
        .preferredColorScheme(.light)
        .overlay(alignment: .top) {
            if let msg = appViewModel.errorMessage {
                ErrorBanner(message: msg) { appViewModel.errorMessage = nil }
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $appViewModel.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            .tag(0)

            NavigationStack {
                ManifestListView()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tabItem {
                Label(
                    appViewModel.appMode == .seller ? "Inventory" : "Loads",
                    systemImage: appViewModel.appMode == .seller ? "shippingbox.fill" : "doc.text.magnifyingglass"
                )
            }
            .tag(1)

            NavigationStack {
                MembershipView()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tabItem { Label("Membership", systemImage: "creditcard") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .tint(EnterpriseTheme.accent)
        .task(id: "\(appViewModel.appMode.rawValue)-\(appViewModel.selectedTab)") {
            guard appViewModel.appMode == .seller,
                  appViewModel.selectedTab == 0 || appViewModel.selectedTab == 1 else { return }
            await appViewModel.prepareSellerMode(forceRefresh: appViewModel.entitlement == nil)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(EnterpriseTheme.danger.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, EnterpriseTheme.pagePadding)
        .padding(.top, 8)
    }
}
