//
//  Equipment.swift
//  HACCPPocket
//
//  Équipement soumis à un contrôle de température (enceinte froide, vitrine,
//  maintien au chaud...). C'est le pivot du relevé quotidien.
//

import Foundation
import SwiftData

// MARK: - Type d'équipement

enum EquipmentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case positiveCold   // Armoire / frigo positif
    case negativeCold   // Congélateur
    case coldRoom       // Chambre froide
    case displayCase    // Vitrine réfrigérée
    case blastChiller   // Cellule de refroidissement rapide
    case hotHolding     // Maintien au chaud (bain-marie, étuve)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .positiveCold:  "Enceinte positive"
        case .negativeCold:  "Congélateur"
        case .coldRoom:      "Chambre froide"
        case .displayCase:   "Vitrine réfrigérée"
        case .blastChiller:  "Cellule de refroidissement"
        case .hotHolding:    "Maintien au chaud"
        }
    }

    var systemImage: String {
        switch self {
        case .positiveCold:  "refrigerator"
        case .negativeCold:  "snowflake"
        case .coldRoom:      "door.left.hand.closed"
        case .displayCase:   "rectangle.split.3x1"
        case .blastChiller:  "wind.snow"
        case .hotHolding:    "flame"
        }
    }

    /// Plage de température recommandée (°C), proposée par défaut à la création.
    /// L'utilisateur reste libre de l'ajuster selon ses propres procédures.
    var recommendedRange: ClosedRange<Double> {
        switch self {
        case .positiveCold:  0...4
        case .negativeCold:  (-24)...(-18)
        case .coldRoom:      0...4
        case .displayCase:   0...4
        case .blastChiller:  (-20)...10
        case .hotHolding:    63...90
        }
    }

    /// Nombre de relevés attendus par jour pour ce type d'équipement.
    var expectedReadingsPerDay: Int {
        switch self {
        case .blastChiller: 0   // Relevé ponctuel, uniquement lors d'un usage
        default:            2   // Matin + soir
        }
    }
}

// MARK: - Modèle

@Model
final class Equipment {

    var name: String = ""

    /// Le type est persisté sous forme de `String` : sur iOS 17, `#Predicate`
    /// ne sait pas comparer un enum stocké. On garde la valeur brute filtrable
    /// et on expose l'enum via une propriété calculée.
    var typeRawValue: String = ""

    /// Emplacement physique (cuisine, réserve, laboratoire...).
    var location: String = ""

    var minTemperature: Double = 0
    var maxTemperature: Double = 0

    /// Ordre d'affichage dans la liste des relevés.
    var sortIndex: Int = 0

    /// Archivage doux : on ne supprime jamais un équipement qui possède un
    /// historique, la réglementation impose de conserver les enregistrements.
    var isActive: Bool = true

    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TemperatureReading.equipment)
    var readings: [TemperatureReading] = []

    init(
        name: String,
        type: EquipmentType,
        location: String = "",
        minTemperature: Double? = nil,
        maxTemperature: Double? = nil,
        sortIndex: Int = 0,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.name = name
        self.typeRawValue = type.rawValue
        self.location = location
        self.minTemperature = minTemperature ?? type.recommendedRange.lowerBound
        self.maxTemperature = maxTemperature ?? type.recommendedRange.upperBound
        self.sortIndex = sortIndex
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension Equipment {

    var type: EquipmentType {
        get { EquipmentType(rawValue: typeRawValue) ?? .positiveCold }
        set { typeRawValue = newValue.rawValue }
    }

    /// Plage acceptée, toujours ordonnée même si l'utilisateur saisit min > max.
    var acceptedRange: ClosedRange<Double> {
        let lower = Swift.min(minTemperature, maxTemperature)
        let upper = Swift.max(minTemperature, maxTemperature)
        return lower...upper
    }

    func isWithinRange(_ value: Double) -> Bool {
        acceptedRange.contains(value)
    }

    /// Ex. « 0,0 °C à 4,0 °C »
    var formattedRange: String {
        AppFormatters.range(acceptedRange)
    }

    var latestReading: TemperatureReading? {
        readings.max { $0.recordedAt < $1.recordedAt }
    }

    /// Relevés d'un jour donné, du plus récent au plus ancien.
    func readings(on day: Date, calendar: Calendar = .current) -> [TemperatureReading] {
        readings
            .filter { calendar.isDate($0.recordedAt, inSameDayAs: day) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Indique si le relevé attendu à ce moment de la journée a déjà été saisi.
    func hasReading(on day: Date, moment: ReadingMoment, calendar: Calendar = .current) -> Bool {
        readings(on: day, calendar: calendar).contains { $0.moment == moment }
    }

    /// Moments de la journée encore à saisir : c'est ce qui alimente le tableau
    /// de bord « il vous reste 2 relevés à faire aujourd'hui ».
    func pendingMoments(on day: Date, calendar: Calendar = .current) -> [ReadingMoment] {
        guard isActive, type.expectedReadingsPerDay > 0 else { return [] }
        return ReadingMoment.dailyRoutine.filter { !hasReading(on: day, moment: $0, calendar: calendar) }
    }

    /// Nombre de non-conformités sur une période, pour les statistiques mensuelles.
    func nonCompliantCount(since date: Date) -> Int {
        readings.filter { $0.recordedAt >= date && !$0.isCompliant }.count
    }
}
