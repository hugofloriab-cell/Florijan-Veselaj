//
//  TemperatureEntryView.swift
//  HACCPPocket
//
//  Formulaire de saisie d'un relevé. La conformité s'affiche en direct et le
//  bouton Enregistrer reste désactivé tant qu'un écart n'est pas justifié.
//

import SwiftUI
import SwiftData

struct TemperatureEntryView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TemperatureLogViewModel
    @State private var showsDeleteConfirmation = false
    @FocusState private var isValueFocused: Bool

    /// Le `ModelContext` est passé par la vue appelante : il n'est pas
    /// accessible depuis l'environnement au moment de construire le ViewModel.
    init(
        equipment: Equipment,
        moment: ReadingMoment?,
        reading: TemperatureReading? = nil,
        context: ModelContext
    ) {
        _viewModel = State(
            initialValue: TemperatureLogViewModel(
                equipment: equipment,
                reading: reading,
                moment: moment,
                context: context
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                equipmentSection
                valueSection

                if viewModel.requiresCorrectiveAction {
                    correctiveActionSection(model: viewModel)
                }

                detailsSection(model: viewModel)

                if viewModel.isEditing {
                    Section {
                        Button("Supprimer ce relevé", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Modifier le relevé" : "Nouveau relevé")
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
            .confirmationDialog(
                "Supprimer ce relevé ?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if viewModel.deleteExisting() { dismiss() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("À n'utiliser que pour corriger une saisie erronée : les enregistrements doivent être conservés.")
            }
            .onAppear { isValueFocused = true }
        }
    }

    // MARK: - Sections

    private var equipmentSection: some View {
        Section {
            InfoRow(
                label: viewModel.equipment.name,
                value: viewModel.equipment.formattedRange,
                systemImage: viewModel.equipment.type.systemImage
            )
        }
    }

    private var valueSection: some View {
        Section {
            HStack {
                TextField("0,0", text: Bindable(viewModel).valueText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($isValueFocused)

                Text("°C")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

            statusBanner
        } header: {
            Text("Température relevée")
        } footer: {
            if let hint = viewModel.validationHint {
                Text(hint)
            } else {
                Text("Plage attendue : \(viewModel.equipment.formattedRange)")
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let isCompliant = viewModel.isCompliant {
            HStack(spacing: 10) {
                Image(systemName: isCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isCompliant ? .green : .red)
                Text(isCompliant ? "Relevé conforme" : "Relevé hors plage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCompliant ? .green : .red)
                Spacer()
                if let deviation = viewModel.deviation, deviation != 0 {
                    Text(AppFormatters.deviation(deviation))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func correctiveActionSection(model: TemperatureLogViewModel) -> some View {
        Section {
            TextField(
                "Ex. porte refermée, denrées transférées, retour en température vérifié",
                text: Bindable(model).correctiveAction,
                axis: .vertical
            )
            .lineLimit(3...6)
        } header: {
            Label("Action corrective", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("Obligatoire : un écart sans action corrective rend le registre incomplet en cas de contrôle.")
        }
    }

    private func detailsSection(model: TemperatureLogViewModel) -> some View {
        Section("Détails") {
            Picker("Moment", selection: Bindable(model).moment) {
                ForEach(ReadingMoment.allCases) { moment in
                    Label(moment.label, systemImage: moment.systemImage).tag(moment)
                }
            }

            DatePicker(
                "Date et heure",
                selection: Bindable(model).recordedAt,
                in: ...Date.now
            )

            TextField("Opérateur", text: Bindable(model).operatorName)
                .textContentType(.name)

            TextField("Commentaire (facultatif)", text: Bindable(model).comment, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
