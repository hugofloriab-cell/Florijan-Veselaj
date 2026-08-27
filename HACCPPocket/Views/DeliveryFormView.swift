//
//  DeliveryFormView.swift
//  HACCPPocket
//
//  Contrôle d'une livraison. Le seuil de température se déduit de la famille
//  de denrées, un refus impose un motif écrit, et au moins une pièce
//  justificative doit être photographiée.
//
//  L'ordre de la capture est imposé : on annonce la nature du document, puis
//  on le photographie. Demander la nature après coup revient à ne jamais la
//  demander — le téléphone est déjà rangé.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct DeliveryFormView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DeliveryCheckViewModel
    @State private var pendingKind: DeliveryDocumentKind?

    init(check: DeliveryCheck? = nil, context: ModelContext) {
        _viewModel = State(initialValue: DeliveryCheckViewModel(check: check, context: context))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .delivery) }
                supplierSection
                temperatureSection
                controlsSection
                decisionSection
                documentsSection
                detailsSection
            }
            .navigationTitle(viewModel.isEditing ? "Modifier le contrôle" : "Contrôle à réception")
            .navigationBarTitleDisplayMode(.inline)
            // La nature est choisie d'abord ; cette feuille explique quoi
            // cadrer, puis ouvre l'appareil photo. Posée sur le formulaire et
            // non sur la section : une présentation depuis l'intérieur d'une
            // `Section` ne se déclenche pas de façon fiable.
            .sheet(item: $pendingKind) { kind in
                PhotoCaptureSheet(title: kind.label, message: kind.captureHint) { data in
                    viewModel.addDocument(kind: kind, photoData: data)
                    pendingKind = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if viewModel.save() { dismiss() }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var supplierSection: some View {
        Section("Livraison") {
            TextField("Fournisseur", text: Bindable(viewModel).supplierName)
            TextField("Marchandise", text: Bindable(viewModel).productLabel)
            TextField("Numéro de lot", text: Bindable(viewModel).batchNumber)
            DatePicker("Reçue le", selection: Bindable(viewModel).receivedAt, in: ...Date.now)
        }
    }

    private var temperatureSection: some View {
        Section {
            Picker("Famille", selection: Bindable(viewModel).category) {
                ForEach(DeliveryCheckViewModel.GoodsCategory.allCases) { category in
                    Text(category.label).tag(category)
                }
            }

            if viewModel.category.requiresTemperature {
                HStack {
                    Text("Température relevée")
                    Spacer()
                    TextField("0,0", text: Bindable(viewModel).temperatureText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .frame(maxWidth: 100)
                    Text("°C").foregroundStyle(.secondary)
                }

                if viewModel.temperature != nil {
                    Label(
                        viewModel.isTemperatureCompliant ? "Température conforme" : "Température hors seuil",
                        systemImage: viewModel.isTemperatureCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.isTemperatureCompliant ? Color.green : Color.red)
                }
            }
        } header: {
            Text("Température")
        } footer: {
            if let limit = viewModel.temperatureLimit {
                Text("Seuil maximal admis pour cette famille : \(AppFormatters.temperature(limit)).")
            } else {
                Text("L'épicerie sèche ne fait pas l'objet d'un relevé de température.")
            }
        }
    }

    private var controlsSection: some View {
        Section("Points de contrôle") {
            Toggle("Emballage intact", isOn: Bindable(viewModel).packagingIntact)
            Toggle("Étiquetage conforme", isOn: Bindable(viewModel).labellingCompliant)
        }
    }

    private var decisionSection: some View {
        Section {
            Picker("Décision", selection: Bindable(viewModel).decision) {
                ForEach(DeliveryDecision.allCases) { decision in
                    Label(decision.label, systemImage: decision.systemImage).tag(decision)
                }
            }

            if viewModel.requiresReason {
                TextField("Motif du refus ou de la réserve", text: Bindable(viewModel).reason, axis: .vertical)
                    .lineLimit(2...5)

                if !viewModel.anomalies.isEmpty {
                    Button {
                        viewModel.fillReasonFromAnomalies()
                    } label: {
                        Label("Reprendre les anomalies détectées", systemImage: "text.badge.plus")
                    }
                }
            }
        } header: {
            Text("Décision")
        } footer: {
            if !viewModel.anomalies.isEmpty {
                Label(
                    "Anomalies constatées : \(viewModel.anomalies.joined(separator: ", ")).",
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                Text("Livraison conforme sur les trois points de contrôle.")
            }
        }
    }

    // MARK: - Pièces justificatives

    private var documentsSection: some View {
        Section {
            ForEach(viewModel.documents) { draft in
                documentRow(draft)
            }

            Menu {
                ForEach(DeliveryDocumentKind.allCases) { kind in
                    Button {
                        pendingKind = kind
                    } label: {
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                }
            } label: {
                Label("Photographier un document", systemImage: "camera")
            }
        } header: {
            Text("Pièces justificatives")
        } footer: {
            if viewModel.isMissingDocument {
                Label(
                    "Photographiez au moins le bon de livraison ou la facture. C'est la pièce qui rattache cette réception à un fournisseur et à un lot.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            } else if viewModel.requiresReason && viewModel.capturedDocuments.allSatisfy({ $0.kind != .nonConformity }) {
                Text("Un refus se défend mieux avec une photo de ce qui a été constaté : ajoutez un constat de non-conformité.")
            } else {
                Text("Ces photos ne figurent pas dans le registre mensuel. Elles se consultent et s'impriment depuis la page Photos des registres.")
            }
        }
    }

    private func documentRow(_ draft: DeliveryCheckViewModel.DraftDocument) -> some View {
        HStack(spacing: 12) {
            #if canImport(UIKit)
            if let data = draft.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                RowIcon(systemImage: draft.kind.systemImage, tint: .teal)
            }
            #else
            RowIcon(systemImage: draft.kind.systemImage, tint: .teal)
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.kind.label)
                    .font(.subheadline.weight(.medium))
                Text(AppFormatters.dateAndTime(draft.capturedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                viewModel.removeDocument(id: draft.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private var detailsSection: some View {
        Section("Détails") {
            OperatorField(name: Bindable(viewModel).operatorName)
            TextField("Observations", text: Bindable(viewModel).notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
