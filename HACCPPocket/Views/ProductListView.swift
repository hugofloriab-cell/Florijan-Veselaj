//
//  ProductListView.swift
//  HACCPPocket
//
//  Registre des produits entamés : ce qui est en cours, ce qui presse, et
//  l'historique des produits consommés ou jetés.
//

import SwiftUI
import SwiftData

struct ProductListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(UserPreferences.self) private var preferences

    @Query(sort: \TrackedProduct.secondaryLimitDate) private var products: [TrackedProduct]

    @State private var viewModel: ProductTrackingViewModel?
    @State private var editedProduct: TrackedProduct?
    @State private var isCreating = false
    @State private var showsPaywall = false
    @State private var productPendingDeletion: TrackedProduct?
    @State private var labelProduct: TrackedProduct?
    @State private var isScanning = false
    @State private var scanMessage: String?
    @State private var scanPrefill: ProductPrefill?

    /// Produit en cours de mise au rebut : l'alerte demande le motif.
    @State private var discardTarget: TrackedProduct?
    @State private var discardReason = ""

    private var displayed: [TrackedProduct] {
        viewModel?.present(products) ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Produits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if subscription.canWrite {
                            isCreating = true
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        Label("Nouveau produit", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scanner une étiquette", systemImage: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                ProductFormView(context: modelContext)
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .sheet(item: $labelProduct) { product in
                LabelPrintView(product: product)
            }
            .sheet(isPresented: $isScanning) {
                QRScannerView { code in
                    handleScan(code)
                }
            }
            .sheet(item: $scanPrefill) { prefill in
                ProductFormView(prefill: prefill, context: modelContext)
            }
            .alert(
                "Étiquette non reconnue",
                isPresented: Binding(
                    get: { scanMessage != nil },
                    set: { if !$0 { scanMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { scanMessage = nil }
            } message: {
                Text(scanMessage ?? "")
            }
            .confirmationDialog(
                "Supprimer ce produit ?",
                isPresented: Binding(
                    get: { productPendingDeletion != nil },
                    set: { if !$0 { productPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let product = productPendingDeletion { viewModel?.delete(product) }
                    productPendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { productPendingDeletion = nil }
            } message: {
                Text("À réserver à une saisie erronée : un produit réellement utilisé doit rester dans le registre.")
            }
            .sheet(item: $editedProduct) { product in
                ProductFormView(product: product, context: modelContext)
            }
            .alert("Mise au rebut", isPresented: Binding(
                get: { discardTarget != nil },
                set: { if !$0 { discardTarget = nil } }
            )) {
                TextField("Motif", text: $discardReason)
                Button("Confirmer") { confirmDiscard() }
                Button("Annuler", role: .cancel) { discardTarget = nil }
            } message: {
                Text("Le motif est obligatoire : il justifie la destruction en cas de contrôle.")
            }
            .task {
                if viewModel == nil {
                    viewModel = ProductTrackingViewModel(context: modelContext)
                }
            }
        }
    }

    // MARK: - Contenu

    private func content(viewModel: ProductTrackingViewModel) -> some View {
        List {
            Section {
                Picker("Filtre", selection: Bindable(viewModel).filter) {
                    ForEach(ProductTrackingViewModel.Filter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            ForEach(displayed) { product in
                Button {
                    editedProduct = product
                } label: {
                    row(for: product)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if !subscription.canWrite {
                        Button {
                            showsPaywall = true
                        } label: {
                            Label("Débloquer", systemImage: "lock")
                        }
                        .tint(.orange)
                    } else if product.status == .inUse {
                        Button {
                            discardReason = viewModel.suggestedDiscardReason(for: product)
                            discardTarget = product
                        } label: {
                            Label("Jeter", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            viewModel.markConsumed(product)
                        } label: {
                            Label("Consommé", systemImage: "checkmark")
                        }
                        .tint(.green)
                    } else {
                        Button {
                            viewModel.reopen(product)
                        } label: {
                            Label("Rouvrir", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(role: .destructive) {
                        productPendingDeletion = product
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }

                    Button {
                        labelProduct = product
                    } label: {
                        Label("Étiquette", systemImage: "printer")
                    }
                    .tint(.indigo)

                    Button {
                        guard subscription.canWrite else { showsPaywall = true; return }
                        editedProduct = viewModel.duplicate(
                            product,
                            shelfLifeDays: preferences.defaultShelfLifeDays
                        )
                    } label: {
                        Label("Ré-entamer", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(.brand)
                }
            }
        }
        .searchable(text: Bindable(viewModel).searchText, prompt: "Nom, lot ou fournisseur")
        .overlay {
            if displayed.isEmpty {
                emptyState(for: viewModel.filter)
            }
        }
    }

    private func row(for product: TrackedProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(product.name)
                    .font(.headline)
                Spacer()
                StatusBadge(
                    text: product.remainingLabel(),
                    color: product.status == .inUse ? product.urgency().color : .secondary,
                    systemImage: product.status == .inUse ? product.urgency().systemImage : product.status.systemImage
                )
            }

            HStack(spacing: 10) {
                Label(product.storage.label, systemImage: product.storage.systemImage)
                if !product.batchNumber.isEmpty {
                    Label(product.batchNumber, systemImage: "number")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Ouvert le \(AppFormatters.shortDate(product.openedAt)) · à retirer le \(AppFormatters.shortDate(product.effectiveLimitDate))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if product.status == .discarded, !product.discardReason.isEmpty {
                Text(product.discardReason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyState(for filter: ProductTrackingViewModel.Filter) -> some View {
        switch filter {
        case .active:
            ContentUnavailableView {
                Label("Aucun produit entamé", systemImage: "shippingbox")
            } description: {
                Text("Ajoutez un produit dès son ouverture pour suivre sa DLC secondaire.")
            } actions: {
                Button("Ajouter un produit") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        case .expiringSoon:
            ContentUnavailableView(
                "Rien à traiter",
                systemImage: "checkmark.seal",
                description: Text("Aucun produit n'arrive en fin de DLC secondaire.")
            )
        case .closed:
            ContentUnavailableView(
                "Historique vide",
                systemImage: "archivebox",
                description: Text("Les produits consommés ou jetés apparaîtront ici.")
            )
        }
    }

    // MARK: - Actions

    /// Aiguille un code scanné : étiquette de l'app, code fournisseur porteur
    /// d'une DLC, ou simple code-barres à compléter à la main.
    private func handleScan(_ code: String) {
        // 1. Une de nos étiquettes : on rouvre la fiche existante.
        if let identifier = LabelPayload.decode(code) {
            if let product = products.first(where: { $0.identifier == identifier }) {
                editedProduct = product
            } else {
                scanMessage = "Le produit correspondant à cette étiquette n'existe plus dans l'application."
            }
            return
        }

        guard subscription.canWrite else {
            showsPaywall = true
            return
        }

        // 2. Code fournisseur : on n'en tire que ce qu'il contient réellement.
        let reading = BarcodePayload.parse(code)
        var prefill = ProductPrefill(barcode: reading.productCode)
        var origins: [String] = []

        if let date = reading.mostRestrictiveDate {
            prefill.supplierExpiryDate = date
            origins.append("DLC lue sur le code : \(AppFormatters.shortDate(date))")
        }

        if let batch = reading.batchNumber {
            prefill.batchNumber = batch
            origins.append("lot \(batch)")
        }

        // 3. Déjà ouvert par le passé ? On reprend ce qui avait été saisi.
        if let previous = previousProduct(withCode: reading.productCode) {
            prefill.name = previous.name
            prefill.supplier = previous.supplier
            prefill.storage = previous.storage
            prefill.shelfLifeDays = shelfLife(of: previous)
            origins.append("produit reconnu dans votre historique")
        }

        if origins.isEmpty {
            origins.append("Ce code ne contient ni date ni lot : complétez la fiche à la main.")
        }

        prefill.origin = origins.joined(separator: " · ")
        scanPrefill = prefill
    }

    /// Produit le plus récent partageant ce code-barres.
    private func previousProduct(withCode code: String) -> TrackedProduct? {
        guard !code.isEmpty else { return nil }
        return products
            .filter { $0.barcode == code }
            .max { $0.openedAt < $1.openedAt }
    }

    /// Durée de vie appliquée la dernière fois à ce produit.
    private func shelfLife(of product: TrackedProduct, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: product.openedAt),
            to: calendar.startOfDay(for: product.secondaryLimitDate)
        ).day ?? preferences.defaultShelfLifeDays
        return max(0, days)
    }

    private func confirmDiscard() {
        guard let product = discardTarget, let viewModel else { return }
        viewModel.markDiscarded(product, reason: discardReason)
        discardTarget = nil
        discardReason = ""
    }
}
