import SwiftUI
import UIKit

struct NewManifestView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Binding var isPresented: Bool
    @StateObject private var viewModel: NewManifestViewModel
    @State private var isShowingCamera = false
    @State private var selectedSourceType: UIImagePickerController.SourceType = .camera
    @State private var isChoosingPhotoSource = false
    @State private var showNotApplianceToast = false
    @State private var pendingPhotoLookup: PendingPhotoLookup?
    @State private var hasRestoredLocalDraft = false
    @State private var didExplicitlySaveManifest = false
    @FocusState private var focusedField: Field?
    private let existingManifest: Manifest?
    private let draftStore = NewManifestDraftStore()

    private enum Field {
        case title, loadReference, loadCost, margin, manualModel
    }

    init(isPresented: Binding<Bool>, backend: BackendServicing, existingManifest: Manifest? = nil) {
        _isPresented = isPresented
        let viewModel = NewManifestViewModel(backend: backend)
        if let existingManifest {
            viewModel.title = existingManifest.title
            viewModel.loadReference = existingManifest.loadReference
        }
        _viewModel = StateObject(wrappedValue: viewModel)
        self.existingManifest = existingManifest
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if existingManifest == nil { infoCard }
                    scanCard
                    if existingManifest == nil { pricingCard }
                    queueSection
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 140)
            }
            .navigationTitle(existingManifest == nil ? "New Load" : "Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    if focusedField != nil {
                        Button("Dismiss Keyboard") { focusedField = nil }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())
                    }
                    Button(existingManifest == nil ? "Save Manifest" : "Add to Draft") {
                        focusedField = nil
                        Task {
                            viewModel.isSaving = true
                            defer { viewModel.isSaving = false }
                            let didSave: Bool
                            if let existingManifest {
                                didSave = await appViewModel.appendDraftItems(
                                    viewModel.draftItems,
                                    to: existingManifest
                                )
                            } else {
                                var loadCost: Decimal? = nil
                                var targetMarginPct: Decimal? = nil
                                if viewModel.pricingMode == .loadBased {
                                    viewModel.applyLoadBasedPricing()
                                    loadCost = Decimal(string: viewModel.loadCostText)
                                    targetMarginPct = Decimal(string: viewModel.targetMarginText)
                                }
                                didSave = await appViewModel.addManifest(
                                    title: viewModel.title,
                                    loadReference: viewModel.resolvedLoadReference,
                                    items: viewModel.draftItems,
                                    loadCost: loadCost,
                                    targetMarginPct: targetMarginPct
                                )
                            }
                            if didSave {
                                didExplicitlySaveManifest = true
                                clearLocalDraft()
                                pendingPhotoLookup = nil
                                if existingManifest == nil {
                                    viewModel.resetNewManifestComposer()
                                }
                                isPresented = false
                            }
                        }
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(!viewModel.canSave || viewModel.isSaving || appViewModel.isLoading)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.textSecondary)
                            .padding(7)
                            .background(EnterpriseTheme.surfacePrimary)
                            .clipShape(Circle())
                            .overlay { Circle().stroke(EnterpriseTheme.border, lineWidth: 1) }
                    }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker(sourceType: selectedSourceType) { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        Task { await prepareScannedPhoto(data) }
                    }
                }
            }
            .sheet(item: $pendingPhotoLookup) { pending in
                DetectedModelReviewView(pending: pending) { reviewed in
                    await confirmScannedPhoto(reviewed)
                }
            }
            .confirmationDialog(
                "Choose Photo Source",
                isPresented: $isChoosingPhotoSource,
                titleVisibility: .visible
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        selectedSourceType = .camera
                        isShowingCamera = true
                    }
                }
                Button("Choose From Camera Roll") {
                    selectedSourceType = .photoLibrary
                    isShowingCamera = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Pick how you want to add the appliance sticker image.")
            }
            .sheet(item: selectedDraftBinding) { draft in
                DraftReviewView(draft: draft) { updated in
                    await viewModel.saveReviewedDraft(updated)
                }
            }
            .overlay {
                if viewModel.isScanning || viewModel.isSaving {
                    ScanningOverlay(message: viewModel.isSaving
                        ? "Saving manifest…"
                        : "Reading sticker and checking MSRP…")
                }
            }
            .alert("Scan Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.notApplianceDetected) { _, detected in
                guard detected else { return }
                viewModel.notApplianceDetected = false
                showNotApplianceToast = true
                focusedField = .manualModel
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showNotApplianceToast = false
                }
            }
            .overlay(alignment: .top) {
                if showNotApplianceToast {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Not an appliance — type the model number below")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EnterpriseTheme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(EnterpriseTheme.border, lineWidth: 1)
                    }
                    .shadow(color: EnterpriseTheme.shadow, radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showNotApplianceToast)
                }
            }
            .task {
                restoreLocalDraftIfNeeded()
            }
            .onChange(of: isPresented) { _, presented in
                guard !presented, !didExplicitlySaveManifest else { return }
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.title) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.loadReference) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.draftItems) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.manualModelNumber) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.pricingMode) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.loadCostText) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .onChange(of: viewModel.targetMarginText) { _, _ in
                persistLocalDraftIfNeeded()
            }
            .enterpriseScreen()
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        EnterpriseCard {
            EnterpriseSectionHeader(
                eyebrow: "New Load",
                title: "New load manifest",
                subtitle: "Name the load, scan sticker photos, and review every item before saving."
            )

            EnterpriseField(
                title: "Manifest Title",
                prompt: "Friday truck load",
                text: $viewModel.title
            )
            .focused($focusedField, equals: .title)
            .onSubmit { focusedField = .loadReference }

            EnterpriseField(
                title: "Load Reference (Optional)",
                prompt: "LOAD-001",
                text: $viewModel.loadReference,
                capitalization: .never
            )
            .focused($focusedField, equals: .loadReference)
        }
    }

    // MARK: - Scan Card

    private var scanCard: some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.accent) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(EnterpriseTheme.accentDim)
                        .frame(width: 48, height: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(EnterpriseTheme.accent.opacity(0.3), lineWidth: 1)
                        }
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22))
                        .foregroundStyle(EnterpriseTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(existingManifest == nil ? "Add Items" : "Add More Items")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text(existingManifest == nil
                        ? "Photograph a sticker or type a model number to look it up."
                        : "Scan more stickers or type model numbers to add them to this draft load.")
                        .font(.caption)
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                }

                Spacer()
            }

            // Photo scan
            Button {
                focusedField = nil
                isChoosingPhotoSource = true
            } label: {
                Label("Scan Sticker", systemImage: "camera.fill")
            }
            .buttonStyle(EnterprisePrimaryButtonStyle())

            // Divider
            HStack(spacing: 10) {
                Rectangle()
                    .fill(EnterpriseTheme.border)
                    .frame(height: 1)
                Text("or")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textTertiary)
                Rectangle()
                    .fill(EnterpriseTheme.border)
                    .frame(height: 1)
            }

            // Manual model number entry
            HStack(spacing: 8) {
                TextField("Type model number…", text: $viewModel.manualModelNumber)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.search)
                    .focused($focusedField, equals: .manualModel)
                    .onSubmit {
                        Task { await viewModel.lookupManualModelNumber() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(EnterpriseTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                            .stroke(focusedField == .manualModel
                                    ? EnterpriseTheme.accent.opacity(0.5)
                                    : EnterpriseTheme.border,
                                    lineWidth: 1)
                    }

                Button {
                    focusedField = nil
                    Task { await viewModel.lookupManualModelNumber() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(viewModel.manualModelNumber.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? EnterpriseTheme.accent.opacity(0.35)
                                    : EnterpriseTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
                }
                .disabled(viewModel.manualModelNumber.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Pricing Card

    private var pricingCard: some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.warning) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(EnterpriseTheme.warning.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(EnterpriseTheme.warning)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pricing Strategy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                    Text(viewModel.pricingMode == .perItem
                         ? "Set price per item during review."
                         : "Enter load cost and margin — prices auto-calculated on save.")
                        .font(.caption)
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            // Mode toggle
            Picker("Pricing Mode", selection: $viewModel.pricingMode) {
                ForEach(PricingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(EnterpriseTheme.warning)
            .onChange(of: viewModel.pricingMode) { _, _ in
                viewModel.applyLoadBasedPricing()
            }

            // Load-based fields
            if viewModel.pricingMode == .loadBased {
                VStack(spacing: 0) {
                    EnterpriseField(
                        title: "Total Load Cost ($)",
                        prompt: "0.00",
                        text: $viewModel.loadCostText,
                        keyboardType: .decimalPad,
                        capitalization: .never
                    )
                    .focused($focusedField, equals: .loadCost)
                    .onSubmit { focusedField = .margin }
                    .onChange(of: viewModel.loadCostText) { _, _ in
                        viewModel.applyLoadBasedPricing()
                    }

                    EnterpriseField(
                        title: "Target Profit Margin (%)",
                        prompt: "30",
                        text: $viewModel.targetMarginText,
                        keyboardType: .decimalPad,
                        capitalization: .never
                    )
                    .focused($focusedField, equals: .margin)
                    .onChange(of: viewModel.targetMarginText) { _, _ in
                        viewModel.applyLoadBasedPricing()
                    }
                }

                // Live projection
                if let revenue = viewModel.projectedRevenue,
                   let cost = Decimal(string: viewModel.loadCostText), cost > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PROJECTED REVENUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                                .tracking(1.2)
                            Text(Formatters.currencyString(revenue))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.success)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("PROFIT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                                .tracking(1.2)
                            Text(Formatters.currencyString(revenue - cost))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.warning)
                        }
                    }
                    .padding(12)
                    .background(EnterpriseTheme.success.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(EnterpriseTheme.success.opacity(0.18), lineWidth: 1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(EnterpriseTheme.accent)
                        Text("Prices are distributed proportionally by MSRP and condition, capped at retail.")
                            .font(.system(size: 11))
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Queue Section

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(EnterpriseTheme.textTertiary)
                        .frame(width: 12, height: 2)
                    Text("SCAN QUEUE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.6)
                }
                Spacer()
                if !viewModel.draftItems.isEmpty {
                    Text("\(viewModel.draftItems.count) items")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }

            if viewModel.draftItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.badge.clock")
                        .font(.system(size: 28))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Text("No stickers scanned yet.")
                        .font(.subheadline)
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(EnterpriseTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous)
                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                }
            } else {
                ForEach(viewModel.draftItems) { draft in
                    EnterpriseCard(accentLeft: draft.lookupStatus.badgeTint) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(draft.productName.isEmpty ? "Needs review" : draft.productName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(draft.productName.isEmpty
                                        ? EnterpriseTheme.textTertiary
                                        : EnterpriseTheme.textPrimary)
                                    .lineLimit(2)

                                Text(draft.modelNumber.isEmpty ? "Model pending" : draft.modelNumber.uppercased())
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(EnterpriseTheme.textSecondary)

                                StatusBadge(text: draft.lookupStatus.displayLabel, tint: draft.lookupStatus.badgeTint)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 10) {
                                Text(draft.msrpText.isEmpty ? "—" : "$\(draft.msrpText)")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(draft.msrpText.isEmpty
                                        ? EnterpriseTheme.textTertiary
                                        : EnterpriseTheme.textPrimary)

                                Text("QTY \(draft.quantity)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(EnterpriseTheme.textSecondary)

                                Button("Review") {
                                    viewModel.selectedDraftID = draft.id
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(EnterpriseTheme.accentDim)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(EnterpriseTheme.accent.opacity(0.3), lineWidth: 0.5)
                                }

                                Button(role: .destructive) {
                                    viewModel.removeDraft(id: draft.id)
                                } label: {
                                    Text("Remove")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(EnterpriseTheme.danger)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(EnterpriseTheme.danger.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(EnterpriseTheme.danger.opacity(0.22), lineWidth: 0.5)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        viewModel.selectedDraftID = draft.id
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeDraft(id: draft.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var selectedDraftBinding: Binding<DraftManifestItem?> {
        Binding<DraftManifestItem?>(
            get: {
                guard let id = viewModel.selectedDraftID else { return nil }
                return viewModel.draftItems.first(where: { $0.id == id })
            },
            set: { newValue in
                if let newValue { viewModel.updateDraft(newValue) }
                viewModel.selectedDraftID = nil
            }
        )
    }

    private var draftUserID: UUID? {
        appViewModel.session?.user.id
    }

    private func persistLocalDraftIfNeeded() {
        guard existingManifest == nil, let userID = draftUserID else { return }
        if let snapshot = viewModel.autosaveSnapshot {
            draftStore.save(snapshot, userID: userID)
        } else {
            draftStore.clear(userID: userID)
        }
    }

    private func restoreLocalDraftIfNeeded() {
        guard existingManifest == nil, !hasRestoredLocalDraft else { return }
        hasRestoredLocalDraft = true
        guard let userID = draftUserID,
              let snapshot = draftStore.restore(userID: userID) else { return }
        viewModel.restore(from: snapshot)
    }

    private func clearLocalDraft() {
        guard existingManifest == nil, let userID = draftUserID else { return }
        draftStore.clear(userID: userID)
    }

    private func prepareScannedPhoto(_ data: Data) async {
        do {
            let detectedModel = try await viewModel.detectModelNumberForPhoto(data: data)
            pendingPhotoLookup = PendingPhotoLookup(
                imageData: data,
                detectedModelNumber: detectedModel,
                modelNumber: detectedModel,
                helperText: "Confirm the detected model number before LoadScan looks up the product."
            )
        } catch AppError.notAppliance {
            try? await Task.sleep(nanoseconds: 600_000_000)
            viewModel.notApplianceDetected = true
        } catch {
            if error.isNotApplianceIssue {
                try? await Task.sleep(nanoseconds: 600_000_000)
                viewModel.notApplianceDetected = true
                return
            }

            pendingPhotoLookup = PendingPhotoLookup(
                imageData: data,
                detectedModelNumber: "",
                modelNumber: "",
                helperText: "LoadScan could not confidently read the sticker. Enter the model number manually to continue."
            )
        }
    }

    private func confirmScannedPhoto(_ pending: PendingPhotoLookup) async -> Bool {
        do {
            try await viewModel.lookupScannedModelNumber(
                pending.modelNumber,
                imageData: pending.imageData,
                observedModelNumber: pending.detectedModelNumber
            )
            pendingPhotoLookup = nil
            return true
        } catch AppError.notAppliance {
            try? await Task.sleep(nanoseconds: 500_000_000)
            viewModel.notApplianceDetected = true
            return false
        } catch {
            if error.isNotApplianceIssue {
                try? await Task.sleep(nanoseconds: 500_000_000)
                viewModel.notApplianceDetected = true
                return false
            }

            viewModel.errorMessage = error.userMessage
            return false
        }
    }
}

// MARK: - Scanning Overlay

private struct ScanningOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(EnterpriseTheme.accent)
                    .scaleEffect(1.2)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EnterpriseTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        }
    }
}

private struct PendingPhotoLookup: Identifiable, Equatable {
    let id = UUID()
    let imageData: Data
    let detectedModelNumber: String
    var modelNumber: String
    let helperText: String
}

private struct DetectedModelReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: PendingPhotoLookup
    @FocusState private var focusedField: Bool
    let onConfirm: (PendingPhotoLookup) async -> Bool

    init(pending: PendingPhotoLookup, onConfirm: @escaping (PendingPhotoLookup) async -> Bool) {
        _pending = State(initialValue: pending)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: "Scan Check",
                            title: "Confirm model number",
                            subtitle: pending.helperText
                        )

                        if let image = UIImage(data: pending.imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(EnterpriseTheme.border, lineWidth: 1)
                                }
                        }

                        EnterpriseField(
                            title: "Detected Model Number",
                            prompt: "Enter model number",
                            text: $pending.modelNumber,
                            capitalization: .characters
                        )
                        .focused($focusedField)
                    }
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Sticker Read")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    if focusedField {
                        Button("Dismiss Keyboard") { focusedField = false }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())
                    }
                    Button("Search Product") {
                        focusedField = false
                        pending.modelNumber = ModelNumberNormalizer.normalize(pending.modelNumber)
                        Task {
                            if await onConfirm(pending) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                    .disabled(pending.modelNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.textSecondary)
                            .padding(7)
                            .background(EnterpriseTheme.surfacePrimary)
                            .clipShape(Circle())
                            .overlay { Circle().stroke(EnterpriseTheme.border, lineWidth: 1) }
                    }
                }
            }
            .enterpriseScreen()
        }
    }
}

// MARK: - Draft Review View

private struct DraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: DraftManifestItem
    @FocusState private var focusedField: Field?
    let onSave: (DraftManifestItem) async -> Void

    private enum Field {
        case model, name, msrp, ourPrice
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsCard
                    signalCard
                }
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Review Item")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    if focusedField != nil {
                        Button("Dismiss Keyboard") { focusedField = nil }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())
                    }
                    Button("Save Item") {
                        draft.modelNumber = ModelNumberNormalizer.normalize(draft.modelNumber)
                        Task {
                            await onSave(draft)
                            dismiss()
                        }
                    }
                    .buttonStyle(EnterprisePrimaryButtonStyle())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.textSecondary)
                            .padding(7)
                            .background(EnterpriseTheme.surfacePrimary)
                            .clipShape(Circle())
                            .overlay { Circle().stroke(EnterpriseTheme.border, lineWidth: 1) }
                    }
                }
            }
            .enterpriseScreen()
        }
    }

    private var detailsCard: some View {
        EnterpriseCard {
            EnterpriseSectionHeader(
                eyebrow: "Review",
                title: "Confirm appliance details",
                subtitle: "Confirm the model, product name, MSRP, our price, condition, and quantity before saving."
            )

            EnterpriseField(
                title: "Model Number",
                prompt: "Enter model number",
                text: $draft.modelNumber,
                capitalization: .characters
            )
            .focused($focusedField, equals: .model)
            .onSubmit { focusedField = .name }

            EnterpriseField(
                title: "Product Name",
                prompt: "Enter product name",
                text: $draft.productName
            )
            .focused($focusedField, equals: .name)
            .onSubmit { focusedField = .msrp }

            EnterpriseField(
                title: "MSRP",
                prompt: "0.00",
                text: $draft.msrpText,
                keyboardType: .decimalPad,
                capitalization: .never,
                submitLabel: .next
            )
            .focused($focusedField, equals: .msrp)
            .onSubmit { focusedField = .ourPrice }

            EnterpriseField(
                title: "Our Price",
                prompt: "0.00",
                text: $draft.ourPriceText,
                keyboardType: .decimalPad,
                capitalization: .never,
                submitLabel: .done
            )
            .focused($focusedField, equals: .ourPrice)

            // Condition picker
            VStack(alignment: .leading, spacing: 7) {
                Text("CONDITION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .tracking(1.2)

                Picker("Condition", selection: $draft.condition) {
                    ForEach(ItemCondition.allCases) { condition in
                        Text(condition.displayLabel).tag(condition)
                    }
                }
                .pickerStyle(.segmented)
                .tint(EnterpriseTheme.accent)
            }
            .padding(14)
            .background(EnterpriseTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }

            // Quantity stepper
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUANTITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.2)
                    Text("\(draft.quantity)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                }
                Spacer()
                Stepper("", value: $draft.quantity, in: 1...50)
                    .labelsHidden()
                    .tint(EnterpriseTheme.accent)
            }
            .padding(14)
            .background(EnterpriseTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
        }
    }

    private var signalCard: some View {
        EnterpriseCard {
            EnterpriseSectionHeader(eyebrow: "Lookup", title: "Signal quality")

            HStack(spacing: 14) {
                StatusBadge(text: draft.lookupStatus.displayLabel, tint: draft.lookupStatus.badgeTint)

                if draft.confidence > 0 {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CONFIDENCE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EnterpriseTheme.textTertiary)
                            .tracking(1.2)
                        Text("\(Int(draft.confidence * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(draft.confidence > 0.7
                                ? EnterpriseTheme.success
                                : draft.confidence > 0.4
                                    ? EnterpriseTheme.warning
                                    : EnterpriseTheme.danger)
                    }
                }
            }

            if !draft.source.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.caption2)
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Text("Source: \(draft.source)")
                        .font(.caption)
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Camera Picker

private struct CameraPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
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

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }
    }
}
