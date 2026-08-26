//
//  ThawingView.swift
//  HACCPPocket
//
//  Registre de décongélation.
//

import SwiftUI
import SwiftData

struct ThawingListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \ThawingRecord.startedAt, order: .reverse)
    private var records: [ThawingRecord]

    @State private var isCreating = false
    @State private var editedRecord: ThawingRecord?
    @State private var showsPaywall = false

    private var running: [ThawingRecord] { records.filter { !$0.isFinished } }
    private var finished: [ThawingRecord] { records.filter(\.isFinished) }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .thawing) }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune décongélation", systemImage: "snowflake.slash")
                    } description: {
                        Text("Une pièce décongelée ne se conserve plus comme une pièce fraîche : sa DLC d'origine ne s'applique plus. C'est ce registre qui la remplace.")
                    } actions: {
                        Button("Enregistrer une décongélation") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !running.isEmpty {
                Section("En cours") {
                    ForEach(running) { record in
                        row(record)
                    }
                }
            }

            if !finished.isEmpty {
                Section("Terminées") {
                    ForEach(finished) { record in
                        row(record)
                    }
                }
            }
        }
        .navigationTitle("Décongélation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer une décongélation", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ThawingEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            ThawingEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ record: ThawingRecord) -> some View {
        Button {
            editedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: record.method.systemImage,
                    tint: record.isExpired() ? .red : (record.isFinished ? .green : .orange)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(record.method.label) · démarré le \(AppFormatters.shortDate(record.startedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.caption2)
                        Text("À retirer le \(AppFormatters.shortDate(record.residualLimitDate()))")
                            .font(.caption)
                    }
                    .foregroundStyle(record.isExpired() ? Color.red : Color.secondary)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: record.statusLabel,
                    color: record.isExpired() ? .red : (record.isFinished ? .green : .orange)
                )
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

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ record: ThawingRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct ThawingEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let record: ThawingRecord?
    private let context: ModelContext

    @State private var productName: String
    @State private var batchNumber: String
    @State private var location: String
    @State private var method: ThawingMethod
    @State private var startedAt: Date
    @State private var isFinished: Bool
    @State private var finishedAt: Date
    @State private var hasOriginalExpiry: Bool
    @State private var originalExpiryDate: Date
    @State private var shelfLifeDays: Int
    @State private var quantity: String
    @State private var operatorName: String
    @State private var comment: String

    init(record: ThawingRecord?, context: ModelContext) {
        self.record = record
        self.context = context

        _productName = State(initialValue: record?.productName ?? "")
        _batchNumber = State(initialValue: record?.batchNumber ?? "")
        _location = State(initialValue: record?.location ?? "")
        _method = State(initialValue: record?.method ?? .coldRoom)
        _startedAt = State(initialValue: record?.startedAt ?? .now)
        _isFinished = State(initialValue: record?.isFinished ?? false)
        _finishedAt = State(initialValue: record?.finishedAt ?? .now)
        _hasOriginalExpiry = State(initialValue: record?.originalExpiryDate != nil)
        _originalExpiryDate = State(initialValue: record?.originalExpiryDate ?? .now)
        _shelfLifeDays = State(initialValue: record?.shelfLifeDays ?? 1)
        _quantity = State(initialValue: record?.quantity ?? "")
        _operatorName = State(initialValue: record?.operatorName ?? "")
        _comment = State(initialValue: record?.comment ?? "")
    }

    /// Aperçu calculé en direct, avec les deux plafonds.
    private var previewLimit: Date {
        let reference = isFinished ? finishedAt : startedAt
        let computed = Calendar.current.date(byAdding: .day, value: shelfLifeDays, to: reference) ?? reference
        guard hasOriginalExpiry else { return computed }
        return min(computed, originalExpiryDate)
    }

    private var originalWins: Bool {
        guard hasOriginalExpiry else { return false }
        let reference = isFinished ? finishedAt : startedAt
        let computed = Calendar.current.date(byAdding: .day, value: shelfLifeDays, to: reference) ?? reference
        return originalExpiryDate < computed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .thawing) }

                Section("Produit") {
                    TextField("Désignation", text: $productName)
                    TextField("Numéro de lot", text: $batchNumber)
                    TextField("Quantité (facultatif)", text: $quantity)
                }

                Section {
                    Picker("Méthode", selection: $method) {
                        ForEach(ThawingMethod.allCases) { method in
                            Label(method.label, systemImage: method.systemImage).tag(method)
                        }
                    }

                    if method == .coldRoom {
                        TextField("Enceinte de décongélation", text: $location)
                    }
                } header: {
                    Text("Méthode")
                } footer: {
                    Text(method.requiresImmediateCooking
                         ? "\(method.detail)\n\nCette méthode impose une cuisson immédiate : le produit ne repart pas au froid."
                         : method.detail)
                }

                Section("Chronologie") {
                    DatePicker("Mise en décongélation", selection: $startedAt, in: ...Date.now)

                    Toggle("Décongélation terminée", isOn: $isFinished)

                    if isFinished {
                        DatePicker("Terminée le", selection: $finishedAt, in: startedAt...Date.now)
                    }
                }

                Section {
                    Stepper(
                        "Durée de vie après décongélation : \(shelfLifeDays) jour(s)",
                        value: $shelfLifeDays,
                        in: 0...7
                    )

                    Toggle("DLC d'origine connue", isOn: $hasOriginalExpiry)

                    if hasOriginalExpiry {
                        DatePicker(
                            "DLC du fournisseur",
                            selection: $originalExpiryDate,
                            displayedComponents: .date
                        )
                    }

                    HStack {
                        Text("À retirer le")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(AppFormatters.shortDate(previewLimit))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.brand)
                    }
                } header: {
                    Text("DLC résiduelle")
                } footer: {
                    if originalWins {
                        Label(
                            "La DLC du fournisseur est plus courte que la durée accordée : c'est elle qui s'applique. On ne gagne jamais de temps en décongelant.",
                            systemImage: "info.circle"
                        )
                    } else {
                        Text("Un produit décongelé ne retrouve jamais sa durée de vie d'origine. Vingt-quatre heures est l'usage pour une viande ou un poisson.")
                    }
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouvelle décongélation" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private func save() {
        let target = record ?? ThawingRecord()

        target.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.batchNumber = batchNumber
        target.location = location
        target.method = method
        target.startedAt = startedAt
        target.finishedAt = isFinished ? finishedAt : nil
        target.originalExpiryDate = hasOriginalExpiry ? originalExpiryDate : nil
        target.shelfLifeDays = shelfLifeDays
        target.quantity = quantity
        target.operatorName = operatorName
        target.comment = comment

        if record == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
