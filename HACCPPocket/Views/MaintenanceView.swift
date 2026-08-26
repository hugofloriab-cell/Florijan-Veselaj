//
//  MaintenanceView.swift
//  HACCPPocket
//
//  Carnet d'entretien et étalonnage des sondes.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct MaintenanceListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \EquipmentMaintenance.occurredAt, order: .reverse)
    private var records: [EquipmentMaintenance]

    @State private var isCreating = false
    @State private var editedRecord: EquipmentMaintenance?
    @State private var showsPaywall = false

    private var attention: [EquipmentMaintenance] { records.filter(\.needsAction) }
    private var settled: [EquipmentMaintenance] { records.filter { !$0.needsAction } }

    /// Dernier étalonnage enregistré, tous appareils confondus.
    private var lastCalibration: EquipmentMaintenance? {
        records.first { $0.kind.isCalibration }
    }

    private var calibrationIsStale: Bool {
        guard let lastCalibration else { return true }
        let days = Calendar.current.dateComponents(
            [.day],
            from: lastCalibration.occurredAt,
            to: .now
        ).day ?? 0
        return days > 45
    }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .temperatureReading) }

            if calibrationIsStale {
                Section {
                    Label(
                        lastCalibration == nil
                            ? "Aucun étalonnage de sonde enregistré. Une sonde qui ment rend faux tout le registre de températures."
                            : "Dernier étalonnage il y a plus de six semaines. Le test du verre de glace prend trois minutes.",
                        systemImage: "thermometer.variable"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Carnet vide", systemImage: "wrench.and.screwdriver")
                    } description: {
                        Text("Pannes, entretiens, réparations et étalonnages. C'est ce carnet qui démontre qu'une enceinte tombée en panne a bien été réparée, et quand.")
                    } actions: {
                        Button("Ajouter une intervention") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section("À traiter") {
                    ForEach(attention) { record in row(record) }
                }
            }

            if !settled.isEmpty {
                Section("Historique") {
                    ForEach(settled) { record in row(record) }
                }
            }
        }
        .navigationTitle("Carnet d'entretien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Ajouter une intervention", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            MaintenanceEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            MaintenanceEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ record: EquipmentMaintenance) -> some View {
        Button {
            editedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: record.kind.systemImage, tint: tint(for: record))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(record.kind.label) · \(AppFormatters.shortDate(record.occurredAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if record.kind.isCalibration, let deviation = record.deviation {
                        Text("Écart mesuré : \(AppFormatters.deviation(deviation))")
                            .font(.caption)
                            .foregroundStyle(record.isCalibrationAcceptable == true ? Color.green : Color.red)
                    } else if !record.observation.isEmpty {
                        Text(record.observation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(text: record.statusLabel, color: tint(for: record))
                    if record.hasDocument {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(record) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func tint(for record: EquipmentMaintenance) -> Color {
        if !record.isResolved || record.isOverdue() { return .red }
        if record.kind.isCalibration && record.isCalibrationAcceptable == false { return .red }
        if record.needsAction { return .orange }
        return .green
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ record: EquipmentMaintenance) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct MaintenanceEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let record: EquipmentMaintenance?
    private let context: ModelContext

    @State private var equipmentName: String
    @State private var kind: MaintenanceKind
    @State private var occurredAt: Date
    @State private var provider: String
    @State private var observation: String
    @State private var actionTaken: String
    @State private var calibrationReference: String
    @State private var expectedText: String
    @State private var measuredText: String
    @State private var hasNextDue: Bool
    @State private var nextDueDate: Date
    @State private var isResolved: Bool
    @State private var operatorName: String
    @State private var notes: String
    @State private var documentData: Data?
    @State private var documentItem: PhotosPickerItem?

    init(record: EquipmentMaintenance?, context: ModelContext) {
        self.record = record
        self.context = context

        _equipmentName = State(initialValue: record?.equipmentName ?? "")
        _kind = State(initialValue: record?.kind ?? .calibration)
        _occurredAt = State(initialValue: record?.occurredAt ?? .now)
        _provider = State(initialValue: record?.provider ?? "")
        _observation = State(initialValue: record?.observation ?? "")
        _actionTaken = State(initialValue: record?.actionTaken ?? "")
        _calibrationReference = State(initialValue: record?.calibrationReference ?? "Eau glacée fondante")
        _expectedText = State(initialValue: MaintenanceEditorView.format(record?.expectedValue ?? 0))
        _measuredText = State(initialValue: record?.measuredValue.map { MaintenanceEditorView.format($0) } ?? "")
        _hasNextDue = State(initialValue: record?.nextDueDate != nil)
        _nextDueDate = State(
            initialValue: record?.nextDueDate
                ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)
                ?? .now
        )
        _isResolved = State(initialValue: record?.isResolved ?? true)
        _operatorName = State(initialValue: record?.operatorName ?? "")
        _notes = State(initialValue: record?.notes ?? "")
        _documentData = State(initialValue: record?.documentData)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(AppFormatters.locale))
    }

    private var expectedValue: Double? { AppFormatters.parseTemperature(expectedText) }
    private var measuredValue: Double? { AppFormatters.parseTemperature(measuredText) }

    private var deviation: Double? {
        guard let expectedValue, let measuredValue else { return nil }
        return measuredValue - expectedValue
    }

    private var isAcceptable: Bool? {
        guard let deviation else { return nil }
        return abs(deviation) <= EquipmentMaintenance.acceptableDeviation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Intervention") {
                    TextField("Matériel (sonde, frigo, lave-vaisselle…)", text: $equipmentName)

                    Picker("Nature", selection: $kind) {
                        ForEach(MaintenanceKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }

                    DatePicker("Date", selection: $occurredAt, in: ...Date.now)
                    TextField("Prestataire ou « interne »", text: $provider)
                }

                if kind.isCalibration {
                    calibrationSection
                } else {
                    Section("Constat et suite") {
                        TextField("Ce qui a été constaté", text: $observation, axis: .vertical)
                            .lineLimit(1...4)
                        TextField("Ce qui a été fait", text: $actionTaken, axis: .vertical)
                            .lineLimit(1...4)
                        Toggle("Problème résolu", isOn: $isResolved)
                    }
                }

                Section {
                    Toggle("Prochaine échéance", isOn: $hasNextDue)
                    if hasNextDue {
                        DatePicker("À refaire le", selection: $nextDueDate, displayedComponents: .date)
                    }
                } footer: {
                    Text(kind.isCalibration
                         ? "Un contrôle mensuel de la sonde suffit pour un usage courant."
                         : "Contrat d'entretien, visite périodique, prochaine vérification.")
                }

                documentSection

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouvelle intervention" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(equipmentName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private var calibrationSection: some View {
        Section {
            TextField("Référence utilisée", text: $calibrationReference)

            HStack {
                Text("Valeur attendue")
                Spacer()
                TextField("0,0", text: $expectedText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 90)
                Text("°C").foregroundStyle(.secondary)
            }

            HStack {
                Text("Valeur lue")
                Spacer()
                TextField("0,0", text: $measuredText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 90)
                Text("°C").foregroundStyle(.secondary)
            }

            if let deviation, let isAcceptable {
                HStack(spacing: 10) {
                    Image(systemName: isAcceptable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isAcceptable ? Color.green : Color.red)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Écart : \(AppFormatters.deviation(deviation))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isAcceptable ? Color.green : Color.red)
                        Text(isAcceptable
                             ? "Sonde utilisable."
                             : "Au-delà d'un demi-degré, la sonde fausse les décisions prises avec elle. Réglez-la ou remplacez-la.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            TextField("Suite donnée (réglage, remplacement…)", text: $actionTaken, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Étalonnage")
        } footer: {
            Text("Le test du verre de glace : plongez la sonde dans un mélange d'eau et de glace fondante, remué. Il est à 0 °C, toujours, quelle que soit la pièce.")
        }
    }

    @ViewBuilder
    private var documentSection: some View {
        Section {
            #if canImport(UIKit)
            if let documentData, let image = UIImage(data: documentData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.documentData = nil
                } label: {
                    Label("Retirer le document", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $documentItem, matching: .images) {
                Label(
                    documentData == nil ? "Joindre le rapport ou la facture" : "Remplacer le document",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Pièce jointe")
        }
        .onChange(of: documentItem) { _, item in
            Task { await loadDocument(item) }
        }
    }

    private func loadDocument(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            documentData = data
        }
    }

    private func save() {
        let target = record ?? EquipmentMaintenance()

        target.equipmentName = equipmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind
        target.occurredAt = occurredAt
        target.provider = provider
        target.observation = observation
        target.actionTaken = actionTaken
        target.calibrationReference = kind.isCalibration ? calibrationReference : ""
        target.expectedValue = kind.isCalibration ? expectedValue : nil
        target.measuredValue = kind.isCalibration ? measuredValue : nil
        target.nextDueDate = hasNextDue ? nextDueDate : nil
        target.isResolved = kind.isCalibration ? true : isResolved
        target.documentData = documentData
        target.operatorName = operatorName
        target.notes = notes

        if record == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
