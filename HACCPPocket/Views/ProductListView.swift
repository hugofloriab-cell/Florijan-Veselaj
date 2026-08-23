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

    @Query(sort: \TrackedProduct.secondaryLimitDate) private var products: [TrackedProduct]

    @State private var viewModel: ProductTrackingViewModel?
    @State private var editedProduct: TrackedProduct?
    @State private var isCreating = false
    @State private var showsPaywall = false
    @State private var productPendingDeletion: TrackedProduct?
    @State private var labelProduct: TrackedProduct?
    @State private var isScanning = false
    @State private var scanMessage: String?

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

    /// Retrouve le produit désigné par le QR d'une étiquette et ouvre sa fiche.
    private func handleScan(_ code: String) {
        guard let identifier = LabelPayload.decode(code) else {
            scanMessage = "Ce QR code ne provient pas d'une étiquette HACCP Pocket."
            return
        }

        guard let product = products.first(where: { $0.identifier == identifier }) else {
            scanMessage = "Le produit correspondant à cette étiquette n'existe plus dans l'application."
            return
        }

        editedProduct = product
    }

    private func confirmDiscard() {
        guard let product = discardTarget, let viewModel else { return }
        viewModel.markDiscarded(product, reason: discardReason)
        discardTarget = nil
        discardReason = ""
    }
}
