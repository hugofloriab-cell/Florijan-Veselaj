//
//  ProductFormView.swift
//  HACCPPocket
//
//  Fiche d'un produit entamé. Le scan de l'étiquette pré-remplit la DLC
//  fournisseur et le code-barres ; la DLC secondaire se calcule toute seule.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct ProductFormView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ProductFormViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isPresentingCamera = false

    init(product: TrackedProduct? = nil, prefill: ProductPrefill? = nil, context: ModelContext) {
        _viewModel = State(
            initialValue: ProductFormViewModel(product: product, prefill: prefill, context: context)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                prefillBanner
                identificationSection
                Section { ProtocolLink(procedure: .productLabelling) }
                categorySection
                storageSection
                datesSection
                labelSection
                allergenSection
                notesSection
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if viewModel.save() != nil { dismiss() }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isPresentingCamera) {
                CameraPicker(
                    onCapture: { data in
                        Task { await viewModel.scanLabel(imageData: data) }
                    },
                    onFinish: { isPresentingCamera = false }
                )
                .ignoresSafeArea()
            }
            #endif
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var prefillBanner: some View {
        if let origin = viewModel.prefillOrigin {
            Section {
                Label(origin, systemImage: "barcode.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.brand)
            }
        }
    }

    private var identificationSection: some View {
        Section("Produit") {
            TextField("Nom (ex. Crème fraîche 35 %)", text: Bindable(viewModel).name)
            TextField("Fournisseur", text: Bindable(viewModel).supplier)
            TextField("Numéro de lot", text: Bindable(viewModel).batchNumber)
            TextField("Code-barres", text: Bindable(viewModel).barcode)
        }
    }

    private var storageSection: some View {
        Section("Stockage") {
            Picker("Zone", selection: Bindable(viewModel).storage) {
                ForEach(StorageZone.allCases) { zone in
                    Label(zone.label, systemImage: zone.systemImage).tag(zone)
                }
            }
        }
    }

    /// Choisir une famille plutôt que saisir un nombre de jours : le
    /// cuisinier sait ce qu'il vient d'ouvrir, il n'a pas à connaître la
    /// durée d'usage de chaque denrée ni à compter sur ses doigts.
    private var categorySection: some View {
        Section {
            ForEach(FoodCategory.allCases) { category in
                Button {
                    viewModel.apply(category)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(.brand)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(limitPreview(for: category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        RegulatoryBadge(note: category.note)

                        if viewModel.category == category {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.brand)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Qu'avez-vous ouvert ?")
        } footer: {
            Text("Facultatif : appuyez sur une famille et la durée de vie se règle toute seule. Ces durées sont des usages professionnels, pas un tableau réglementaire — ajustez-les si votre plan de maîtrise sanitaire dit autre chose.")
        }
    }

    /// La date exacte, calculée tout de suite : plus de « J+3 » à traduire
    /// mentalement en jour de la semaine.
    private func limitPreview(for category: FoodCategory) -> String {
        let limit = TrackedProduct.defaultLimitDate(
            openedAt: viewModel.openedAt,
            days: category.shelfLifeDays
        )
        return "J+\(category.shelfLifeDays) — à retirer le \(AppFormatters.shortDate(limit))"
    }

    private var datesSection: some View {
        Section {
            DatePicker("Ouvert le", selection: Bindable(viewModel).openedAt, in: ...Date.now)

            Stepper(
                "Durée de vie : \(viewModel.shelfLifeDays) jour(s)",
                value: Bindable(viewModel).shelfLifeDays,
                in: 0...30
            )

            Toggle("DLC imprimée par le fournisseur", isOn: Bindable(viewModel).hasSupplierExpiry)

            if viewModel.hasSupplierExpiry {
                DatePicker(
                    "DLC fournisseur",
                    selection: Bindable(viewModel).supplierExpiryDate,
                    displayedComponents: .date
                )
            }

            HStack {
                Text("À retirer le")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(AppFormatters.shortDate(viewModel.effectiveLimitDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.brand)
            }
        } header: {
            Text("Dates limites")
        } footer: {
            if viewModel.supplierDateWins {
                Label(
                    "La DLC du fournisseur est plus courte que la règle des \(viewModel.shelfLifeDays) jours : c'est elle qui s'applique.",
                    systemImage: "info.circle"
                )
            } else if viewModel.hasCustomShelfLife, let category = viewModel.category {
                Label(
                    "Durée modifiée à la main : \(category.label) suggérait \(category.shelfLifeDays) jour(s). C'est vous qui décidez, mais gardez de quoi le justifier.",
                    systemImage: "pencil.circle"
                )
            } else {
                Text("La date de retrait est calculée à partir de l'ouverture. On ne prolonge jamais un produit au-delà de la DLC du fournisseur.")
            }
        }
    }

    private var labelSection: some View {
        Section {
            if let data = viewModel.labelPhotoData, let image = platformImage(from: data) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            #if canImport(UIKit)
            if CameraPicker.isAvailable {
                Button {
                    isPresentingCamera = true
                } label: {
                    Label("Photographier l'étiquette", systemImage: "camera")
                }
            }
            #endif

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choisir une photo", systemImage: "photo.on.rectangle")
            }

            if viewModel.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lecture de l'étiquette…")
                        .foregroundStyle(.secondary)
                }
            }

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Étiquette")
        } footer: {
            Text("La photo est analysée sur l'appareil pour retrouver la DLC et le code-barres. Aucune image n'est envoyée sur Internet.")
        }
    }

    private var allergenSection: some View {
        Section {
            AllergenSummaryRow(
                selection: Bindable(viewModel).allergens,
                subject: viewModel.name.isEmpty ? "Allergènes" : viewModel.name
            )
        } header: {
            Text("Allergènes")
        } footer: {
            Text("Recopiez ce qui est déclaré sur l'emballage. Ces allergènes vous seront rappelés au moment de renseigner les plats qui utilisent ce produit.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Observations (facultatif)", text: Bindable(viewModel).notes, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    // MARK: - Photothèque

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await viewModel.scanLabel(imageData: data)
    }

    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
