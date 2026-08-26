//
//  WasteOilCollection.swift
//  HACCPPocket
//
//  Bordereaux de collecte des huiles alimentaires usagées.
//
//  Une huile de friture usagée est un déchet. Elle ne se jette ni à l'évier,
//  ni aux ordures ménagères : elle se fait enlever par un collecteur, et
//  l'établissement conserve la trace de chaque enlèvement.
//
//  Ce registre a une seconde vertu, moins évidente : confronter les volumes
//  collectés au registre des bains de friture. Une friteuse qu'on prétend
//  changer toutes les semaines sans jamais faire enlever d'huile pose une
//  question à laquelle il vaut mieux avoir une réponse.
//

import Foundation
import SwiftData

// MARK: - Unité

enum WasteOilUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case litres
    case kilograms

    var id: String { rawValue }

    var label: String {
        switch self {
        case .litres:    "litres"
        case .kilograms: "kilogrammes"
        }
    }

    var shortLabel: String {
        switch self {
        case .litres:    "L"
        case .kilograms: "kg"
        }
    }
}

// MARK: - Enlèvement

@Model
final class WasteOilCollection {

    var collectedAt: Date = Date.now

    /// Société de collecte.
    var collector: String = ""

    /// Numéro d'agrément ou d'identification du collecteur.
    var collectorApproval: String = ""

    /// Numéro du bordereau ou du bon d'enlèvement.
    var documentReference: String = ""

    var quantity: Double = 0
    var unitRawValue: String = WasteOilUnit.litres.rawValue

    /// Nombre de contenants repris.
    var containerCount: Int = 0

    /// Bordereau ou bon signé.
    @Attribute(.externalStorage) var documentData: Data?

    var operatorName: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    /// Durée de conservation du registre des déchets.
    static let retentionYears = 3

    init(
        collectedAt: Date = .now,
        collector: String = "",
        collectorApproval: String = "",
        documentReference: String = "",
        quantity: Double = 0,
        unit: WasteOilUnit = .litres,
        containerCount: Int = 0,
        documentData: Data? = nil,
        operatorName: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.collectedAt = collectedAt
        self.collector = collector
        self.collectorApproval = collectorApproval
        self.documentReference = documentReference
        self.quantity = quantity
        self.unitRawValue = unit.rawValue
        self.containerCount = containerCount
        self.documentData = documentData
        self.operatorName = operatorName
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var unit: WasteOilUnit {
        get { WasteOilUnit(rawValue: unitRawValue) ?? .litres }
        set { unitRawValue = newValue.rawValue }
    }

    var displayName: String {
        collector.isEmpty ? "Collecteur non précisé" : collector
    }

    var formattedQuantity: String {
        let number = quantity.formatted(
            .number.precision(.fractionLength(0...1)).locale(AppFormatters.locale)
        )
        return "\(number) \(unit.shortLabel)"
    }

    var hasDocument: Bool { documentData != nil }

    /// Un enlèvement sans bordereau ne prouve rien : c'est justement la pièce
    /// que l'on doit pouvoir présenter.
    var isIncomplete: Bool {
        !hasDocument || collector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusLabel: String {
        isIncomplete ? "Bordereau manquant" : "Complet"
    }
}
