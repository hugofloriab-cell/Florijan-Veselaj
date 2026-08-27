//
//  FoodSampleView.swift
//  HACCPPocket
//
//  Registre des plats témoins.
//

import SwiftUI
import SwiftData

struct FoodSampleListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \FoodSample.collectedAt, order: .reverse)
    private var samples: [FoodSample]

    @State private var isCreating = false
    @State private var editedSample: FoodSample?
    @State private var showsPaywall = false
    @State private var labelSample: FoodSample?

    private var stored: [FoodSample] { samples.filter { !$0.isDiscarded } }
    private var toDiscard: [FoodSample] { stored.filter(\.needsAction) }
    private var keeping: [FoodSample] { stored.filter { !$0.needsAction } }
    private var discarded: [FoodSample] { samples.filter(\.isDiscarded) }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .foodSample) }

            if samples.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun plat témoin", systemImage: "takeoutbag.and.cup.and.straw")
                    } description: {
                        Text("Un plat témoin ne sert à rien tant que tout va bien. Le jour où un convive se déclare malade, c'est la seule pièce qui permette de démontrer que votre plat était conforme.")
                    } actions: {
                        Button("Enregistrer un prélèvement") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !toDiscard.isEmpty {
                Section {
                    ForEach(toDiscard) { sample in
                        row(sample)
                    }
                } header: {
                    Text("À éliminer")
                } footer: {
                    Text("Le délai de conservation est écoulé : ces échantillons ne prouvent plus rien et prennent la place des suivants.")
                }
            }

            if !keeping.isEmpty {
                Section {
                    ForEach(keeping) { sample in
                        row(sample)
                    }
                } header: {
                    Text("En conservation")
                } footer: {
                    Text("Appui long sur un prélèvement pour imprimer son étiquette : nom du plat, date d'élimination possible, service et opérateur. Cinq formats sont proposés, du petit rouleau thermique à la planche A4.")
                }
            }

            if !discarded.isEmpty {
                Section("Éliminés") {
                    ForEach(discarded) { sample in
                        row(sample)
                    }
                }
            }
        }
        .navigationTitle("Plats témoins")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un prélèvement", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            FoodSampleEditorView(sample: nil, context: modelContext)
        }
        .sheet(item: $editedSample) { sample in
            FoodSampleEditorView(sample: sample, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .sheet(item: $labelSample) { sample in
            LabelPrintView(sample: sample)
        }
    }

    private func row(_ sample: FoodSample) -> some View {
        Button {
            editedSample = sample
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: "takeoutbag.and.cup.and.straw",
                    tint: sample.isDiscarded ? .secondary : (sample.needsAction ? .orange : .brand)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(sample.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(sample.isDiscarded ? Color.secondary : Color.primary)

                    Text(subtitle(for: sample))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !sample.isDiscarded {
                        Text("Élimination possible le \(AppFormatters.shortDate(sample.disposalDate()))")
                            .font(.caption)
                            .foregroundStyle(sample.needsAction ? Color.orange : Color.secondary)
                    }
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: sample.statusLabel,
                    color: sample.isDiscarded ? .secondary : (sample.needsAction ? .orange : .green)
                )
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(sample) } label: {
                Label("Supprimer", systemImage: "trash")
            }

            if !sample.isDiscarded {
                Button { markDiscarded(sample) } label: {
                    Label("Éliminé", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { labelSample = sample } label: {
                Label("Étiquette", systemImage: "printer")
            }
            .tint(.indigo)
        }
        // Le glissement ne se découvre pas tout seul : l'appui long propose
        // la même action, et c'est le geste que les gens essaient.
        .contextMenu {
            Button {
                labelSample = sample
            } label: {
                Label("Imprimer l'étiquette", systemImage: "printer")
            }
        }
    }

    private func subtitle(for sample: FoodSample) -> String {
        var parts = [AppFormatters.dateAndTime(sample.collectedAt)]
        if !sample.serviceLabel.isEmpty { parts.append(sample.serviceLabel) }
        parts.append("\(sample.quantityGrams) g")
        return parts.joined(separator: " · ")
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func markDiscarded(_ sample: FoodSample) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        sample.discardedAt = .now
        try? modelContext.save()
    }

    private func delete(_ sample: FoodSample) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(sample)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct FoodSampleEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let sample: FoodSample?
    private let context: ModelContext

    @State private var dishName: String
    @State private var serviceLabel: String
    @State private var collectedAt: Date
    @State private var lastServedAt: Date
    @State private var quantityGrams: Int
    @State private var coverCount: Int
    @State private var storageLocation: String
    @State private var operatorName: String
    @State private var comment: String
    @State private var isDiscarded: Bool
    @State private var discardedAt: Date

    init(sample: FoodSample?, context: ModelContext) {
        self.sample = sample
        self.context = context

        _dishName = State(initialValue: sample?.dishName ?? "")
        _serviceLabel = State(initialValue: sample?.serviceLabel ?? "")
        _collectedAt = State(initialValue: sample?.collectedAt ?? .now)
        _lastServedAt = State(initialValue: sample?.lastServedAt ?? .now)
        _quantityGrams = State(initialValue: sample?.quantityGrams ?? 100)
        _coverCount = State(initialValue: sample?.coverCount ?? 0)
        _storageLocation = State(initialValue: sample?.storageLocation ?? "")
        _operatorName = State(initialValue: sample?.operatorName ?? "")
        _comment = State(initialValue: sample?.comment ?? "")
        _isDiscarded = State(initialValue: sample?.isDiscarded ?? false)
        _discardedAt = State(initialValue: sample?.discardedAt ?? .now)
    }

    private var disposalDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: FoodSample.retentionDays,
            to: lastServedAt
        ) ?? lastServedAt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .foodSample) }

                Section("Plat prélevé") {
                    TextField("Nom du plat", text: $dishName)
                    TextField("Service (midi, soir, banquet…)", text: $serviceLabel)
                    Stepper("Quantité : \(quantityGrams) g", value: $quantityGrams, in: 50...300, step: 10)
                    Stepper(
                        coverCount > 0 ? "Couverts servis : \(coverCount)" : "Couverts servis : non précisé",
                        value: $coverCount,
                        in: 0...2000,
                        step: 10
                    )
                }

                Section {
                    DatePicker("Prélevé le", selection: $collectedAt, in: ...Date.now)
                    DatePicker("Dernier service", selection: $lastServedAt, in: ...Date.now)

                    HStack {
                        Text("Élimination possible le")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(AppFormatters.shortDate(disposalDate))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.brand)
                    }
                } header: {
                    Text("Conservation")
                } footer: {
                    Text("Le délai de \(FoodSample.retentionDays) jours court à partir de la dernière présentation au consommateur, pas de la fabrication du plat.")
                }

                Section("Stockage") {
                    TextField("Emplacement (+0/+3 °C)", text: $storageLocation)
                }

                Section {
                    Toggle("Échantillon éliminé", isOn: $isDiscarded)
                    if isDiscarded {
                        DatePicker("Éliminé le", selection: $discardedAt, in: ...Date.now)
                    }
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(sample == nil ? "Nouveau prélèvement" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(dishName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private func save() {
        let target = sample ?? FoodSample()

        target.dishName = dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.serviceLabel = serviceLabel
        target.collectedAt = collectedAt
        target.lastServedAt = lastServedAt
        target.quantityGrams = quantityGrams
        target.coverCount = coverCount
        target.storageLocation = storageLocation
        target.operatorName = operatorName
        target.comment = comment
        target.discardedAt = isDiscarded ? discardedAt : nil

        if sample == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
