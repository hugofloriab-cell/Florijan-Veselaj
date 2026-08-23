//
//  DeliveryFormView.swift
//  HACCPPocket
//
//  Contrôle d'une livraison. Le seuil de température se déduit de la famille
//  de denrées, et un refus impose un motif écrit.
//

import SwiftUI
import SwiftData

struct DeliveryFormView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DeliveryCheckViewModel

    init(check: DeliveryCheck? = nil, context: ModelContext) {
        _viewModel = State(initialValue: DeliveryCheckViewModel(check: check, context: context))
    }

    var body: some View {
        NavigationStack {
            Form {
                supplierSection
                temperatureSection
                controlsSection
                decisionSection
                detailsSection
            }
            .navigationTitle(viewModel.isEditing ? "Modifier le contrôle" : "Contrôle à réception")
            .navigationBarTitleDisplayMode(.inline)
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

    private var detailsSection: some View {
        Section("Détails") {
            OperatorField(name: Bindable(viewModel).operatorName)
            TextField("Observations", text: Bindable(viewModel).notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
