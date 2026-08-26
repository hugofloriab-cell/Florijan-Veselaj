//
//  FoodSample.swift
//  HACCPPocket
//
//  Registre des plats témoins.
//
//  Un plat témoin est un échantillon d'environ 100 g de chaque plat servi,
//  conservé au froid. Il ne sert à rien tant que tout va bien — et il devient
//  la seule preuve disponible le jour où un convive tombe malade. Sans lui,
//  l'établissement ne peut pas démontrer que le plat incriminé était conforme.
//
//  Obligatoire en restauration collective, et pour les traiteurs à partir
//  d'un certain nombre de couverts.
//

import Foundation
import SwiftData

@Model
final class FoodSample {

    /// Nom du plat, tel qu'il figure au menu du jour.
    var dishName: String = ""

    /// Service concerné : midi, soir, banquet, prestation.
    var serviceLabel: String = ""

    /// Date et heure du prélèvement.
    var collectedAt: Date = Date.now

    /// Dernière présentation au consommateur : c'est elle qui fait courir le
    /// délai de conservation, pas la date de fabrication.
    var lastServedAt: Date = Date.now

    /// Quantité prélevée. 100 g est l'usage.
    var quantityGrams: Int = 100

    /// Nombre de couverts servis, utile pour retrouver l'ampleur d'un cas.
    var coverCount: Int = 0

    /// Emplacement de conservation, à +0/+3 °C.
    var storageLocation: String = ""

    var operatorName: String = ""
    var comment: String = ""

    /// Élimination effective de l'échantillon.
    var discardedAt: Date?

    var createdAt: Date = Date.now

    /// Durée de conservation réglementaire, en jours, après la dernière
    /// présentation au consommateur.
    static let retentionDays = 5

    init(
        dishName: String = "",
        serviceLabel: String = "",
        collectedAt: Date = .now,
        lastServedAt: Date? = nil,
        quantityGrams: Int = 100,
        coverCount: Int = 0,
        storageLocation: String = "",
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.dishName = dishName
        self.serviceLabel = serviceLabel
        self.collectedAt = collectedAt
        self.lastServedAt = lastServedAt ?? collectedAt
        self.quantityGrams = quantityGrams
        self.coverCount = coverCount
        self.storageLocation = storageLocation
        self.operatorName = operatorName
        self.comment = comment
        self.discardedAt = nil
        self.createdAt = createdAt
    }

    // MARK: - Conservation

    var displayName: String {
        dishName.isEmpty ? "Plat sans nom" : dishName
    }

    var isDiscarded: Bool { discardedAt != nil }

    /// Date à partir de laquelle l'échantillon peut être éliminé.
    func disposalDate(calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .day,
            value: FoodSample.retentionDays,
            to: lastServedAt
        ) ?? lastServedAt
    }

    /// L'échantillon a-t-il fait son temps ?
    func canBeDiscarded(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: reference) >= calendar.startOfDay(for: disposalDate(calendar: calendar))
    }

    /// Jours restants avant élimination possible. Négatif si le délai est
    /// dépassé — l'échantillon encombre alors le frigo pour rien.
    func daysBeforeDisposal(from reference: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: disposalDate(calendar: calendar))
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var statusLabel: String {
        if isDiscarded { return "Éliminé" }
        if canBeDiscarded() { return "À éliminer" }
        let days = daysBeforeDisposal()
        return days <= 1 ? "Encore 1 jour" : "Encore \(days) jours"
    }

    /// Un échantillon dont le délai est passé doit sortir du frigo : il ne
    /// prouve plus rien et prend la place des suivants.
    var needsAction: Bool {
        !isDiscarded && canBeDiscarded()
    }
}
