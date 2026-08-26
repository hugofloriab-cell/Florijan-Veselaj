//
//  WaterControl.swift
//  HACCPPocket
//
//  Contrôles de l'eau et du réseau interne.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DEUX SITUATIONS TRÈS DIFFÉRENTES
//  ─────────────────────────────────────────────────────────────────────────
//
//  RÉSEAU PUBLIC — l'eau est contrôlée en amont par le distributeur, et
//  l'exploitant n'a aucune analyse à commander. Sa responsabilité commence au
//  compteur : c'est son réseau intérieur qui peut dégrader une eau qui
//  arrivait potable. Bras morts, adoucisseur mal entretenu, filtres saturés,
//  ballon d'eau chaude tiède — autant de sources de contamination internes.
//
//  RESSOURCE PRIVÉE (puits, forage, source) — là, tout change : autorisation
//  préfectorale préalable, analyses obligatoires et surveillance à la charge
//  de l'exploitant.
//
//  Le registre couvre les deux, mais ne prétend pas que le premier cas impose
//  ce qu'exige le second.
//

import Foundation
import SwiftData

// MARK: - Type d'opération

enum WaterCheckKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case chlorine
    case flushing
    case filterChange
    case softener
    case temperature
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chlorine:     "Chlore résiduel"
        case .flushing:     "Purge des points peu utilisés"
        case .filterChange: "Changement de filtre"
        case .softener:     "Entretien de l'adoucisseur"
        case .temperature:  "Température de l'eau chaude"
        case .other:        "Autre contrôle"
        }
    }

    var detail: String {
        switch self {
        case .chlorine:
            "Mesuré au robinet le plus éloigné du compteur : c'est là que le résiduel est le plus faible."
        case .flushing:
            "Faire couler les robinets rarement utilisés. Une canalisation en eau stagnante est un bras mort, et un bras mort fabrique du biofilm."
        case .filterChange:
            "Un filtre saturé retient et cultive ce qu'il a arrêté. Suivez la périodicité du fabricant, pas l'aspect du filtre."
        case .softener:
            "Régénération, niveau de sel, désinfection périodique du bac. Un adoucisseur négligé est une des principales sources de contamination d'un réseau intérieur."
        case .temperature:
            "L'eau chaude sanitaire doit être suffisamment chaude pour ne pas favoriser les légionelles, et le mitigeage se fait au point d'usage."
        case .other:
            "Toute autre opération sur le réseau intérieur."
        }
    }

    var systemImage: String {
        switch self {
        case .chlorine:     "drop.triangle"
        case .flushing:     "arrow.down.to.line"
        case .filterChange: "line.3.horizontal.decrease.circle"
        case .softener:     "waterbottle"
        case .temperature:  "thermometer.medium"
        case .other:        "wrench"
        }
    }

    /// Les opérations qui portent une valeur mesurée.
    var hasMeasurement: Bool {
        self == .chlorine || self == .temperature
    }

    var unit: String {
        switch self {
        case .chlorine:    "mg/L"
        case .temperature: "°C"
        default:           ""
        }
    }
}

// MARK: - Enregistrement

@Model
final class WaterControl {

    var kindRawValue: String = WaterCheckKind.chlorine.rawValue

    /// Point de prélèvement ou équipement concerné.
    var location: String = ""

    var performedAt: Date = Date.now

    /// Valeur mesurée, quand l'opération en produit une.
    var measuredValue: Double?

    /// L'établissement est-il alimenté par une ressource privée ?
    var isPrivateSupply: Bool = false

    var isCompliant: Bool = true

    /// Suite donnée en cas d'anomalie.
    var correctiveAction: String = ""

    var nextDueDate: Date?

    @Attribute(.externalStorage) var documentData: Data?

    var operatorName: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    init(
        kind: WaterCheckKind = .chlorine,
        location: String = "",
        performedAt: Date = .now,
        measuredValue: Double? = nil,
        isPrivateSupply: Bool = false,
        isCompliant: Bool = true,
        correctiveAction: String = "",
        nextDueDate: Date? = nil,
        documentData: Data? = nil,
        operatorName: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.kindRawValue = kind.rawValue
        self.location = location
        self.performedAt = performedAt
        self.measuredValue = measuredValue
        self.isPrivateSupply = isPrivateSupply
        self.isCompliant = isCompliant
        self.correctiveAction = correctiveAction
        self.nextDueDate = nextDueDate
        self.documentData = documentData
        self.operatorName = operatorName
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var kind: WaterCheckKind {
        get { WaterCheckKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var displayName: String {
        location.isEmpty ? kind.label : "\(kind.label) — \(location)"
    }

    var formattedValue: String {
        guard let measuredValue else { return "—" }
        let number = measuredValue.formatted(
            .number.precision(.fractionLength(0...2)).locale(AppFormatters.locale)
        )
        return kind.unit.isEmpty ? number : "\(number) \(kind.unit)"
    }

    private var hasCorrectiveAction: Bool {
        !correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let nextDueDate else { return false }
        return calendar.startOfDay(for: nextDueDate) < calendar.startOfDay(for: reference)
    }

    var needsAction: Bool {
        (!isCompliant && !hasCorrectiveAction) || isOverdue()
    }

    var statusLabel: String {
        if !isCompliant && !hasCorrectiveAction { return "Suite à écrire" }
        if isOverdue() { return "À refaire" }
        return isCompliant ? "Conforme" : "Traité"
    }
}
