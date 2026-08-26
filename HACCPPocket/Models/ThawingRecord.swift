//
//  ThawingRecord.swift
//  HACCPPocket
//
//  Registre de décongélation.
//
//  La décongélation est l'opération la plus souvent bâclée d'une cuisine :
//  elle se fait la veille, sans témoin, et personne ne note rien. Or elle
//  raccourcit brutalement la durée de vie du produit — une pièce décongelée
//  ne se conserve plus comme une pièce fraîche, et sa DLC d'origine ne veut
//  plus rien dire.
//

import Foundation
import SwiftData

// MARK: - Méthode

/// Les trois méthodes admises. La décongélation à température ambiante n'en
/// fait pas partie : elle laisse la surface du produit des heures en zone de
/// danger pendant que le cœur est encore gelé.
enum ThawingMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case coldRoom       // Enceinte froide à +3 °C
    case runningWater   // Eau froide courante, produit protégé
    case microwave      // Micro-ondes, cuisson immédiate obligatoire
    case directCooking  // Cuisson sans décongélation préalable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coldRoom:       "En enceinte froide"
        case .runningWater:   "Sous eau froide courante"
        case .microwave:      "Au micro-ondes"
        case .directCooking:  "Cuisson directe sans décongélation"
        }
    }

    var detail: String {
        switch self {
        case .coldRoom:
            "La méthode de référence. Comptez 24 heures pour 2 kg, sur une grille et un bac de récupération."
        case .runningWater:
            "Produit sous emballage étanche, eau à moins de +21 °C. Cuisson immédiate après décongélation."
        case .microwave:
            "Réservé aux petites pièces, et uniquement si la cuisson suit immédiatement."
        case .directCooking:
            "Possible pour les petites pièces. Aucun risque lié à la décongélation puisqu'il n'y en a pas."
        }
    }

    var systemImage: String {
        switch self {
        case .coldRoom:      "refrigerator"
        case .runningWater:  "drop"
        case .microwave:     "wave.3.right"
        case .directCooking: "flame"
        }
    }

    /// Ces méthodes imposent une cuisson dans la foulée : le produit ne
    /// repart pas au froid pour le lendemain.
    var requiresImmediateCooking: Bool {
        self == .runningWater || self == .microwave
    }
}

// MARK: - Enregistrement

@Model
final class ThawingRecord {

    var productName: String = ""
    var batchNumber: String = ""

    /// Enceinte où le produit décongèle, quand la méthode en utilise une.
    var location: String = ""

    var methodRawValue: String = ThawingMethod.coldRoom.rawValue

    /// Mise en décongélation.
    var startedAt: Date = Date.now

    /// Fin constatée. `nil` tant que le produit décongèle.
    var finishedAt: Date?

    /// DLC imprimée par le fournisseur, avant congélation. Elle ne s'applique
    /// plus une fois le produit décongelé, mais elle plafonne tout le reste.
    var originalExpiryDate: Date?

    /// Durée de vie accordée après décongélation, en jours.
    var shelfLifeDays: Int = 1

    var quantity: String = ""
    var operatorName: String = ""
    var comment: String = ""
    var createdAt: Date = Date.now

    init(
        productName: String = "",
        batchNumber: String = "",
        location: String = "",
        method: ThawingMethod = .coldRoom,
        startedAt: Date = .now,
        originalExpiryDate: Date? = nil,
        shelfLifeDays: Int = 1,
        quantity: String = "",
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.productName = productName
        self.batchNumber = batchNumber
        self.location = location
        self.methodRawValue = method.rawValue
        self.startedAt = startedAt
        self.finishedAt = nil
        self.originalExpiryDate = originalExpiryDate
        self.shelfLifeDays = shelfLifeDays
        self.quantity = quantity
        self.operatorName = operatorName
        self.comment = comment
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var method: ThawingMethod {
        get { ThawingMethod(rawValue: methodRawValue) ?? .coldRoom }
        set { methodRawValue = newValue.rawValue }
    }

    var isFinished: Bool { finishedAt != nil }

    var displayName: String {
        productName.isEmpty ? "Produit sans nom" : productName
    }

    // MARK: - DLC résiduelle

    /// Date de retrait après décongélation.
    ///
    /// Deux plafonds s'appliquent, et c'est le plus court qui gagne : la durée
    /// accordée après décongélation, et la DLC d'origine du produit. On ne
    /// gagne jamais de temps en décongelant.
    func residualLimitDate(calendar: Calendar = .current) -> Date {
        let reference = finishedAt ?? startedAt
        let computed = calendar.date(byAdding: .day, value: shelfLifeDays, to: reference) ?? reference

        guard let originalExpiryDate else { return computed }
        return min(computed, originalExpiryDate)
    }

    /// La DLC d'origine est-elle plus courte que la durée accordée ?
    func originalExpiryWins(calendar: Calendar = .current) -> Bool {
        guard let originalExpiryDate else { return false }
        let reference = finishedAt ?? startedAt
        let computed = calendar.date(byAdding: .day, value: shelfLifeDays, to: reference) ?? reference
        return originalExpiryDate < computed
    }

    func isExpired(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: residualLimitDate(calendar: calendar))
            < calendar.startOfDay(for: reference)
    }

    var statusLabel: String {
        if isExpired() { return "À retirer" }
        if !isFinished { return "En cours" }
        return "Décongelé"
    }
}
