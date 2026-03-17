import Foundation
import SwiftUI

enum PricingMode: String, CaseIterable {
    case perItem = "Per Item"
    case loadBased = "Load Pricing"
}

@MainActor
final class NewManifestViewModel: ObservableObject {
    @Published var title = ""
    @Published var loadReference = ""
    @Published var draftItems: [DraftManifestItem] = []
    @Published var selectedDraftID: UUID?
    @Published var isScanning = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var notApplianceDetected = false

    // Manual model entry
    @Published var manualModelNumber = ""

    // Pricing strategy
    @Published var pricingMode: PricingMode = .perItem
    @Published var loadCostText = ""
    @Published var targetMarginText = ""

    let backend: BackendServicing

    init(backend: BackendServicing) {
        self.backend = backend
    }

    func ingestPhoto(data: Data) async {
        isScanning = true
        defer { isScanning = false }

        do {
            let suggestion: LookupSuggestion

            if let ocrFirst = try? await ingestViaOCRFirst(data: data) {
                suggestion = ocrFirst
            } else {
                suggestion = try await backend.ingestSticker(imageData: data)
            }

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
        } catch AppError.notAppliance {
            try? await Task.sleep(nanoseconds: 600_000_000)
            notApplianceDetected = true
        } catch {
            let msg = error.localizedDescription
            print("❌ ingestPhoto error: \(error)")
            let fallback = DraftManifestItem(imageData: data, lookupStatus: .needsReview)
            draftItems.append(fallback)
            selectedDraftID = fallback.id
            // Wait for the camera sheet to finish dismissing before showing the alert
            try? await Task.sleep(nanoseconds: 800_000_000)
            errorMessage = msg
        }
    }

    private func ingestViaOCRFirst(data: Data) async throws -> LookupSuggestion {
        let extractedModel = try await backend.extractModelNumber(from: data)
        let normalizedModel = ModelNumberNormalizer.normalize(extractedModel)
        guard !normalizedModel.isEmpty else {
            throw AppError.ocrFailed
        }

        return try await backend.lookupProduct(modelNumber: normalizedModel)
    }

    func updateDraft(_ draft: DraftManifestItem) {
        guard let index = draftItems.firstIndex(where: { $0.id == draft.id }) else { return }
        draftItems[index] = draft
    }

    func saveReviewedDraft(_ draft: DraftManifestItem) async {
        updateDraft(draft)

        guard let suggestion = catalogSuggestion(from: draft) else { return }
        do {
            try await backend.confirmProduct(suggestion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeDraft(id: UUID) {
        draftItems.removeAll { $0.id == id }
    }

    func lookupManualModelNumber() async {
        let trimmed = manualModelNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }

        let normalized = ModelNumberNormalizer.normalize(trimmed)
        guard !normalized.isEmpty else {
            errorMessage = "Please enter a valid model number."
            return
        }

        do {
            let suggestion = try await backend.lookupProduct(modelNumber: normalized)
            let msrp = NSDecimalNumber(decimal: suggestion.msrp)
            let msrpString = msrp == .notANumber ? "" : msrp.stringValue
            let draft = DraftManifestItem(
                imageData: Data(),  // no photo for manual entries
                modelNumber: suggestion.normalizedModelNumber,
                productName: suggestion.productName,
                msrpText: msrpString,
                quantity: 1,
                lookupStatus: suggestion.status,
                source: suggestion.source,
                confidence: suggestion.confidence
            )
            draftItems.append(draft)
            selectedDraftID = draft.id
            manualModelNumber = ""
        } catch {
            try? await Task.sleep(nanoseconds: 500_000_000)
            errorMessage = error.localizedDescription
        }
    }

    var resolvedLoadReference: String {
        let trimmed = loadReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallbackSuffix = String(Int(Date().timeIntervalSince1970))
        return "LOAD-\(fallbackSuffix)"
    }

    var canSave: Bool {
        let itemsReady = !draftItems.isEmpty && draftItems.allSatisfy {
            !$0.modelNumber.isEmpty
                && !$0.productName.isEmpty
                && Decimal(string: $0.msrpText) != nil
                && $0.quantity > 0
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && itemsReady else {
            return false
        }
        if pricingMode == .loadBased {
            guard let cost = Decimal(string: loadCostText), cost > 0,
                  let margin = Decimal(string: targetMarginText), margin > 0, margin < 100 else {
                return false
            }
        }
        return true
    }

    // Projected total revenue based on load cost + margin
    var projectedRevenue: Decimal? {
        guard let cost = Decimal(string: loadCostText), cost > 0,
              let margin = Decimal(string: targetMarginText), margin > 0, margin < 100 else {
            return nil
        }
        return cost / (1 - margin / 100)
    }

    // Applies the load-based pricing algorithm to all draft items.
    // Prices are allocated proportionally to MSRP, weighted by condition,
    // then scaled so total revenue hits the target margin on the load cost.
    func applyLoadBasedPricing() {
        guard let loadCost = Decimal(string: loadCostText), loadCost > 0,
              let margin = Decimal(string: targetMarginText), margin > 0, margin < 100 else {
            return
        }

        let targetRevenue = loadCost / (1 - margin / 100)

        // Condition multipliers: better condition items are priced proportionally higher
        let conditionMultiplier: (ItemCondition) -> Decimal = {
            switch $0 {
            case .new:            return 1.00
            case .refurbished:    return 0.82
            case .used:           return 0.65
            case .scratchAndDent: return 0.48
            }
        }

        // Weight = MSRP × conditionMultiplier × quantity
        let weights: [(id: UUID, weight: Decimal)] = draftItems.map { draft in
            let msrp = Decimal(string: draft.msrpText) ?? 0
            let w = msrp * conditionMultiplier(draft.condition) * Decimal(draft.quantity)
            return (draft.id, w)
        }
        let totalWeight = weights.reduce(Decimal(0)) { $0 + $1.weight }
        guard totalWeight > 0 else { return }

        for i in draftItems.indices {
            let draft = draftItems[i]
            guard let entry = weights.first(where: { $0.id == draft.id }) else { continue }

            // Proportional share of total revenue for this item's total units
            let itemRevenue = (entry.weight / totalWeight) * targetRevenue
            // Per-unit price
            var pricePerUnit = itemRevenue / Decimal(draft.quantity)
            // Cap at MSRP so we never price above market
            let msrp = Decimal(string: draft.msrpText) ?? pricePerUnit
            pricePerUnit = min(pricePerUnit, msrp)
            // Round to 2 decimal places
            var rounded = Decimal()
            var input = pricePerUnit
            NSDecimalRound(&rounded, &input, 2, .plain)

            draftItems[i].ourPriceText = NSDecimalNumber(decimal: rounded).stringValue
        }
    }

    private func catalogSuggestion(from draft: DraftManifestItem) -> LookupSuggestion? {
        let normalized = ModelNumberNormalizer.normalize(draft.modelNumber)
        guard !normalized.isEmpty,
              !draft.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let msrp = Decimal(string: draft.msrpText),
              msrp >= 0 else {
            return nil
        }

        return LookupSuggestion(
            normalizedModelNumber: normalized,
            productName: draft.productName.trimmingCharacters(in: .whitespacesAndNewlines),
            msrp: msrp,
            source: draft.source.isEmpty ? "operator-confirmed" : draft.source,
            confidence: draft.confidence,
            status: .confirmed
        )
    }
}
