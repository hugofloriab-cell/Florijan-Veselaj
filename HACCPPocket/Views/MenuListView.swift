//
//  MenuListView.swift
//  HACCPPocket
//
//  La carte : les plats servis et leurs allergènes.
//
//  C'est le registre que réclame un contrôleur au titre de l'information du
//  consommateur, et celui qu'on sort quand un client demande « il y a des
//  fruits à coque dedans ? ».
//

import SwiftUI
import SwiftData

struct MenuListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: [SortDescriptor(\Dish.sortIndex), SortDescriptor(\Dish.name)])
    private var dishes: [Dish]

    @Query private var establishments: [Establishment]

    @State private var searchText = ""
    @State private var showsUnavailable = false
    @State private var editedDish: Dish?
    @State private var showsPaywall = false
    @State private var sheetURL: URL?
    @State private var isPreparingSheet = false
    @State private var errorMessage: String?

    // MARK: - Corps

    var body: some View {
        List {
            if dishes.isEmpty {
                emptyState
            } else {
                if incompleteCount > 0 {
                    reviewSection
                }

                ForEach(groupedDishes) { group in
                    Section(group.category.label) {
                        ForEach(group.dishes) { dish in
                            Button {
                                editedDish = dish
                            } label: {
                                DishRow(dish: dish)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(dish)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }

                                Button {
                                    toggleAvailability(dish)
                                } label: {
                                    Label(
                                        dish.isAvailable ? "Retirer" : "Remettre",
                                        systemImage: dish.isAvailable ? "eye.slash" : "eye"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                exportSection
            }
        }
        .navigationTitle("Ma carte")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Nom d'un plat, ingrédient…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addDish()
                } label: {
                    Label("Ajouter un plat", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Toggle("Afficher les plats retirés", isOn: $showsUnavailable)
            }
        }
        .sheet(item: $editedDish) { dish in
            DishEditorView(dish: dish, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .alert("Fiche allergènes", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("Fermer", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Regroupement

    private struct DishGroup: Identifiable {
        let category: DishCategory
        var dishes: [Dish]
        var id: String { category.rawValue }
    }

    private var filteredDishes: [Dish] {
        let needle = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)

        return dishes.filter { dish in
            if !showsUnavailable && !dish.isAvailable { return false }
            guard !needle.isEmpty else { return true }

            let haystack = [dish.name, dish.summary, dish.composition, dish.allergenSummary]
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)
            return haystack.contains(needle)
        }
    }

    private var groupedDishes: [DishGroup] {
        var groups: [DishGroup] = []
        for category in DishCategory.allCases.sorted(by: { $0.sortWeight < $1.sortWeight }) {
            let matching = filteredDishes.filter { $0.category == category }
            if !matching.isEmpty {
                groups.append(DishGroup(category: category, dishes: matching))
            }
        }
        return groups
    }

    /// Plats dont la fiche allergènes n'a jamais été renseignée. Un plat sans
    /// allergène coché ET sans composition est un plat qu'on a oublié, pas un
    /// plat sans allergène.
    private var incompleteCount: Int {
        dishes.filter { $0.isAvailable && $0.needsAllergenReview }.count
    }

    // MARK: - Sections

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label("Votre carte est vide", systemImage: "fork.knife")
            } description: {
                Text("Ajoutez vos plats et cochez leurs allergènes. Vous obtiendrez une fiche à afficher en salle, à jour et prête à présenter.")
            } actions: {
                Button("Ajouter un plat") { addDish() }
                    .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var reviewSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(incompleteCount) plat(s) sans fiche allergènes")
                        .font(.subheadline.weight(.medium))
                    Text("Un plat sans allergène coché et sans composition n'est pas un plat sans allergène : c'est une fiche qui n'a pas été remplie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                prepareSheet()
            } label: {
                if isPreparingSheet {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Préparation…")
                    }
                } else {
                    Label("Préparer la fiche allergènes", systemImage: "doc.text")
                }
            }
            .disabled(isPreparingSheet || filteredDishes.isEmpty)

            if let sheetURL {
                ShareLink(item: sheetURL) {
                    Label("Imprimer ou partager la fiche", systemImage: "printer")
                }
            }
        } header: {
            Text("Fiche à afficher")
        } footer: {
            Text("Un tableau A4 : vos plats en lignes, les quatorze allergènes en colonnes. À afficher en salle ou à garder près du passe.")
        }
    }

    // MARK: - Actions

    private func addDish() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }

        let dish = Dish(sortIndex: (dishes.map(\.sortIndex).max() ?? 0) + 1)
        modelContext.insert(dish)
        try? modelContext.save()
        editedDish = dish
    }

    private func delete(_ dish: Dish) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(dish)
        try? modelContext.save()
    }

    private func toggleAvailability(_ dish: Dish) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        dish.isAvailable.toggle()
        dish.touch()
        try? modelContext.save()
    }

    private func prepareSheet() {
        isPreparingSheet = true

        Task { @MainActor in
            await Task.yield()

            let sheet = AllergenSheet(
                dishes: filteredDishes,
                establishment: establishments.first,
                watermark: subscription.pdfWatermark
            )

            do {
                sheetURL = try AllergenSheetService.render(sheet)
            } catch {
                errorMessage = "La fiche n'a pas pu être créée. \(error.localizedDescription)"
            }

            isPreparingSheet = false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

// MARK: - Ligne

private struct DishRow: View {

    let dish: Dish

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: dish.category.systemImage,
                tint: dish.isAvailable ? .brand : .secondary
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dish.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(dish.isAvailable ? Color.primary : Color.secondary)

                    if !dish.isAvailable {
                        StatusBadge(text: "Retiré", color: .secondary)
                    }
                }

                if !dish.summary.isEmpty {
                    Text(dish.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if dish.needsAllergenReview {
                    Label("Fiche allergènes à remplir", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    AllergenBadges(allergens: dish.allergens)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        MenuListView()
    }
    .modelContainer(AppSchema.preview)
    .environment(SubscriptionManager.shared)
}
