import SwiftUI
import UIKit

struct NewManifestView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Binding var isPresented: Bool
    @StateObject private var viewModel: NewManifestViewModel
    @State private var isShowingCamera = false

    init(isPresented: Binding<Bool>, backend: BackendServicing) {
        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue: NewManifestViewModel(backend: backend))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Manifest") {
                    TextField("Manifest title", text: $viewModel.title)
                    TextField("Load reference", text: $viewModel.loadReference)
                }

                Section("Scanned Appliances") {
                    if viewModel.draftItems.isEmpty {
                        Text("No stickers scanned yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.draftItems) { draft in
                            Button {
                                viewModel.selectedDraftID = draft.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.productName.isEmpty ? "Needs review" : draft.productName)
                                        .font(.headline)
                                    Text(draft.modelNumber.isEmpty ? "Model pending" : draft.modelNumber)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { viewModel.draftItems[$0].id }.forEach(viewModel.removeDraft)
                        }
                    }

                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Scan Sticker", systemImage: "camera.viewfinder")
                    }
                }
            }
            .navigationTitle("New Manifest")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            let didSave = await appViewModel.addManifest(
                                title: viewModel.title,
                                loadReference: viewModel.loadReference,
                                items: viewModel.draftItems
                            )
                            if didSave {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        Task { await viewModel.ingestPhoto(data: data) }
                    }
                }
            }
            .sheet(item: selectedDraftBinding) { draft in
                DraftReviewView(draft: draft) { updated in
                    viewModel.updateDraft(updated)
                }
            }
            .overlay {
                if viewModel.isScanning {
                    ProgressView("Reading sticker and checking MSRP...")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var selectedDraftBinding: Binding<DraftManifestItem?> {
        Binding<DraftManifestItem?>(
            get: {
                guard let id = viewModel.selectedDraftID else { return nil }
                return viewModel.draftItems.first(where: { $0.id == id })
            },
            set: { newValue in
                if let newValue {
                    viewModel.updateDraft(newValue)
                }
                viewModel.selectedDraftID = nil
            }
        )
    }
}

private struct DraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: DraftManifestItem
    let onSave: (DraftManifestItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Detected") {
                    TextField("Model Number", text: $draft.modelNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Product Name", text: $draft.productName)
                    TextField("MSRP", text: $draft.msrpText)
                        .keyboardType(.decimalPad)
                    Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...50)
                }

                Section("Lookup") {
                    Text("Status: \(draft.lookupStatus.rawValue)")
                    if !draft.source.isEmpty {
                        Text("Source: \(draft.source)")
                    }
                    if draft.confidence > 0 {
                        Text("Confidence: \(Int(draft.confidence * 100))%")
                    }
                }
            }
            .navigationTitle("Review Item")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        draft.modelNumber = ModelNumberNormalizer.normalize(draft.modelNumber)
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }
    }
}
