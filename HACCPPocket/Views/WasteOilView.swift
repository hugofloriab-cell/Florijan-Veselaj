//
//  WasteOilView.swift
//  HACCPPocket
//
//  Bordereaux de collecte des huiles usagées.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct WasteOilListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \WasteOilCollection.collectedAt, order: .reverse)
    private var collections: [WasteOilCollection]

    @Query private var oilChecks: [OilCheckRecord]

    @State private var isCreating = false
    @State private var editedCollection: WasteOilCollection?
    @State private var showsPaywall = false

    private var incomplete: [WasteOilCollection] { collections.filter(\.isIncomplete) }

    /// Bains changés depuis le dernier enlèvement. Une friteuse vidangée
    /// souvent sans aucune collecte pose une question visible de loin.
    private var changesSinceLastCollection: Int {
        guard let last = collections.first?.collectedAt else {
            return oilChecks.filter { $0.action == .changed }.count
        }
        return oilChecks.filter { $0.action == .changed && $0.checkedAt > last }.count
    }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .wasteOil) }

            if changesSinceLastCollection >= 4 {
                Section {
                    Label(
                        "\(changesSinceLastCollection) changements de bain depuis le dernier enlèvement enregistré. Si l'huile part autrement, le registre des déchets ne le montre pas.",
                        systemImage: "arrow.3.trianglepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if collections.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun enlèvement", systemImage: "arrow.3.trianglepath")
                    } description: {
                        Text("Une huile de friture usagée est un déchet : elle se fait enlever par un collecteur, et chaque enlèvement laisse un bordereau à conserver au moins trois ans.")
                    } actions: {
                        Button("Enregistrer un enlèvement") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !incomplete.isEmpty {
                Section {
                    ForEach(incomplete) { collection in row(collection) }
                } header: {
                    Text("Bordereaux manquants")
                } footer: {
                    Text("Sans document, vous restez responsable du devenir du déchet.")
                }
            }

            let complete = collections.filter { !$0.isIncomplete }
            if !complete.isEmpty {
                Section("Enlèvements") {
                    ForEach(complete) { collection in row(collection) }
                }
            }
        }
        .navigationTitle("Huiles usagées")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un enlèvement", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            WasteOilEditorView(collection: nil, context: modelContext)
        }
        .sheet(item: $editedCollection) { collection in
            WasteOilEditorView(collection: collection, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ collection: WasteOilCollection) -> some View {
        Button {
            editedCollection = collection
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: "arrow.3.trianglepath",
                    tint: collection.isIncomplete ? .orange : .brand
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(AppFormatters.shortDate(collection.collectedAt)) · \(collection.formattedQuantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !collection.documentReference.isEmpty {
                        Text("Bordereau \(collection.documentReference)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                if collection.hasDocument {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    StatusBadge(text: collection.statusLabel, color: .orange)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(collection) } label: {
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

    private func delete(_ collection: WasteOilCollection) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(collection)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct WasteOilEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let collection: WasteOilCollection?
    private let context: ModelContext

    @State private var collectedAt: Date
    @State private var collector: String
    @State private var collectorApproval: String
    @State private var documentReference: String
    @State private var quantityText: String
    @State private var unit: WasteOilUnit
    @State private var containerCount: Int
    @State private var operatorName: String
    @State private var notes: String
    @State private var documentData: Data?
    @State private var documentItem: PhotosPickerItem?

    init(collection: WasteOilCollection?, context: ModelContext) {
        self.collection = collection
        self.context = context

        _collectedAt = State(initialValue: collection?.collectedAt ?? .now)
        _collector = State(initialValue: collection?.collector ?? "")
        _collectorApproval = State(initialValue: collection?.collectorApproval ?? "")
        _documentReference = State(initialValue: collection?.documentReference ?? "")
        _quantityText = State(
            initialValue: collection.map {
                $0.quantity.formatted(.number.precision(.fractionLength(0...1)).locale(AppFormatters.locale))
            } ?? ""
        )
        _unit = State(initialValue: collection?.unit ?? .litres)
        _containerCount = State(initialValue: collection?.containerCount ?? 0)
        _operatorName = State(initialValue: collection?.operatorName ?? "")
        _notes = State(initialValue: collection?.notes ?? "")
        _documentData = State(initialValue: collection?.documentData)
    }

    private var quantity: Double {
        AppFormatters.parseTemperature(quantityText) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .wasteOil) }

                Section("Enlèvement") {
                    DatePicker("Date", selection: $collectedAt, in: ...Date.now)
                    TextField("Société de collecte", text: $collector)
                    TextField("Numéro d'agrément du collecteur", text: $collectorApproval)
                    TextField("Numéro de bordereau", text: $documentReference)
                }

                Section("Quantité") {
                    HStack {
                        Text("Quantité reprise")
                        Spacer()
                        TextField("0", text: $quantityText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 90)
                        Picker("", selection: $unit) {
                            ForEach(WasteOilUnit.allCases) { unit in
                                Text(unit.shortLabel).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }

                    Stepper(
                        containerCount > 0 ? "Contenants : \(containerCount)" : "Contenants : non précisé",
                        value: $containerCount,
                        in: 0...50
                    )
                }

                documentSection

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(collection == nil ? "Nouvel enlèvement" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(collector.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
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
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.documentData = nil
                } label: {
                    Label("Retirer le bordereau", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $documentItem, matching: .images) {
                Label(
                    documentData == nil ? "Photographier le bordereau" : "Remplacer le bordereau",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Bordereau signé")
        } footer: {
            Text("À conserver au moins \(WasteOilCollection.retentionYears) ans : c'est la suite de ces bons qui constitue votre registre des déchets.")
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
        let target = collection ?? WasteOilCollection()

        target.collectedAt = collectedAt
        target.collector = collector.trimmingCharacters(in: .whitespacesAndNewlines)
        target.collectorApproval = collectorApproval
        target.documentReference = documentReference
        target.quantity = quantity
        target.unit = unit
        target.containerCount = containerCount
        target.documentData = documentData
        target.operatorName = operatorName
        target.notes = notes

        if collection == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
