//
//  CleaningTaskEditorView.swift
//  HACCPPocket
//
//  Création et modification d'une ligne du plan de nettoyage. Sans cet écran,
//  l'utilisateur restait prisonnier des opérations livrées par défaut.
//

import SwiftUI
import SwiftData

struct CleaningTaskEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let task: CleaningTask?
    private let sortIndex: Int

    @State private var title: String
    @State private var zone: String
    @State private var productUsed: String
    @State private var procedure: String
    @State private var frequency: CleaningFrequency
    @State private var requiresPhoto: Bool
    @State private var isActive: Bool

    /// `task` à `nil` crée une nouvelle opération.
    init(task: CleaningTask?, sortIndex: Int = 0) {
        self.task = task
        self.sortIndex = task?.sortIndex ?? sortIndex

        _title = State(initialValue: task?.title ?? "")
        _zone = State(initialValue: task?.zone ?? "")
        _productUsed = State(initialValue: task?.productUsed ?? "")
        _procedure = State(initialValue: task?.procedure ?? "")
        _frequency = State(initialValue: task?.frequency ?? .daily)
        // Exigée d'office sur une nouvelle ligne, reprise telle quelle sur une
        // ligne existante : on n'impose pas rétroactivement une preuve que le
        // plan de nettoyage ne demandait pas.
        _requiresPhoto = State(initialValue: task?.requiresPhoto ?? true)
        _isActive = State(initialValue: task?.isActive ?? true)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Opération") {
                    TextField("Intitulé (ex. Désinfection du plan de travail)", text: $title)

                    Picker("Fréquence", selection: $frequency) {
                        ForEach(CleaningFrequency.allCases) { frequency in
                            Label(frequency.label, systemImage: frequency.systemImage).tag(frequency)
                        }
                    }

                    TextField("Zone (ex. Cuisine, Plonge, Sanitaires)", text: $zone)
                }

                Section {
                    TextField("Produit et dosage", text: $productUsed)
                } header: {
                    Text("Produit utilisé")
                } footer: {
                    Text("Le plan de maîtrise sanitaire impose d'indiquer le produit employé et son dosage.")
                }

                Section {
                    TextField(
                        "Nettoyer, rincer, désinfecter, laisser agir 5 min, rincer à l'eau potable.",
                        text: $procedure,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } header: {
                    Text("Mode opératoire")
                } footer: {
                    Text("Consultable d'un geste depuis le plan de nettoyage, au moment de cocher l'opération.")
                }

                Section {
                    Toggle("Photo obligatoire", isOn: $requiresPhoto)
                } header: {
                    Text("Preuve")
                } footer: {
                    Text("Une case cochée ne prouve rien. Une photo horodatée de l'équipement propre, si — c'est elle qu'on montre en cas de contrôle ou de litige. Vous ne pourrez pas valider l'opération sans elle.")
                }

                if task != nil {
                    Section {
                        Toggle("Opération active", isOn: $isActive)
                    } footer: {
                        Text("Une opération archivée disparaît du plan quotidien, mais son historique reste dans les exports.")
                    }
                }
            }
            .navigationTitle(task == nil ? "Nouvelle opération" : "Modifier l'opération")
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
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let task {
            task.title = trimmedTitle
            task.zone = zone
            task.productUsed = productUsed
            task.procedure = procedure
            task.frequency = frequency
            task.requiresPhoto = requiresPhoto
            task.isActive = isActive
        } else {
            let created = CleaningTask(
                title: trimmedTitle,
                frequency: frequency,
                zone: zone,
                productUsed: productUsed,
                procedure: procedure,
                requiresPhoto: requiresPhoto,
                sortIndex: sortIndex
            )
            modelContext.insert(created)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CleaningTaskEditorView(task: nil)
        .modelContainer(AppSchema.preview)
}
