//
//  ShiftHygieneView.swift
//  HACCPPocket
//
//  Contrôle d'hygiène à la prise de poste.
//

import SwiftUI
import SwiftData

struct ShiftHygieneListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \ShiftHygieneCheck.checkedAt, order: .reverse)
    private var checks: [ShiftHygieneCheck]

    @State private var isCreating = false
    @State private var editedCheck: ShiftHygieneCheck?
    @State private var showsPaywall = false

    private var today: [ShiftHygieneCheck] {
        let calendar = Calendar.current
        return checks.filter { calendar.isDateInToday($0.checkedAt) }
    }

    private var earlier: [ShiftHygieneCheck] {
        let calendar = Calendar.current
        return checks.filter { !calendar.isDateInToday($0.checkedAt) }
    }

    var body: some View {
        List {
            if checks.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun contrôle enregistré", systemImage: "hands.and.sparkles")
                    } description: {
                        Text("C'est le contrôle le plus court et le plus rentable de la cuisine. La contamination la plus fréquente ne vient ni du frigo ni du fournisseur : elle vient des mains.")
                    } actions: {
                        Button("Contrôler une prise de poste") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !today.isEmpty {
                Section("Aujourd'hui") {
                    ForEach(today) { check in row(check) }
                }
            }

            if !earlier.isEmpty {
                Section("Historique") {
                    ForEach(earlier) { check in row(check) }
                }
            }
        }
        .navigationTitle("Prise de poste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Contrôler une prise de poste", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ShiftHygieneEditorView(check: nil, context: modelContext)
        }
        .sheet(item: $editedCheck) { check in
            ShiftHygieneEditorView(check: check, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ check: ShiftHygieneCheck) -> some View {
        Button {
            editedCheck = check
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: check.isDisqualified ? "xmark.octagon.fill" : "hands.and.sparkles",
                    tint: tint(for: check)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(check.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle(for: check))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !check.isCompliant {
                        Text(check.failureSummary)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(text: check.statusLabel, color: tint(for: check))
                    if check.hasSignature {
                        Image(systemName: "signature")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(check) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func subtitle(for check: ShiftHygieneCheck) -> String {
        var parts = [AppFormatters.time(check.checkedAt)]
        if !check.shiftLabel.isEmpty { parts.append(check.shiftLabel) }
        if !check.checkedBy.isEmpty { parts.append("contrôlé par \(check.checkedBy)") }
        return parts.joined(separator: " · ")
    }

    private func tint(for check: ShiftHygieneCheck) -> Color {
        if check.isIncomplete { return .secondary }
        if check.isDisqualified { return .red }
        return check.isCompliant ? .green : .orange
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ check: ShiftHygieneCheck) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(check)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct ShiftHygieneEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let check: ShiftHygieneCheck?
    private let context: ModelContext

    @State private var personName: String
    @State private var shiftLabel: String
    @State private var checkedAt: Date
    @State private var passed: Set<HygieneCheckItem>
    @State private var failed: Set<HygieneCheckItem>
    @State private var correctiveAction: String
    @State private var checkedBy: String
    @State private var comment: String
    @State private var signatureData: Data?

    init(check: ShiftHygieneCheck?, context: ModelContext) {
        self.check = check
        self.context = context

        _personName = State(initialValue: check?.personName ?? "")
        _shiftLabel = State(initialValue: check?.shiftLabel ?? "")
        _checkedAt = State(initialValue: check?.checkedAt ?? .now)
        _passed = State(initialValue: check?.passed ?? [])
        _failed = State(initialValue: check?.failed ?? [])
        _correctiveAction = State(initialValue: check?.correctiveAction ?? "")
        _checkedBy = State(initialValue: check?.checkedBy ?? "")
        _comment = State(initialValue: check?.comment ?? "")
        _signatureData = State(initialValue: check?.signatureData)
    }

    private var isDisqualified: Bool {
        failed.contains { $0.isDisqualifying }
    }

    private var untouched: [HygieneCheckItem] {
        HygieneCheckItem.allCases.filter { !passed.contains($0) && !failed.contains($0) }
    }

    private var canSave: Bool {
        guard !personName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // Un écart sans suite écrite ne vaut rien : c'est exactement ce qu'un
        // contrôleur cherche à lire.
        if !failed.isEmpty && correctiveAction.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personne contrôlée") {
                    OperatorField(name: $personName, placeholder: "Nom")
                    TextField("Service (matin, midi, soir…)", text: $shiftLabel)
                    DatePicker("Contrôlé le", selection: $checkedAt, in: ...Date.now)
                }

                Section {
                    ForEach(HygieneCheckItem.allCases) { item in
                        checkRow(item)
                    }
                } header: {
                    Text("Points de contrôle")
                } footer: {
                    Text(untouched.isEmpty
                         ? "Tous les points ont été passés en revue."
                         : "\(untouched.count) point(s) pas encore renseigné(s). Appuyez à gauche pour conforme, à droite pour non conforme.")
                }

                if isDisqualified {
                    Section {
                        Label(
                            "Poste interdit tant que le symptôme persiste. Reclassez la personne sans contact avec les denrées, ou renvoyez-la chez elle.",
                            systemImage: "xmark.octagon.fill"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !failed.isEmpty {
                    Section {
                        TextField(
                            "Ex. charlotte fournie, bijoux retirés, poste changé",
                            text: $correctiveAction,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    } header: {
                        Label("Suite donnée", systemImage: "wrench.and.screwdriver")
                    } footer: {
                        Text("Obligatoire dès qu'un écart est constaté.")
                    }
                }

                Section {
                    SignatureField(signatureData: $signatureData, signerName: personName)
                } header: {
                    Text("Émargement")
                } footer: {
                    Text("Facultatif, mais c'est ce qui distingue un registre tenu au jour le jour d'une feuille remplie la veille du contrôle.")
                }

                Section("Détails") {
                    OperatorField(name: $checkedBy, placeholder: "Contrôlé par")
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(check == nil ? "Prise de poste" : "Modifier")
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
                if checkedBy.isEmpty { checkedBy = preferences.operatorName }
            }
        }
    }

    /// Trois états : non renseigné, conforme, non conforme. Deux boutons
    /// suffisent, et le troisième état est simplement l'absence des deux.
    private func checkRow(_ item: HygieneCheckItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.label)
                            .font(.subheadline.weight(.medium))
                        if let note = item.note {
                            RegulatoryBadge(note: note)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                verdictButton(
                    "Conforme",
                    systemImage: "checkmark",
                    tint: .green,
                    isOn: passed.contains(item)
                ) {
                    passed.insert(item)
                    failed.remove(item)
                }

                verdictButton(
                    "Écart",
                    systemImage: "xmark",
                    tint: .red,
                    isOn: failed.contains(item)
                ) {
                    failed.insert(item)
                    passed.remove(item)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func verdictButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    isOn ? tint.opacity(0.18) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .foregroundStyle(isOn ? tint : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let target = check ?? ShiftHygieneCheck()

        target.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.shiftLabel = shiftLabel
        target.checkedAt = checkedAt
        target.passed = passed
        target.failed = failed
        target.correctiveAction = correctiveAction
        target.signatureData = signatureData
        target.checkedBy = checkedBy
        target.comment = comment

        if check == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
