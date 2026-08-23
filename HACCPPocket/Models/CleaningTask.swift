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
    case daily
    case weekly
    case monthly
    case quarterly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:     "Quotidien"
        case .weekly:    "Hebdomadaire"
        case .monthly:   "Mensuel"
        case .quarterly: "Trimestriel"
        }
    }

    var systemImage: String {
        switch self {
        case .daily:     "sun.max"
        case .weekly:    "calendar"
        case .monthly:   "calendar.badge.clock"
        case .quarterly: "calendar.badge.exclamationmark"
        }
    }

    /// Intervalle entre deux exécutions, exprimé en composantes de date.
    var interval: DateComponents {
        switch self {
        case .daily:     DateComponents(day: 1)
        case .weekly:    DateComponents(day: 7)
        case .monthly:   DateComponents(month: 1)
        case .quarterly: DateComponents(month: 3)
        }
    }

    /// Ordre d'affichage : du plus fréquent au plus rare.
    var sortWeight: Int {
        switch self {
        case .daily:     0
        case .weekly:    1
        case .monthly:   2
        case .quarterly: 3
        }
    }
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
        isActive: Bool = true,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.title = title
        self.frequencyRawValue = frequency.rawValue
        self.zone = zone
        self.productUsed = productUsed
        self.procedure = procedure
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

    /// A-t-elle déjà été cochée aujourd'hui ? (cas des tâches quotidiennes)
    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        records.contains { calendar.isDate($0.completedAt, inSameDayAs: day) }
    }

    /// Exécutions comprises dans une période, pour le PDF mensuel.
    func records(from start: Date, to end: Date) -> [CleaningRecord] {
        records
            .filter { $0.completedAt >= start && $0.completedAt <= end }
            .sorted { $0.completedAt > $1.completedAt }
    }
}
