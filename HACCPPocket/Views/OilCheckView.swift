//
//  OilCheckView.swift
//  HACCPPocket
//
//  Registre des bains de friture : mesure des composés polaires, aspect du
//  bain et suite donnée.
//

import SwiftUI
import SwiftData

// MARK: - Liste

struct OilCheckListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \OilCheckRecord.checkedAt, order: .reverse)
    private var records: [OilCheckRecord]

    @State private var editedRecord: OilCheckRecord?
    @State private var isCreating = false
    @State private var showsPaywall = false
    @State private var recordPendingDeletion: OilCheckRecord?

    var body: some View {
        List {
            ForEach(records) { record in
                Button {
                    editedRecord = record
                } label: {
                    row(record)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        recordPendingDeletion = record
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Huiles de friture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if subscription.canWrite { isCreating = true } else { showsPaywall = true }
                } label: {
                    Label("Nouveau contrôle", systemImage: "plus")
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Aucun contrôle", systemImage: "drop.triangle")
                } description: {
                    Text("Enregistrez ici vos contrôles de bains : un bain au-delà de 25 % de composés polaires doit être changé.")
                } actions: {
                    Button("Nouveau contrôle") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $isCreating) { OilCheckFormView(context: modelContext) }
        .sheet(item: $editedRecord) { record in
            OilCheckFormView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .confirmationDialog(
            "Supprimer ce contrôle ?",
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
        }
    }

    private func row(_ record: OilCheckRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: record.action.systemImage,
                tint: record.isCompliant ? .green : .red
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.fryerName)
                    .font(.subheadline.weight(.semibold))
                Text("\(record.formattedPolarCompounds) · \(record.appearance.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(AppFormatters.shortDate(record.checkedAt)) · \(record.action.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if record.needsAction {
                    Label("Bain hors seuil conservé", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: record.statusLabel,
                color: record.isCompliant ? .green : .red
            )
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Formulaire

struct OilCheckFormView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let record: OilCheckRecord?
    private let context: ModelContext

    @State private var fryerName: String
    @State private var checkedAt: Date
    @State private var polarText: String
    @State private var hasMeasurement: Bool
    @State private var appearance: OilAppearance
    @State private var action: OilAction
    @State private var operatorName: String
    @State private var comment: String

    init(record: OilCheckRecord? = nil, context: ModelContext) {
        self.record = record
        self.context = context

        _fryerName = State(initialValue: record?.fryerName ?? "Friteuse")
        _checkedAt = State(initialValue: record?.checkedAt ?? .now)
        _hasMeasurement = State(initialValue: record?.polarCompounds != nil)
        _polarText = State(initialValue: record?.polarCompounds.map {
            $0.formatted(.number.precision(.fractionLength(1)).locale(AppFormatters.locale))
        } ?? "")
        _appearance = State(initialValue: record?.appearance ?? .clear)
        _action = State(initialValue: record?.action ?? .kept)
        _operatorName = State(initialValue: record?.operatorName ?? "")
        _comment = State(initialValue: record?.comment ?? "")
    }

    private var polarCompounds: Double? {
        hasMeasurement ? AppFormatters.parseTemperature(polarText) : nil
    }

    /// Conformité prévisionnelle, affichée pendant la saisie.
    private var isCompliant: Bool {
        if let polarCompounds { return polarCompounds <= OilCheckRecord.polarCompoundsLimit }
        return !appearance.isSuspect
    }

    private var canSave: Bool {
        guard !fryerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if hasMeasurement && polarCompounds == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProtocolLink(procedure: .oilCheck)
                }

                Section("Friteuse") {
                    TextField("Nom ou emplacement", text: $fryerName)
                    DatePicker("Contrôlé le", selection: $checkedAt, in: ...Date.now)
                }

                Section {
                    Toggle("Mesure au testeur", isOn: $hasMeasurement)

                    if hasMeasurement {
                        HStack {
                            Text("Composés polaires")
                            Spacer()
                            TextField("0,0", text: $polarText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(maxWidth: 80)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }

                    Picker("Aspect du bain", selection: $appearance) {
                        ForEach(OilAppearance.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Label(
                        isCompliant ? "Bain conforme" : "Bain à changer",
                        systemImage: isCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCompliant ? Color.green : Color.red)
                } header: {
                    Text("Contrôle")
                } footer: {
                    Text("Le seuil réglementaire est de 25 % de composés polaires. Sans testeur, l'aspect fait foi : un bain foncé est considéré non conforme.")
                }

                Section {
                    Picker("Suite donnée", selection: $action) {
                        ForEach(OilAction.allCases) { value in
                            Label(value.label, systemImage: value.systemImage).tag(value)
                        }
                    }
                } footer: {
                    if !isCompliant && action == .kept {
                        Label(
                            "Un bain hors seuil doit être filtré ou changé.",
                            systemImage: "exclamationmark.bubble"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouveau contrôle" : "Modifier le contrôle")
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
        let trimmed = fryerName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let record {
            record.fryerName = trimmed
            record.checkedAt = checkedAt
            record.polarCompounds = polarCompounds
            record.appearance = appearance
            record.action = action
            record.operatorName = operatorName
            record.comment = comment
            record.recomputeCompliance()
        } else {
            let created = OilCheckRecord(
                fryerName: trimmed,
                checkedAt: checkedAt,
                polarCompounds: polarCompounds,
                appearance: appearance,
                action: action,
                operatorName: operatorName,
                comment: comment
            )
            context.insert(created)
        }

        try? context.save()
        dismiss()
    }
}
