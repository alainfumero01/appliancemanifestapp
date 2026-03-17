import SwiftUI

struct ManifestDetailView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    let manifestID: UUID
    @State private var exportedManifest: ExportedManifest?
    @State private var editingItem: ManifestItem?
    @State private var isPresentingAddItems = false
    @FocusState private var editingField: Field?

    private enum Field {
        case title, loadReference
    }

    private var manifest: Binding<Manifest>? {
        guard let index = appViewModel.manifests.firstIndex(where: { $0.id == manifestID }) else { return nil }
        return $appViewModel.manifests[index]
    }

    var body: some View {
        Group {
            if let manifest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        editCard(manifest: manifest)
                        itemsSection(manifest: manifest)
                        summaryCard(manifest: manifest)
                    }
                    .padding(.horizontal, EnterpriseTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 130)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    EnterpriseActionBar {
                        if editingField != nil {
                            Button("Dismiss Keyboard") { editingField = nil }
                                .buttonStyle(EnterpriseSecondaryButtonStyle())
                        }
                        HStack(spacing: 10) {
                            if manifest.wrappedValue.status == .draft {
                                Button("Add Items") {
                                    editingField = nil
                                    isPresentingAddItems = true
                                }
                                .buttonStyle(EnterpriseSecondaryButtonStyle())
                            }
                            Button("Export") {
                                editingField = nil
                                Task {
                                    exportedManifest = try? await appViewModel.backend.exportManifest(manifest.wrappedValue)
                                }
                            }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())

                            Button("Save") {
                                editingField = nil
                                Task { await appViewModel.saveManifest(manifest.wrappedValue) }
                            }
                            .buttonStyle(EnterprisePrimaryButtonStyle())
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        EmptyView()
                    }
                }
                .sheet(item: $exportedManifest) { export in
                    ShareSheet(activityItems: [export.fileURL])
                }
                .sheet(item: $editingItem) { item in
                    ItemEditView(item: item) { updated in
                        await appViewModel.updateItem(updated, in: manifest.wrappedValue)
                    }
                }
                .sheet(isPresented: $isPresentingAddItems) {
                    NewManifestView(
                        isPresented: $isPresentingAddItems,
                        backend: appViewModel.backend,
                        existingManifest: manifest.wrappedValue
                    )
                    .environmentObject(appViewModel)
                }
            } else {
                ContentUnavailableView("Load not found", systemImage: "tray")
                    .preferredColorScheme(.light)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .enterpriseScreen()
    }

    // MARK: - Edit Card

    private func editCard(manifest: Binding<Manifest>) -> some View {
        EnterpriseCard {
            EnterpriseSectionHeader(
                eyebrow: "Load Manifest",
                title: manifest.wrappedValue.title,
                subtitle: "Review load details, scanned items, and export-ready totals."
            )

            EnterpriseField(
                title: "Manifest Title",
                prompt: "Manifest title",
                text: manifest.title
            )
            .focused($editingField, equals: .title)
            .onSubmit { editingField = .loadReference }

            EnterpriseField(
                title: "Load Reference",
                prompt: "Load reference",
                text: manifest.loadReference,
                capitalization: .never
            )
            .focused($editingField, equals: .loadReference)

            VStack(alignment: .leading, spacing: 7) {
                Text("STATUS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.textSecondary)
                    .tracking(1.2)

                Picker("Status", selection: manifest.status) {
                    ForEach(ManifestStatus.allCases) { status in
                        Text(status.displayLabel).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .tint(EnterpriseTheme.accent)
            }
        }
    }

    // MARK: - Items Section

    private func itemsSection(manifest: Binding<Manifest>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(EnterpriseTheme.textTertiary)
                        .frame(width: 12, height: 2)
                    Text("SCANNED ITEMS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.6)
                }
                Spacer()
                Text("\(manifest.wrappedValue.items.count) items")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textTertiary)
            }

            if manifest.wrappedValue.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 26))
                        .foregroundStyle(EnterpriseTheme.textTertiary)
                    Text("No items scanned yet.")
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
                ForEach(Array(manifest.wrappedValue.items.enumerated()), id: \.element.id) { index, item in
                    ItemLineCard(item: item, index: index + 1)
                        .onTapGesture { editingItem = item }
                        .swipeActions {
                            Button(role: .destructive) {
                                let deletions = [item]
                                var updatedManifest = manifest.wrappedValue
                                updatedManifest.items.remove(at: index)
                                manifest.wrappedValue = updatedManifest
                                Task {
                                    await appViewModel.deleteItems(deletions, from: manifest.wrappedValue)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Summary Card

    private func summaryCard(manifest: Binding<Manifest>) -> some View {
        EnterpriseCard(accentLeft: EnterpriseTheme.success) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(EnterpriseTheme.success)
                    .frame(width: 12, height: 2)
                Text("LOAD SUMMARY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EnterpriseTheme.success)
                    .tracking(1.6)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL MSRP")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.2)
                    Text(Formatters.currencyString(manifest.wrappedValue.totalMSRP))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ITEMS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                        .tracking(1.2)
                    Text("\(manifest.wrappedValue.items.count)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                }
            }
        }
    }
}

// MARK: - Item Line Card

private struct ItemLineCard: View {
    let item: ManifestItem
    let index: Int

    var body: some View {
        EnterpriseCard(padding: 14, accentLeft: item.lookupStatus.badgeTint) {
            // Row number + product
            HStack(alignment: .top, spacing: 10) {
                // Index badge
                Text(String(format: "%02d", index))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(EnterpriseTheme.textTertiary)
                    .frame(width: 24, alignment: .leading)

                // Product info
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.productName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)
                        .lineLimit(2)

                    Text(item.modelNumber.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(EnterpriseTheme.textSecondary)

                    HStack(spacing: 6) {
                        StatusBadge(text: item.lookupStatus.displayLabel, tint: item.lookupStatus.badgeTint)
                        StatusBadge(text: item.condition.displayLabel, tint: EnterpriseTheme.textTertiary)
                    }
                }

                Spacer()

                // Financials
                VStack(alignment: .trailing, spacing: 5) {
                    if item.ourPrice > 0 {
                        Text(Formatters.currencyString(item.ourLineTotal))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(EnterpriseTheme.textPrimary)
                        HStack(spacing: 4) {
                            Text("OUR")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                                .tracking(0.8)
                            Text("×\(item.quantity) @ \(Formatters.currencyString(item.ourPrice))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                        }
                        HStack(spacing: 4) {
                            Text("MSRP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                                .tracking(0.8)
                            Text(Formatters.currencyString(item.lineTotal))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                        }
                    } else {
                        Text(Formatters.currencyString(item.lineTotal))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(EnterpriseTheme.textPrimary)
                        HStack(spacing: 4) {
                            Text("×\(item.quantity)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                            Text("@")
                                .font(.system(size: 10))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                            Text(Formatters.currencyString(item.msrp))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(EnterpriseTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Item Edit View

private struct ItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ManifestItem
    @State private var msrpText: String
    @State private var ourPriceText: String
    @FocusState private var focusedField: Field?
    let onSave: (ManifestItem) async -> Void

    private enum Field {
        case model, name, msrp, ourPrice
    }

    init(item: ManifestItem, onSave: @escaping (ManifestItem) async -> Void) {
        _item = State(initialValue: item)
        _msrpText = State(initialValue: NSDecimalNumber(decimal: item.msrp).stringValue)
        _ourPriceText = State(initialValue: item.ourPrice > 0
            ? NSDecimalNumber(decimal: item.ourPrice).stringValue
            : "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnterpriseCard {
                        EnterpriseSectionHeader(
                            eyebrow: "Edit",
                            title: "Edit appliance details",
                            subtitle: "Update any field, then tap Save Item."
                        )

                        EnterpriseField(
                            title: "Model Number",
                            prompt: "Enter model number",
                            text: $item.modelNumber,
                            capitalization: .characters
                        )
                        .focused($focusedField, equals: .model)
                        .onSubmit { focusedField = .name }

                        EnterpriseField(
                            title: "Product Name",
                            prompt: "Enter product name",
                            text: $item.productName
                        )
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .msrp }

                        EnterpriseField(
                            title: "MSRP",
                            prompt: "0.00",
                            text: $msrpText,
                            keyboardType: .decimalPad,
                            capitalization: .never,
                            submitLabel: .next
                        )
                        .focused($focusedField, equals: .msrp)
                        .onSubmit { focusedField = .ourPrice }

                        EnterpriseField(
                            title: "Our Price",
                            prompt: "0.00",
                            text: $ourPriceText,
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

                            Picker("Condition", selection: $item.condition) {
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
                                Text("\(item.quantity)")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .foregroundStyle(EnterpriseTheme.textPrimary)
                            }
                            Spacer()
                            Stepper("", value: $item.quantity, in: 1...50)
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
                .padding(.horizontal, EnterpriseTheme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                EnterpriseActionBar {
                    if focusedField != nil {
                        Button("Dismiss Keyboard") { focusedField = nil }
                            .buttonStyle(EnterpriseSecondaryButtonStyle())
                    }
                    Button("Save Item") {
                        item.msrp = Decimal(string: msrpText) ?? item.msrp
                        item.ourPrice = Decimal(string: ourPriceText) ?? 0
                        item.modelNumber = ModelNumberNormalizer.normalize(item.modelNumber)
                        Task {
                            await onSave(item)
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
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
