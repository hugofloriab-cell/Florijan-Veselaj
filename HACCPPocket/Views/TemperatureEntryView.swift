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
            HStack(spacing: 12) {
                adjustButton(-0.5, systemImage: "minus")

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0,0", text: Bindable(viewModel).valueText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($isValueFocused)
                    Text("°C")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                adjustButton(0.5, systemImage: "plus")
            }
            .padding(.vertical, 10)

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

    /// Ajustement au demi-degré : en cuisine, on lit une sonde et on corrige
    /// d'un pouce, sans repasser par le clavier.
    private func adjustButton(_ delta: Double, systemImage: String) -> some View {
        Button {
            adjust(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.brand.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brand)
        .accessibilityLabel(delta > 0 ? "Augmenter d'un demi-degré" : "Diminuer d'un demi-degré")
    }

    private func adjust(by delta: Double) {
        let current = viewModel.value ?? 0
        let updated = ((current + delta) * 10).rounded() / 10
        viewModel.valueText = updated.formatted(
            .number.precision(.fractionLength(1)).locale(AppFormatters.locale)
        )
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let isCompliant = viewModel.isCompliant {
            HStack(spacing: 10) {
                Image(systemName: isCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isCompliant ? Color.green : Color.red)
                Text(isCompliant ? "Relevé conforme" : "Relevé hors plage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCompliant ? Color.green : Color.red)
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

            OperatorField(name: Bindable(model).operatorName)

            TextField("Commentaire (facultatif)", text: Bindable(model).comment, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
