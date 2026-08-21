//
//  TemperatureReading.swift
//  HACCPPocket
//
//  Un relevé de température horodaté. C'est la preuve élémentaire exigée lors
//  d'un contrôle : valeur, date, seuils applicables au moment du relevé, et
//  action corrective en cas d'écart.
//

import Foundation
import SwiftData

// MARK: - Moment du relevé

enum ReadingMoment: String, Codable, CaseIterable, Identifiable, Sendable {
    case morning    // Ouverture
    case evening    // Fermeture
    case delivery   // Contrôle ponctuel à réception
    case other      // Contrôle ponctuel

    var id: String { rawValue }

    /// Les deux relevés obligatoires de la routine quotidienne.
    static let dailyRoutine: [ReadingMoment] = [.morning, .evening]

    var label: String {
        switch self {
        case .morning:  "Matin"
        case .evening:  "Soir"
        case .delivery: "Réception"
        case .other:    "Ponctuel"
        }
    }

    var systemImage: String {
        switch self {
        case .morning:  "sunrise"
        case .evening:  "moon.stars"
        case .delivery: "shippingbox"
        case .other:    "clock"
        }
    }

    /// Moment proposé par défaut selon l'heure de saisie.
    static func suggested(for date: Date = .now, calendar: Calendar = .current) -> ReadingMoment {
        calendar.component(.hour, from: date) < 15 ? .morning : .evening
    }
}

// MARK: - Modèle

@Model
final class TemperatureReading {

    var recordedAt: Date

    /// Température relevée, en degrés Celsius.
    var value: Double

    var momentRawValue: String

    /// Personne ayant effectué le relevé (traçabilité exigée).
    var operatorName: String

    var comment: String

    /// Action corrective obligatoire dès qu'un relevé est hors plage.
    var correctiveAction: String

    /// Seuils figés au moment du relevé : si l'utilisateur modifie plus tard la
    /// plage de l'équipement, l'historique reste jugé sur les règles de l'époque.
    var thresholdMin: Double
    var thresholdMax: Double

    /// Conformité stockée (et non calculée) pour rester filtrable par `#Predicate`.
    var isCompliant: Bool

    var equipment: Equipment?

    init(
        value: Double,
        equipment: Equipment?,
        moment: ReadingMoment = .suggested(),
        operatorName: String = "",
        comment: String = "",
        correctiveAction: String = "",
        recordedAt: Date = .now
    ) {
        self.value = value
        self.equipment = equipment
        self.momentRawValue = moment.rawValue
        self.operatorName = operatorName
        self.comment = comment
        self.correctiveAction = correctiveAction
        self.recordedAt = recordedAt

        let range = equipment?.acceptedRange ?? 0...4
        self.thresholdMin = range.lowerBound
        self.thresholdMax = range.upperBound
        self.isCompliant = range.contains(value)
    }
}

// MARK: - Logique métier

extension TemperatureReading {

    var moment: ReadingMoment {
        get { ReadingMoment(rawValue: momentRawValue) ?? .other }
        set { momentRawValue = newValue.rawValue }
    }

    var appliedRange: ClosedRange<Double> {
        let lower = Swift.min(thresholdMin, thresholdMax)
        let upper = Swift.max(thresholdMin, thresholdMax)
        return lower...upper
    }

    /// Ex. « 3,5 °C »
    var formattedValue: String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) °C"
    }

    /// Écart signé par rapport à la plage (0 si conforme). Utile pour la
    /// couleur et le tri des anomalies.
    var deviation: Double {
        if value < appliedRange.lowerBound { return value - appliedRange.lowerBound }
        if value > appliedRange.upperBound { return value - appliedRange.upperBound }
        return 0
    }

    /// Un écart non conforme sans action corrective renseignée est un dossier
    /// incomplet aux yeux d'un inspecteur : on le signale dans l'app.
    var needsCorrectiveAction: Bool {
        !isCompliant && correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// À rappeler après toute modification de la valeur ou des seuils.
    func recomputeCompliance() {
        isCompliant = appliedRange.contains(value)
    }

    /// Réaligne les seuils sur la configuration actuelle de l'équipement
    /// (utilisé uniquement lors de la correction d'un relevé fraîchement saisi).
    func realignThresholds(with equipment: Equipment) {
        thresholdMin = equipment.acceptedRange.lowerBound
        thresholdMax = equipment.acceptedRange.upperBound
        recomputeCompliance()
    }
}
