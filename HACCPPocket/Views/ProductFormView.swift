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

    init(product: TrackedProduct? = nil, context: ModelContext) {
        _viewModel = State(initialValue: ProductFormViewModel(product: product, context: context))
    }

    var body: some View {
        NavigationStack {
            Form {
                identificationSection
                storageSection
                datesSection
                labelSection
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
                    .foregroundStyle(.teal)
            }
        } header: {
            Text("Dates limites")
        } footer: {
            if viewModel.supplierDateWins {
                Label(
                    "La DLC du fournisseur est plus courte que la règle des \(viewModel.shelfLifeDays) jours : c'est elle qui s'applique.",
                    systemImage: "info.circle"
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
