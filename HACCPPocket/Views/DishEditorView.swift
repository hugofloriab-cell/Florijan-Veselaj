//
//  DishEditorView.swift
//  HACCPPocket
//
//  Fiche d'un plat : nom, catégorie, composition et allergènes.
//

import SwiftUI
import SwiftData

struct DishEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let dish: Dish
    private let context: ModelContext

    @State private var name: String
    @State private var category: DishCategory
    @State private var summary: String
    @State private var composition: String
    @State private var allergens: Set<Allergen>
    @State private var isAvailable: Bool
    @State private var isHomemade: Bool

    @FocusState private var nameIsFocused: Bool

    init(dish: Dish, context: ModelContext) {
        self.dish = dish
        self.context = context

        _name = State(initialValue: dish.name)
        _category = State(initialValue: dish.category)
        _summary = State(initialValue: dish.summary)
        _composition = State(initialValue: dish.composition)
        _allergens = State(initialValue: dish.allergens)
        _isAvailable = State(initialValue: dish.isAvailable)
        _isHomemade = State(initialValue: dish.isHomemade)
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                allergenSection
                compositionSection
                statusSection
            }
            .navigationTitle(name.isEmpty ? "Nouveau plat" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty { nameIsFocused = true }
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            TextField("Nom du plat", text: $name)
                .focused($nameIsFocused)

            Picker("Catégorie", selection: $category) {
                ForEach(DishCategory.allCases) { category in
                    Label(category.singularLabel, systemImage: category.systemImage)
                        .tag(category)
                }
            }

            TextField("Description courte (facultatif)", text: $summary, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Le plat")
        }
    }

    private var allergenSection: some View {
        Section {
            AllergenSummaryRow(selection: $allergens, subject: name.isEmpty ? "Allergènes" : name)
        } header: {
            Text("Information du consommateur")
        } footer: {
            Text(allergens.isEmpty && composition.isEmpty
                 ? "Tant que rien n'est renseigné, ce plat apparaîtra comme « fiche à remplir » : un plat sans allergène coché n'est pas un plat sans allergène."
                 : "Ces allergènes apparaîtront dans la fiche à afficher en salle.")
        }
    }

    private var compositionSection: some View {
        Section {
            TextField(
                "Ingrédients, sauces, garnitures…",
                text: $composition,
                axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("Composition")
        } footer: {
            Text("Facultative, mais c'est elle qui justifie les allergènes cochés en cas de contrôle. Pensez aux sauces, bouillons et panures : ce sont eux qu'on oublie.")
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Au menu en ce moment", isOn: $isAvailable)
            Toggle("Fait maison", isOn: $isHomemade)
        } footer: {
            Text("Un plat retiré de la carte reste enregistré : les anciennes fiches allergènes doivent pouvoir être reconstituées. La mention « fait maison » suit le décret n° 2014-797.")
        }
    }

    // MARK: - Actions

    private func save() {
        dish.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        dish.category = category
        dish.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        dish.composition = composition.trimmingCharacters(in: .whitespacesAndNewlines)
        dish.allergens = allergens
        dish.isAvailable = isAvailable
        dish.isHomemade = isHomemade
        dish.touch()

        try? context.save()
        dismiss()
    }

    /// Un plat créé puis abandonné ne doit pas rester dans la carte : on le
    /// retire plutôt que de laisser une ligne « Plat sans nom ».
    private func cancel() {
        if dish.name.isEmpty && name.trimmingCharacters(in: .whitespaces).isEmpty {
            context.delete(dish)
            try? context.save()
        }
        dismiss()
    }
}
