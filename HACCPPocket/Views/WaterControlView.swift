//
//  WaterControlView.swift
//  HACCPPocket
//
//  Contrôles de l'eau et du réseau intérieur.
//

import SwiftUI
import SwiftData

struct WaterControlListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \WaterControl.performedAt, order: .reverse)
    private var controls: [WaterControl]

    @AppStorage("haccp.water.isPrivateSupply") private var isPrivateSupply = false

    @State private var isCreating = false
    @State private var editedControl: WaterControl?
    @State private var showsPaywall = false

    private var attention: [WaterControl] { controls.filter(\.needsAction) }
    private var settled: [WaterControl] { controls.filter { !$0.needsAction } }

    var body: some View {
        List {
            supplySection

            if controls.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun contrôle", systemImage: "drop")
                    } description: {
                        Text("Sur réseau public, votre responsabilité commence au compteur : c'est votre réseau intérieur qui peut dégrader une eau qui arrivait potable.")
                    } actions: {
                        Button("Enregistrer un contrôle") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section("À traiter") {
                    ForEach(attention) { control in row(control) }
                }
            }

            if !settled.isEmpty {
                Section("Historique") {
                    ForEach(settled) { control in row(control) }
                }
            }
        }
        .navigationTitle("Eau et réseau")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un contrôle", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            WaterControlEditorView(control: nil, isPrivateSupply: isPrivateSupply, context: modelContext)
        }
        .sheet(item: $editedControl) { control in
            WaterControlEditorView(control: control, isPrivateSupply: isPrivateSupply, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    /// L'origine de l'eau change tout : autant la demander une fois pour
    /// toutes et adapter le discours en conséquence.
    private var supplySection: some View {
        Section {
            Toggle("Ressource privée (puits, forage, source)", isOn: $isPrivateSupply)
        } header: {
            Text("Origine de l'eau")
        } footer: {
            Text(isPrivateSupply
                 ? "Une ressource privée impose une autorisation préfectorale préalable et des analyses régulières à votre charge. Enregistrez-les dans le registre des analyses."
                 : "Sur réseau public, l'eau est contrôlée en amont par le distributeur : vous n'avez aucune analyse à commander. Votre responsabilité porte sur le réseau intérieur — bras morts, adoucisseur, filtres, eau chaude.")
        }
    }

    private func row(_ control: WaterControl) -> some View {
        Button {
            editedControl = control
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: control.kind.systemImage, tint: tint(for: control))

                VStack(alignment: .leading, spacing: 3) {
                    Text(control.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(AppFormatters.shortDate(control.performedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if control.kind.hasMeasurement {
                        Text(control.formattedValue)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(control.isCompliant ? Color.secondary : Color.red)
                    }
                }

                Spacer(minLength: 8)

                StatusBadge(text: control.statusLabel, color: tint(for: control))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(control) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func tint(for control: WaterControl) -> Color {
        if control.needsAction { return .red }
        return control.isCompliant ? .green : .orange
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ control: WaterControl) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(control)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct WaterControlEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let control: WaterControl?
    private let defaultPrivateSupply: Bool
    private let context: ModelContext

    @State private var kind: WaterCheckKind
    @State private var location: String
    @State private var performedAt: Date
    @State private var valueText: String
    @State private var isCompliant: Bool
    @State private var correctiveAction: String
    @State private var hasNextDue: Bool
    @State private var nextDueDate: Date
    @State private var operatorName: String
    @State private var notes: String

    init(control: WaterControl?, isPrivateSupply: Bool, context: ModelContext) {
        self.control = control
        self.defaultPrivateSupply = isPrivateSupply
        self.context = context

        _kind = State(initialValue: control?.kind ?? .chlorine)
        _location = State(initialValue: control?.location ?? "")
        _performedAt = State(initialValue: control?.performedAt ?? .now)
        _valueText = State(
            initialValue: control?.measuredValue.map {
                $0.formatted(.number.precision(.fractionLength(0...2)).locale(AppFormatters.locale))
            } ?? ""
        )
        _isCompliant = State(initialValue: control?.isCompliant ?? true)
        _correctiveAction = State(initialValue: control?.correctiveAction ?? "")
        _hasNextDue = State(initialValue: control?.nextDueDate != nil)
        _nextDueDate = State(
            initialValue: control?.nextDueDate
                ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)
                ?? .now
        )
        _operatorName = State(initialValue: control?.operatorName ?? "")
        _notes = State(initialValue: control?.notes ?? "")
    }

    private var measuredValue: Double? {
        AppFormatters.parseTemperature(valueText)
    }

    private var canSave: Bool {
        if !isCompliant && correctiveAction.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Opération", selection: $kind) {
                        ForEach(WaterCheckKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    TextField("Point ou équipement concerné", text: $location)
                    DatePicker("Réalisé le", selection: $performedAt, in: ...Date.now)
                } header: {
                    Text("Contrôle")
                } footer: {
                    Text(kind.detail)
                }

                if kind.hasMeasurement {
                    Section("Mesure") {
                        HStack {
                            Text("Valeur relevée")
                            Spacer()
                            TextField("0", text: $valueText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(maxWidth: 100)
                            Text(kind.unit).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Résultat conforme", isOn: $isCompliant)

                    if !isCompliant {
                        TextField(
                            "Suite donnée",
                            text: $correctiveAction,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                } footer: {
                    if !isCompliant {
                        Text("Obligatoire : une anomalie sur le réseau sans suite écrite laisse le problème entier.")
                    }
                }

                Section {
                    Toggle("Prochaine échéance", isOn: $hasNextDue)
                    if hasNextDue {
                        DatePicker("À refaire le", selection: $nextDueDate, displayedComponents: .date)
                    }
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(control == nil ? "Nouveau contrôle" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private func save() {
        let target = control ?? WaterControl()

        target.kind = kind
        target.location = location
        target.performedAt = performedAt
        target.measuredValue = kind.hasMeasurement ? measuredValue : nil
        target.isPrivateSupply = control?.isPrivateSupply ?? defaultPrivateSupply
        target.isCompliant = isCompliant
        target.correctiveAction = isCompliant ? "" : correctiveAction
        target.nextDueDate = hasNextDue ? nextDueDate : nil
        target.operatorName = operatorName
        target.notes = notes

        if control == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
