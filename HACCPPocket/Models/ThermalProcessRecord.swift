//
//  ThermalProcessRecord.swift
//  HACCPPocket
//
//  Refroidissement rapide, congélation et remise en température.
//
//  Les trois opérations sont le même processus : amener un produit d'une
//  température à une autre, dans un temps limité, avec des relevés
//  intermédiaires. Un seul modèle les couvre donc, ce qui évite de dupliquer
//  toute la logique de conformité.
//

import Foundation
import SwiftData

// MARK: - Nature du processus

enum ThermalProcessKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// +63 °C vers +10 °C en moins de deux heures.
    case cooling
    /// Descente à −18 °C à cœur, sur un produit déjà refroidi.
    case freezing
    /// Retour à +63 °C à cœur en moins d'une heure.
    case reheating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cooling:   "Refroidissement rapide"
        case .freezing:  "Congélation"
        case .reheating: "Remise en température"
        }
    }

    var shortLabel: String {
        switch self {
        case .cooling:   "Refroidissement"
        case .freezing:  "Congélation"
        case .reheating: "Remise en temp."
        }
    }

    var systemImage: String {
        switch self {
        case .cooling:   "snowflake.circle"
        case .freezing:  "thermometer.snowflake"
        case .reheating: "flame.circle"
        }
    }

    /// Température à atteindre pour que l'opération soit conforme.
    var targetTemperature: Double {
        switch self {
        case .cooling:   10
        case .freezing:  -18
        case .reheating: 63
        }
    }

    /// Durée maximale admise, en secondes.
    ///
    /// ⚠️ Les deux heures du refroidissement et l'heure de la remise en
    /// température sont des seuils réglementaires. Les quatre heures et demie
    /// de la congélation ne le sont PAS : le texte impose d'atteindre −18 °C
    /// à cœur et de congeler rapidement, sans fixer de durée. La valeur est
    /// celle d'une cellule de congélation rapide, retenue comme garde-fou
    /// pour que le chronomètre serve à quelque chose. L'écran le dit
    /// explicitement, plutôt que de laisser croire à une obligation.
    var maximumDuration: TimeInterval {
        switch self {
        case .cooling:   2 * 3600
        case .freezing:  4 * 3600 + 30 * 60
        case .reheating: 1 * 3600
        }
    }

    /// Le refroidissement et la congélation descendent, la remise en
    /// température monte.
    var isDescending: Bool { self != .reheating }

    /// La durée affichée est-elle un seuil opposable ?
    ///
    /// Dépasser deux heures sur un refroidissement est une non-conformité.
    /// Dépasser quatre heures et demie sur une congélation est un signal,
    /// pas une infraction — et l'écran ne doit pas dire le contraire.
    var hasRegulatoryDuration: Bool { self != .freezing }

    var requirement: String {
        switch self {
        case .cooling:
            "De +63 °C à +10 °C à cœur en moins de 2 heures."
        case .freezing:
            "Descente à −18 °C à cœur, sur un produit déjà refroidi."
        case .reheating:
            "Retour à +63 °C à cœur en moins d'une heure."
        }
    }

    var startTemperatureHint: Double {
        switch self {
        case .cooling:   63
        case .freezing:  4
        case .reheating: 8
        }
    }
}

// MARK: - Relevé intermédiaire

@Model
final class ThermalCheckpoint {

    var recordedAt: Date = Date.now
    var temperature: Double = 0

    var record: ThermalProcessRecord?

    init(temperature: Double, recordedAt: Date = .now, record: ThermalProcessRecord? = nil) {
        self.temperature = temperature
        self.recordedAt = recordedAt
        self.record = record
    }
}

// MARK: - Opération

@Model
final class ThermalProcessRecord {

    var kindRawValue: String = ""

    var productName: String = ""
    var batchNumber: String = ""

    var startedAt: Date = Date.now
    var startTemperature: Double = 0

    /// `nil` tant que l'opération est en cours.
    var finishedAt: Date?
    var endTemperature: Double?

    /// Seuils figés au moment de la saisie : si la réglementation ou nos
    /// valeurs par défaut changent, l'historique reste jugé sur les règles
    /// en vigueur ce jour-là.
    var targetTemperature: Double = 0
    var maximumDurationSeconds: Double = 0

    var operatorName: String = ""
    var comment: String = ""
    var correctiveAction: String = ""

    /// Stockée plutôt que calculée, pour rester filtrable par `#Predicate`.
    var isCompliant: Bool = true

    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ThermalCheckpoint.record)
    var checkpoints: [ThermalCheckpoint] = []

    init(
        kind: ThermalProcessKind,
        productName: String,
        startTemperature: Double,
        batchNumber: String = "",
        operatorName: String = "",
        startedAt: Date = .now,
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.kindRawValue = kind.rawValue
        self.productName = productName
        self.startTemperature = startTemperature
        self.batchNumber = batchNumber
        self.operatorName = operatorName
        self.startedAt = startedAt
        self.comment = comment
        self.correctiveAction = ""
        self.targetTemperature = kind.targetTemperature
        self.maximumDurationSeconds = kind.maximumDuration
        self.finishedAt = nil
        self.endTemperature = nil
        // Une opération en cours n'est pas encore jugée : on la considère
        // conforme jusqu'à preuve du contraire, la clôture tranchera.
        self.isCompliant = true
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension ThermalProcessRecord {

    var kind: ThermalProcessKind {
        get { ThermalProcessKind(rawValue: kindRawValue) ?? .cooling }
        set { kindRawValue = newValue.rawValue }
    }

    var isFinished: Bool { finishedAt != nil }

    /// Durée écoulée, ou durée totale si l'opération est close.
    func duration(at reference: Date = .now) -> TimeInterval {
        (finishedAt ?? reference).timeIntervalSince(startedAt)
    }

    /// Temps restant avant de dépasser la limite réglementaire. Négatif au-delà.
    func remainingTime(at reference: Date = .now) -> TimeInterval {
        maximumDurationSeconds - duration(at: reference)
    }

    func isOverdue(at reference: Date = .now) -> Bool {
        remainingTime(at: reference) < 0
    }

    /// Ex. « 1 h 12 »
    func formattedDuration(at reference: Date = .now) -> String {
        let total = Int(max(0, duration(at: reference)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    /// Avancement de 0 à 1 dans le temps imparti.
    func timeProgress(at reference: Date = .now) -> Double {
        guard maximumDurationSeconds > 0 else { return 0 }
        return min(1, max(0, duration(at: reference) / maximumDurationSeconds))
    }

    /// Le dernier relevé connu, intermédiaire ou final.
    var lastTemperature: Double? {
        endTemperature
            ?? checkpoints.max { $0.recordedAt < $1.recordedAt }?.temperature
            ?? startTemperature
    }

    /// La température finale atteint-elle la cible ?
    func reachesTarget(_ temperature: Double) -> Bool {
        kind.isDescending ? temperature <= targetTemperature : temperature >= targetTemperature
    }

    var sortedCheckpoints: [ThermalCheckpoint] {
        checkpoints.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// Clôture l'opération et tranche la conformité : la cible doit être
    /// atteinte, et dans le temps imparti.
    func finish(at date: Date = .now, temperature: Double) {
        finishedAt = date
        endTemperature = temperature
        recomputeCompliance()
    }

    func recomputeCompliance() {
        guard let finishedAt, let endTemperature else {
            isCompliant = true
            return
        }

        guard reachesTarget(endTemperature) else {
            isCompliant = false
            return
        }

        // La durée ne fait échouer l'opération que lorsqu'elle est opposable.
        // Une congélation longue mérite d'être signalée à l'écran, pas d'être
        // enregistrée comme une non-conformité : aucun texte ne fixe cette
        // durée, et un registre qui invente des fautes perd sa crédibilité.
        guard kind.hasRegulatoryDuration else {
            isCompliant = true
            return
        }

        isCompliant = finishedAt.timeIntervalSince(startedAt) <= maximumDurationSeconds
    }

    /// Un écart non documenté est un dossier incomplet en contrôle.
    var needsCorrectiveAction: Bool {
        isFinished && !isCompliant
            && correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Motif d'échec, pour l'afficher sans le recalculer dans chaque vue.
    var failureReason: String? {
        guard isFinished, !isCompliant, let finishedAt, let endTemperature else { return nil }

        var reasons: [String] = []
        if !reachesTarget(endTemperature) {
            reasons.append("cible de \(AppFormatters.temperature(targetTemperature)) non atteinte")
        }
        if kind.hasRegulatoryDuration,
           finishedAt.timeIntervalSince(startedAt) > maximumDurationSeconds {
            reasons.append("durée dépassée")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: ", ")
    }
}
