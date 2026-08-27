//
//  CleaningTask.swift
//  HACCPPocket
//
//  Ligne du plan de nettoyage et de désinfection : quoi nettoyer, où, à quelle
//  fréquence et avec quel produit. Les exécutions sont stockées dans
//  `CleaningRecord`.
//

import Foundation
import SwiftData

// MARK: - Fréquence

enum CleaningFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case twiceDaily
    case daily
    case weekly
    case monthly
    case quarterly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twiceDaily: "Deux fois par jour"
        case .daily:     "Quotidien"
        case .weekly:    "Hebdomadaire"
        case .monthly:   "Mensuel"
        case .quarterly: "Trimestriel"
        }
    }

    var systemImage: String {
        switch self {
        case .twiceDaily: "clock.arrow.2.circlepath"
        case .daily:     "sun.max"
        case .weekly:    "calendar"
        case .monthly:   "calendar.badge.clock"
        case .quarterly: "calendar.badge.exclamationmark"
        }
    }

    /// Intervalle entre deux exécutions, exprimé en composantes de date.
    var interval: DateComponents {
        switch self {
        case .twiceDaily: DateComponents(hour: 12)
        case .daily:     DateComponents(day: 1)
        case .weekly:    DateComponents(day: 7)
        case .monthly:   DateComponents(month: 1)
        case .quarterly: DateComponents(month: 3)
        }
    }

    /// Ordre d'affichage : du plus fréquent au plus rare.
    var sortWeight: Int {
        switch self {
        case .twiceDaily: 0
        case .daily:     1
        case .weekly:    2
        case .monthly:   3
        case .quarterly: 4
        }
    }

    /// Nombre d'exécutions attendues dans une journée. Sert à afficher
    /// « 1/2 » plutôt qu'un simple coché / pas coché.
    var occurrencesPerDay: Int {
        switch self {
        case .twiceDaily: 2
        case .daily:      1
        default:          0
        }
    }

    /// Une fréquence qui se compte dans la journée : la tâche revient avant
    /// le lendemain, l'écran doit donc pouvoir la proposer plusieurs fois.
    var isIntraday: Bool { occurrencesPerDay > 1 }
}

// MARK: - Modèle

@Model
final class CleaningTask {

    /// Intitulé de l'opération (ex. « Désinfection du plan de travail »).
    var title: String = ""

    /// Zone concernée (cuisine, plonge, sanitaires, salle...).
    var zone: String = ""

    /// Produit utilisé et dosage, exigés par le plan de nettoyage.
    var productUsed: String = ""

    /// Mode opératoire résumé, consultable au moment de cocher la tâche.
    var procedure: String = ""

    var frequencyRawValue: String = ""

    /// Une photo de l'équipement nettoyé est-elle exigée pour valider ?
    ///
    /// C'est la seule preuve qu'un nettoyage a réellement eu lieu : une case
    /// cochée ne prouve rien, une photo horodatée de la plonge propre, si.
    /// Activée par défaut sur les nouvelles lignes ; les lignes déjà créées
    /// restent telles quelles, on ne rend pas rétroactivement incomplet un
    /// plan de nettoyage qui fonctionnait.
    var requiresPhoto: Bool = false

    var isActive: Bool = true
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CleaningRecord.task)
    var records: [CleaningRecord] = []

    init(
        title: String,
        frequency: CleaningFrequency = .daily,
        zone: String = "",
        productUsed: String = "",
        procedure: String = "",
        requiresPhoto: Bool = false,
        isActive: Bool = true,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.title = title
        self.frequencyRawValue = frequency.rawValue
        self.zone = zone
        self.productUsed = productUsed
        self.procedure = procedure
        self.requiresPhoto = requiresPhoto
        self.isActive = isActive
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension CleaningTask {

    var frequency: CleaningFrequency {
        get { CleaningFrequency(rawValue: frequencyRawValue) ?? .daily }
        set { frequencyRawValue = newValue.rawValue }
    }

    var lastCompletion: CleaningRecord? {
        records.max { $0.completedAt < $1.completedAt }
    }

    var lastCompletedAt: Date? {
        lastCompletion?.completedAt
    }

    /// Date à laquelle l'opération doit être refaite. `nil` si jamais réalisée
    /// (dans ce cas la tâche est due immédiatement).
    func nextDueDate(calendar: Calendar = .current) -> Date? {
        guard let lastCompletedAt else { return nil }
        return calendar.date(byAdding: frequency.interval, to: lastCompletedAt)
    }

    /// La tâche est-elle à réaliser à la date de référence ?
    func isDue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        guard let nextDueDate = nextDueDate(calendar: calendar) else { return true }
        return nextDueDate <= reference
    }

    /// Tâche en retard : l'échéance est passée depuis plus d'une période complète.
    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isActive, let nextDueDate = nextDueDate(calendar: calendar) else { return false }
        guard let tolerance = calendar.date(byAdding: frequency.interval, to: nextDueDate) else {
            return false
        }
        return tolerance <= reference
    }

    /// Nombre d'exécutions enregistrées ce jour-là.
    func completionCount(on day: Date, calendar: Calendar = .current) -> Int {
        records.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }.count
    }

    /// La tâche est-elle soldée pour la journée ?
    ///
    /// Une ligne bi-quotidienne cochée une seule fois ne l'est pas : c'est
    /// tout l'intérêt de la fréquence. Les fréquences plus longues gardent le
    /// comportement d'avant — une exécution dans la journée suffit.
    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        let done = completionCount(on: day, calendar: calendar)
        return done >= max(1, frequency.occurrencesPerDay)
    }

    /// Reste-t-il des passages à faire aujourd'hui, et combien.
    func remainingToday(on day: Date = .now, calendar: Calendar = .current) -> Int {
        let expected = max(1, frequency.occurrencesPerDay)
        return max(0, expected - completionCount(on: day, calendar: calendar))
    }

    /// « 1/2 » pour une ligne bi-quotidienne à moitié faite. Vide pour les
    /// fréquences qui ne se comptent pas dans la journée.
    func dailyProgressLabel(on day: Date = .now, calendar: Calendar = .current) -> String? {
        guard frequency.isIntraday else { return nil }
        return "\(completionCount(on: day, calendar: calendar))/\(frequency.occurrencesPerDay)"
    }

    /// Une exécution sans photo, alors que la ligne en exige une, laisse un
    /// trou dans la preuve.
    var recordsMissingPhoto: [CleaningRecord] {
        guard requiresPhoto else { return [] }
        return records.filter { $0.photoData == nil }
    }

    /// Exécutions comprises dans une période, pour le PDF mensuel.
    func records(from start: Date, to end: Date) -> [CleaningRecord] {
        records
            .filter { $0.completedAt >= start && $0.completedAt <= end }
            .sorted { $0.completedAt > $1.completedAt }
    }
}
