import SwiftUI

struct ManifestListView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isPresentingNewManifest = false

    var body: some View {
        List {
            Section {
                Button {
                    isPresentingNewManifest = true
                } label: {
                    Label("Create New Manifest", systemImage: "plus.rectangle.on.rectangle")
                }
            }

            Section("Previous Manifests") {
                if appViewModel.manifests.isEmpty {
                    Text("No manifests yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appViewModel.manifests) { manifest in
                        NavigationLink(destination: ManifestDetailView(manifestID: manifest.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(manifest.title)
                                    .font(.headline)
                                Text("Load \(manifest.loadReference)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(manifest.items.count) appliances • $\(NSDecimalNumber(decimal: manifest.totalMSRP).stringValue)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await appViewModel.refreshManifests()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Sign Out") {
                    Task { await appViewModel.signOut() }
                }
            }
        }
        .sheet(isPresented: $isPresentingNewManifest) {
            NewManifestView(isPresented: $isPresentingNewManifest, backend: appViewModel.backend)
                .environmentObject(appViewModel)
        }
    }
}
