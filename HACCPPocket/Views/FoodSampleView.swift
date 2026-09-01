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
                    Text("L'icône d'imprimante à droite de chaque ligne édite l'étiquette : nom du plat, date d'élimination possible, service et opérateur. Sept formats sont proposés, du petit rouleau thermique à la planche A4.")
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

    /// Bouton d'impression, sur la ligne elle-même.
    ///
    /// Même raisonnement que pour les produits entamés : l'étiquette se colle
    /// sur le bac au moment du prélèvement. Le glissement et l'appui long
    /// restent disponibles, mais aucun des deux ne se découvre tout seul.
    private func printButton(for sample: FoodSample) -> some View {
        Button {
            labelSample = sample
        } label: {
            Image(systemName: "printer")
                .font(.body)
                .foregroundStyle(Color.brand)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Imprimer l'étiquette de \(sample.displayName)")
    }

    private func row(_ sample: FoodSample) -> some View {
        // Deux boutons voisins : dans une liste, un bouton placé à
        // l'intérieur du libellé d'un autre ne reçoit pas ses propres appuis.
        HStack(spacing: 0) {
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

            printButton(for: sample)
        }
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
    @State private var createdSample: FoodSample?
    @State private var savedForPrinting: FoodSample?
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

                Section {
                    TextField("Nom du plat", text: $dishName)
                    TextField("Service (midi, soir, banquet…)", text: $serviceLabel)
                    Stepper("Quantité : \(quantityGrams) g", value: $quantityGrams, in: 50...300, step: 10)

                    // Le nombre de couverts se tape.
                    //
                    // Il avançait de dix en dix : 22 couverts — un service
                    // parfaitement ordinaire — étaient tout simplement
                    // impossibles à saisir. Le pas passe à un, et surtout le
                    // champ accepte la frappe directe : personne n'appuie
                    // vingt-deux fois sur un bouton.
                    HStack {
                        Text("Couverts servis")
                        Spacer(minLength: 8)

                        TextField("0", value: $coverCount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)

                        Stepper("", value: $coverCount, in: 0...2000)
                            .labelsHidden()
                    }
                } header: {
                    Text("Plat prélevé")
                } footer: {
                    Text("Le nombre de couverts n'est pas obligatoire, mais il permet de mesurer l'ampleur d'un cas si plusieurs convives se déclarent malades.")
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

                Section {
                    Button {
                        savedForPrinting = save()
                    } label: {
                        Label("Enregistrer et imprimer l'étiquette", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(dishName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("L'étiquette porte le nom du plat et la date d'élimination possible en gros — au fond d'un frigo, la seule question utile est « est-ce que je peux le jeter ? ».")
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
                    Button("Enregistrer") {
                        save()
                        dismiss()
                    }
                    .disabled(dishName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
            // La fiche se referme derrière l'écran d'impression : le geste
            // est « je prélève, j'imprime, je colle ».
            .sheet(item: $savedForPrinting, onDismiss: { dismiss() }) { sample in
                LabelPrintView(sample: sample)
            }
        }
    }

    @discardableResult
    private func save() -> FoodSample {
        // `createdSample` évite qu'un second appel — enregistrer puis
        // imprimer — crée un deuxième prélèvement au lieu de compléter le
        // premier.
        let target = sample ?? createdSample ?? FoodSample()

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

        if sample == nil, createdSample == nil {
            context.insert(target)
            createdSample = target
        }

        try? context.save()
        return target
    }
}
