import Foundation
import SwiftUI

@MainActor
final class NewManifestViewModel: ObservableObject {
    @Published var title = ""
    @Published var loadReference = ""
    @Published var draftItems: [DraftManifestItem] = []
    @Published var selectedDraftID: UUID?
    @Published var isScanning = false
    @Published var errorMessage: String?

    let backend: BackendServicing

    init(backend: BackendServicing) {
        self.backend = backend
    }

    func ingestPhoto(data: Data) async {
        isScanning = true
        defer { isScanning = false }

        do {
            let modelNumber = try await backend.extractModelNumber(from: data)
            let suggestion = try await backend.lookupProduct(modelNumber: modelNumber)
            let draft = DraftManifestItem(
                imageData: data,
                modelNumber: suggestion.normalizedModelNumber,
                productName: suggestion.productName,
                msrpText: NSDecimalNumber(decimal: suggestion.msrp).stringValue,
                quantity: 1,
                lookupStatus: suggestion.status,
                source: suggestion.source,
                confidence: suggestion.confidence
            )
            draftItems.append(draft)
            selectedDraftID = draft.id
        } catch {
            errorMessage = error.localizedDescription
            let fallback = DraftManifestItem(imageData: data, lookupStatus: .needsReview)
            draftItems.append(fallback)
            selectedDraftID = fallback.id
        }
    }

    func updateDraft(_ draft: DraftManifestItem) {
        guard let index = draftItems.firstIndex(where: { $0.id == draft.id }) else { return }
        draftItems[index] = draft
    }

    func removeDraft(id: UUID) {
        draftItems.removeAll { $0.id == id }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !loadReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftItems.isEmpty
            && draftItems.allSatisfy {
                !$0.modelNumber.isEmpty && !$0.productName.isEmpty && Decimal(string: $0.msrpText) != nil
            }
    }
}
