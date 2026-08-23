//
//  ProductTrackingViewModel.swift
//  HACCPPocket
//
//  Actions sur la liste des produits tracés : filtrage, tri par urgence,
//  clôture (consommé ou jeté). La liste elle-même vient d'un `@Query`.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProductTrackingViewModel {

    /// Onglets de la liste des produits.
    enum Filter: String, CaseIterable, Identifiable {
        case active
        case expiringSoon
        case closed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .active:       "En cours"
            case .expiringSoon: "À traiter"
            case .closed:       "Historique"
            }
        }

        var systemImage: String {
            switch self {
            case .active:       "clock.badge.checkmark"
            case .expiringSoon: "exclamationmark.triangle"
            case .closed:       "archivebox"
            }
        }
    }

    private let modelContext: ModelContext

    var filter: Filter = .active
    var searchText: String = ""
    var storageFilter: StorageZone?

    private(set) var errorMessage: String?

    init(context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Filtrage et tri

    /// Applique filtre, recherche et tri à la liste fournie par la vue.
    /// Le tri place toujours le plus urgent en tête.
    func present(
        _ products: [TrackedProduct],
        at reference: Date = .now,
        calendar: Calendar = .current
    ) -> [TrackedProduct] {
        products
            .filter { matchesFilter($0, at: reference, calendar: calendar) }
            .filter(matchesStorage)
            .filter(matchesSearch)
            .sorted { lhs, rhs in
                let leftUrgency = lhs.urgency(at: reference, calendar: calendar)
                let rightUrgency = rhs.urgency(at: reference, calendar: calendar)
                if leftUrgency != rightUrgency { return leftUrgency > rightUrgency }
                return lhs.effectiveLimitDate < rhs.effectiveLimitDate
            }
    }

    private func matchesFilter(
        _ product: TrackedProduct,
        at reference: Date,
        calendar: Calendar
    ) -> Bool {
        switch filter {
        case .active:
            product.status == .inUse
        case .expiringSoon:
            product.status == .inUse
                && product.urgency(at: reference, calendar: calendar) >= .critical
        case .closed:
            product.status != .inUse
        }
    }

    private func matchesStorage(_ product: TrackedProduct) -> Bool {
        guard let storageFilter else { return true }
        return product.storage == storageFilter
    }

    private func matchesSearch(_ product: TrackedProduct) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystack = [product.name, product.batchNumber, product.supplier, product.barcode]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return haystack.contains(needle)
    }

    // MARK: - Actions

    /// Le produit a été terminé normalement.
    func markConsumed(_ product: TrackedProduct) {
        product.markConsumed()
        persist()
    }

    /// Le produit est jeté : le motif est obligatoire pour justifier la
    /// destruction en cas de contrôle.
    @discardableResult
    func markDiscarded(_ product: TrackedProduct, reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Indiquez le motif de la mise au rebut."
            return false
        }
        product.markDiscarded(reason: trimmed)
        persist()
        return errorMessage == nil
    }

    /// Motif pré-rempli quand le produit est jeté pour DLC dépassée.
    func suggestedDiscardReason(for product: TrackedProduct, at reference: Date = .now) -> String {
        product.isExpired(at: reference)
            ? "DLC secondaire dépassée le \(AppFormatters.shortDate(product.effectiveLimitDate))."
            : ""
    }

    func reopen(_ product: TrackedProduct) {
        product.reopen()
        persist()
    }

    /// Rouvre le même produit avec une nouvelle date d'ouverture. En cuisine,
    /// on ré-entame chaque semaine les mêmes références : re-saisir le nom, le
    /// fournisseur et le lot à chaque fois est le meilleur moyen de ne rien
    /// tracer du tout.
    @discardableResult
    func duplicate(_ product: TrackedProduct, shelfLifeDays: Int) -> TrackedProduct {
        let copy = TrackedProduct(
            name: product.name,
            openedAt: .now,
            secondaryLimitDate: TrackedProduct.defaultLimitDate(openedAt: .now, days: shelfLifeDays),
            storage: product.storage,
            batchNumber: product.batchNumber,
            barcode: product.barcode,
            supplier: product.supplier,
            notes: product.notes
        )
        modelContext.insert(copy)
        persist()
        return copy
    }

    /// Suppression définitive, réservée à une saisie erronée.
    func delete(_ product: TrackedProduct) {
        modelContext.delete(product)
        persist()
    }

    private func persist() {
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
        }
    }
}
