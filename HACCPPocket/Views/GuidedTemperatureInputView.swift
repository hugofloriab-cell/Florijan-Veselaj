//
//  GuidedTemperatureInputView.swift
//  HACCPPocket
//
//  Saisie guidée d'un relevé de température.
//
//  Contexte d'usage : debout devant une chambre froide, une sonde dans une
//  main, souvent des gants, parfois à 23 h. Tout part de là — le pavé
//  numérique plutôt que le clavier système, les cibles larges, la couleur qui
//  tranche avant même qu'on lise, et une seule décision par écran.
//
//  Trois étapes : on saisit, on corrige si besoin, on valide.
//

import SwiftUI
import SwiftData

struct GuidedTemperatureInputView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TemperatureLogViewModel
    @State private var stage: Stage = .entry
    @State private var conclusion: CorrectiveConclusion?
    @State private var showsDeleteConfirmation = false

    private enum Stage {
        case entry
        case correctiveAction
        case confirmation
    }

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

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:            entryStage
                case .correctiveAction: correctiveStage
                case .confirmation:     confirmationStage
                }
            }
            .navigationTitle(viewModel.equipment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .entry ? "Annuler" : "Retour") { goBack() }
                }
            }
        }
    }

    private func goBack() {
        switch stage {
        case .entry:
            dismiss()
        case .correctiveAction:
            stage = .entry
        case .confirmation:
            stage = viewModel.requiresCorrectiveAction ? .correctiveAction : .entry
        }
    }

    // MARK: - Étape 1 : la saisie

    private var entryStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.gutter) {
                    targetCard
                    valueDisplay
                    verdictCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .readableWidth()
            }

            NumericKeypad(
                text: Bindable(viewModel).valueText,
                allowsNegative: true
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            continueButton
                .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// La cible, en grand et avant tout le reste : c'est l'information que
    /// l'utilisateur est venu chercher, et celle qu'il n'a pas à connaître
    /// par cœur.
    private var targetCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.equipment.type.systemImage)
                    .foregroundStyle(.brand)
                Text(viewModel.equipment.type.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if let standard = matchingStandard {
                    RegulatoryBadge(note: standard.note)
                }

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Cible")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.equipment.formattedRange)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.brand)
                Spacer()
            }
        }
        .padding(14)
        .cardSurface()
    }

    /// La norme du référentiel dont la plage correspond à celle de l'enceinte.
    /// Sert uniquement à proposer l'explication : elle n'impose rien.
    private var matchingStandard: ColdChainStandard? {
        let range = viewModel.equipment.acceptedRange
        return ColdChainStandard.allCases.first {
            $0.range.lowerBound == range.lowerBound && $0.range.upperBound == range.upperBound
        }
    }

    private var valueDisplay: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.valueText.isEmpty ? "—" : viewModel.valueText)
                    .font(.system(size: 68, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(displayColor)
                Text("°C")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: viewModel.valueText)

            if let deviation = viewModel.deviation, deviation != 0 {
                Text("\(AppFormatters.deviation(deviation)) hors de la plage")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var displayColor: Color {
        guard let verdict = viewModel.verdict else { return .primary }
        return color(for: verdict)
    }

    private func color(for verdict: ReadingVerdict) -> Color {
        switch verdict {
        case .compliant:  .green
        case .borderline: .orange
        case .outOfRange: .red
        }
    }

    @ViewBuilder
    private var verdictCard: some View {
        if let verdict = viewModel.verdict {
            let tint = color(for: verdict)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: verdict.systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(verdict.advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                tint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
            .transition(.opacity)
        }
    }

    private var continueButton: some View {
        Button {
            advanceFromEntry()
        } label: {
            Label(
                viewModel.requiresCorrectiveAction ? "Traiter l'écart" : "Continuer",
                systemImage: viewModel.requiresCorrectiveAction ? "wrench.and.screwdriver.fill" : "arrow.right"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.requiresCorrectiveAction ? .red : .brand)
        .disabled(viewModel.value == nil)
    }

    private func advanceFromEntry() {
        if viewModel.requiresCorrectiveAction {
            conclusion = nil
            viewModel.correctiveAction = ""
            stage = .correctiveAction
        } else {
            stage = .confirmation
        }
    }

    // MARK: - Étape 2 : l'action corrective

    private var correctiveStage: some View {
        CorrectiveActionFlowView(
            equipment: viewModel.equipment,
            measured: viewModel.value ?? 0
        ) { reached in
            conclusion = reached
            viewModel.correctiveAction = reached.recordedAction
            stage = .confirmation
        }
    }

    // MARK: - Étape 3 : la validation

    private var confirmationStage: some View {
        Form {
            summarySection

            if let conclusion {
                conclusionSection(conclusion)
            }

            detailsSection

            if viewModel.isEditing {
                Section {
                    Button("Supprimer ce relevé", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            }

            Section {
                Button {
                    if viewModel.save() { dismiss() }
                } label: {
                    Label("Enregistrer au registre", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(!viewModel.canSave)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text(viewModel.equipment.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(viewModel.valueText) °C")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(displayColor)
            }
            .padding(.vertical, 2)

            LabeledContent("Plage attendue", value: viewModel.equipment.formattedRange)

            ProtocolLink(procedure: .temperatureReading)
        } header: {
            Text("Relevé")
        }
    }

    private func conclusionSection(_ conclusion: CorrectiveConclusion) -> some View {
        Section {
            Text(conclusion.recordedAction)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "Précision à ajouter (facultatif)",
                text: Bindable(viewModel).correctiveAction,
                axis: .vertical
            )
            .lineLimit(2...6)
        } header: {
            Label("Action corrective", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("Ce texte part au registre. Vous pouvez le compléter, mais pas le vider : un écart sans action corrective rend le registre incomplet.")
        }
    }

    private var detailsSection: some View {
        Section("Détails") {
            Picker("Moment", selection: Bindable(viewModel).moment) {
                ForEach(ReadingMoment.allCases) { moment in
                    Label(moment.label, systemImage: moment.systemImage).tag(moment)
                }
            }

            DatePicker(
                "Date et heure",
                selection: Bindable(viewModel).recordedAt,
                in: ...Date.now
            )

            OperatorField(name: Bindable(viewModel).operatorName)

            TextField("Commentaire (facultatif)", text: Bindable(viewModel).comment, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}
