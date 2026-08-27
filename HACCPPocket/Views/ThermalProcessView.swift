//
//  ThermalProcessView.swift
//  HACCPPocket
//
//  Refroidissement rapide et remise en température : une opération se lance,
//  se suit au chronomètre, et se clôture par un relevé final.
//

import SwiftUI
import SwiftData

// MARK: - Liste

struct ThermalProcessListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(UserPreferences.self) private var preferences

    @Query(sort: \ThermalProcessRecord.startedAt, order: .reverse)
    private var records: [ThermalProcessRecord]

    @State private var creationKind: ThermalProcessKind?
    @State private var finishTarget: ThermalProcessRecord?
    @State private var showsPaywall = false
    @State private var recordPendingDeletion: ThermalProcessRecord?

    private var running: [ThermalProcessRecord] { records.filter { !$0.isFinished } }
    private var finished: [ThermalProcessRecord] { records.filter(\.isFinished) }

    var body: some View {
        List {
            if !running.isEmpty {
                Section("En cours") {
                    ForEach(running) { record in
                        Button {
                            finishTarget = record
                        } label: {
                            runningRow(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Historique") {
                if finished.isEmpty {
                    Text("Aucune opération enregistrée.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(finished) { record in
                        finishedRow(record)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    recordPendingDeletion = record
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Températures process")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ThermalProcessKind.allCases) { kind in
                        Button {
                            start(kind)
                        } label: {
                            Label(kind.label, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Label("Nouvelle opération", systemImage: "plus")
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Aucune opération", systemImage: "thermometer.variable")
                } description: {
                    Text("Enregistrez ici vos refroidissements rapides, vos congélations et vos remises en température.")
                }
            }
        }
        .sheet(item: $creationKind) { kind in
            ThermalProcessFormView(kind: kind, context: modelContext)
        }
        .sheet(item: $finishTarget) { record in
            ThermalProcessFinishView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .confirmationDialog(
            "Supprimer cette opération ?",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { if !$0 { recordPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let record = recordPendingDeletion {
                    modelContext.delete(record)
                    try? modelContext.save()
                }
                recordPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { recordPendingDeletion = nil }
        } message: {
            Text("À réserver à une saisie erronée : une opération réelle doit rester au registre.")
        }
    }

    // MARK: Lignes

    /// Le chronomètre se rafraîchit chaque seconde : c'est l'information utile
    /// pendant l'opération, bien plus que la température de départ.
    private func runningRow(_ record: ThermalProcessRecord) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = record.remainingTime(at: context.date)
            let overdue = remaining < 0

            HStack(spacing: 12) {
                RowIcon(
                    systemImage: record.kind.systemImage,
                    tint: overdue ? .red : .brand
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.productName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(record.kind.shortLabel) · départ \(AppFormatters.temperature(record.startTemperature))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: record.timeProgress(at: context.date))
                        .tint(overdue ? Color.red : Color.brand)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.formattedDuration(at: context.date))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? Color.red : Color.primary)
                    Text(overdue ? "Limite dépassée" : "Clôturer")
                        .font(.caption2)
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func finishedRow(_ record: ThermalProcessRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: record.kind.systemImage,
                tint: record.isCompliant ? .green : .red
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.productName)
                    .font(.subheadline.weight(.semibold))

                Text("\(record.kind.shortLabel) · \(record.formattedDuration())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(AppFormatters.dateAndTime(record.startedAt)) · \(AppFormatters.temperature(record.startTemperature)) → \(record.endTemperature.map { AppFormatters.temperature($0) } ?? "—")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let reason = record.failureReason {
                    Text(reason.prefix(1).uppercased() + reason.dropFirst())
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if record.needsCorrectiveAction {
                    Label("Action corrective manquante", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: record.isCompliant ? "Conforme" : "Non conforme",
                color: record.isCompliant ? .green : .red
            )
        }
        .padding(.vertical, 6)
    }

    private func start(_ kind: ThermalProcessKind) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        creationKind = kind
    }
}

// MARK: - Démarrage

struct ThermalProcessFormView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    let kind: ThermalProcessKind
    private let context: ModelContext

    /// Le mode opératoire correspondant à l'opération lancée.
    private var guide: OperationProtocol {
        switch kind {
        case .cooling:   return .rapidCooling
        case .freezing:  return .freezing
        case .reheating: return .reheating
        }
    }

    @State private var productName = ""
    @State private var batchNumber = ""
    @State private var temperatureText: String
    @State private var operatorName = ""
    @State private var startedAt = Date.now
    @State private var comment = ""

    init(kind: ThermalProcessKind, context: ModelContext) {
        self.kind = kind
        self.context = context
        _temperatureText = State(
            initialValue: kind.startTemperatureHint.formatted(
                .number.precision(.fractionLength(1)).locale(AppFormatters.locale)
            )
        )
    }

    private var temperature: Double? {
        AppFormatters.parseTemperature(temperatureText)
    }

    private var canSave: Bool {
        !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && temperature != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Produit (ex. Sauce bolognaise)", text: $productName)
                    TextField("Numéro de lot", text: $batchNumber)
                } header: {
                    Text("Produit")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.requirement)

                        // La congélation n'a pas de durée opposable : le dire
                        // ici évite de faire croire à une obligation que
                        // l'application aurait inventée.
                        if !kind.hasRegulatoryDuration {
                            Text("Le chronomètre est un repère de bonne pratique : aucun texte ne fixe de durée de congélation. Seule la température de −18 °C à cœur est exigée.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    ProtocolLink(procedure: guide)
                }

                Section("Départ") {
                    HStack {
                        Text("Température à cœur")
                        Spacer()
                        TextField("0,0", text: $temperatureText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 90)
                        Text("°C").foregroundStyle(.secondary)
                    }

                    DatePicker("Heure de départ", selection: $startedAt, in: ...Date.now)
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Démarrer") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private func save() {
        guard let temperature else { return }

        let record = ThermalProcessRecord(
            kind: kind,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            startTemperature: temperature,
            batchNumber: batchNumber,
            operatorName: operatorName,
            startedAt: startedAt,
            comment: comment
        )
        context.insert(record)
        try? context.save()
        dismiss()
    }
}

// MARK: - Clôture

struct ThermalProcessFinishView: View {

    @Environment(\.dismiss) private var dismiss

    let record: ThermalProcessRecord
    private let context: ModelContext

    @State private var temperatureText = ""
    @State private var checkpointText = ""
    @State private var correctiveAction: String
    @State private var finishedAt = Date.now

    init(record: ThermalProcessRecord, context: ModelContext) {
        self.record = record
        self.context = context
        _correctiveAction = State(initialValue: record.correctiveAction)
    }

    private var temperature: Double? {
        AppFormatters.parseTemperature(temperatureText)
    }

    /// Conformité prévisionnelle, affichée avant même de valider.
    private var wouldBeCompliant: Bool? {
        guard let temperature else { return nil }
        let elapsed = finishedAt.timeIntervalSince(record.startedAt)
        return record.reachesTarget(temperature) && elapsed <= record.maximumDurationSeconds
    }

    private var requiresCorrectiveAction: Bool {
        wouldBeCompliant == false
    }

    private var canSave: Bool {
        guard temperature != nil else { return false }
        if requiresCorrectiveAction {
            return !correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                checkpointsSection
                finishSection

                if requiresCorrectiveAction {
                    Section {
                        TextField(
                            "Ex. produit jeté, cellule redémarrée, lot déclassé",
                            text: $correctiveAction,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    } header: {
                        Label("Action corrective", systemImage: "wrench.and.screwdriver")
                    } footer: {
                        Text("Obligatoire : une opération non conforme sans suite documentée rend le registre incomplet.")
                    }
                }
            }
            .navigationTitle("Clôturer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { finish() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            InfoRow(label: "Produit", value: record.productName, systemImage: "shippingbox")
            InfoRow(
                label: "Départ",
                value: "\(AppFormatters.temperature(record.startTemperature)) à \(AppFormatters.time(record.startedAt))",
                systemImage: "play.circle"
            )
            InfoRow(
                label: "Objectif",
                value: AppFormatters.temperature(record.targetTemperature),
                systemImage: "target"
            )

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let overdue = record.isOverdue(at: context.date)
                HStack {
                    RowIcon(systemImage: "timer", tint: overdue ? .red : .brand, size: 26)
                    Text("Temps écoulé")
                    Spacer()
                    Text(record.formattedDuration(at: context.date))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? Color.red : Color.primary)
                }
            }
        } footer: {
            Text(record.kind.requirement)
        }
    }

    private var checkpointsSection: some View {
        Section {
            ForEach(record.sortedCheckpoints) { checkpoint in
                HStack {
                    Text(AppFormatters.time(checkpoint.recordedAt))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(AppFormatters.temperature(checkpoint.temperature))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }

            HStack {
                TextField("Relevé intermédiaire", text: $checkpointText)
                    .keyboardType(.numbersAndPunctuation)
                Button("Ajouter") { addCheckpoint() }
                    .disabled(AppFormatters.parseTemperature(checkpointText) == nil)
            }
        } header: {
            Text("Relevés intermédiaires")
        } footer: {
            Text("Facultatifs, mais ils montrent que la descente a été surveillée et non simplement constatée à la fin.")
        }
    }

    private var finishSection: some View {
        Section {
            HStack {
                Text("Température finale")
                Spacer()
                TextField("0,0", text: $temperatureText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 90)
                Text("°C").foregroundStyle(.secondary)
            }

            DatePicker("Heure de fin", selection: $finishedAt, in: record.startedAt...Date.now)

            if let compliant = wouldBeCompliant {
                Label(
                    compliant ? "Opération conforme" : "Opération non conforme",
                    systemImage: compliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(compliant ? Color.green : Color.red)
            }
        } header: {
            Text("Arrivée")
        }
    }

    private func addCheckpoint() {
        guard let value = AppFormatters.parseTemperature(checkpointText) else { return }
        let checkpoint = ThermalCheckpoint(temperature: value, record: record)
        context.insert(checkpoint)
        try? context.save()
        checkpointText = ""
    }

    private func finish() {
        guard let temperature else { return }
        record.correctiveAction = correctiveAction
        record.finish(at: finishedAt, temperature: temperature)
        try? context.save()
        dismiss()
    }
}
