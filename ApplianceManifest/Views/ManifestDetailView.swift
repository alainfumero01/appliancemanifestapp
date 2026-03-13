import SwiftUI

struct ManifestDetailView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    let manifestID: UUID
    @State private var exportedManifest: ExportedManifest?

    private var manifest: Binding<Manifest>? {
        guard let index = appViewModel.manifests.firstIndex(where: { $0.id == manifestID }) else { return nil }
        return $appViewModel.manifests[index]
    }

    var body: some View {
        Group {
            if let manifest {
                Form {
                    Section("Manifest Info") {
                        TextField("Title", text: manifest.title)
                        TextField("Load Reference", text: manifest.loadReference)
                        Picker("Status", selection: manifest.status) {
                            ForEach(ManifestStatus.allCases) { status in
                                Text(status.rawValue.capitalized).tag(status)
                            }
                        }
                    }

                    Section("Items") {
                        ForEach(manifest.wrappedValue.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.productName)
                                    .font(.headline)
                                Text(item.modelNumber)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Qty \(item.quantity) • $\(NSDecimalNumber(decimal: item.lineTotal).stringValue)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let currentItems = manifest.wrappedValue.items
                            let deletions = offsets.map { currentItems[$0] }
                            var updatedManifest = manifest.wrappedValue
                            updatedManifest.items.remove(atOffsets: offsets)
                            manifest.wrappedValue = updatedManifest
                            Task {
                                await appViewModel.deleteItems(deletions, from: manifest.wrappedValue)
                            }
                        }
                    }

                    Section("Summary") {
                        Text("Appliances: \(manifest.wrappedValue.items.count)")
                        Text("Total MSRP: $\(NSDecimalNumber(decimal: manifest.wrappedValue.totalMSRP).stringValue)")
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Save") {
                            Task {
                                await appViewModel.saveManifest(manifest.wrappedValue)
                            }
                        }
                        Button("Export") {
                            Task {
                                exportedManifest = try? await appViewModel.backend.exportManifest(manifest.wrappedValue)
                            }
                        }
                    }
                }
                .sheet(item: $exportedManifest) { export in
                    ShareSheet(activityItems: [export.fileURL])
                }
            } else {
                ContentUnavailableView("Manifest not found", systemImage: "tray")
            }
        }
        .navigationTitle("Manifest Detail")
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
