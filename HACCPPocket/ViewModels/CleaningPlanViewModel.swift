//
//  CleaningPlanViewModel.swift
//  HACCPPocket
//
//  Plan de nettoyage : regroupement par fréquence, validation d'une opération
//  et correction d'un pointage erroné.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CleaningPlanViewModel {

    /// Une fréquence et les tâches qu'elle contient, pour les sections de liste.
    struct Section: Identifiable {
        let frequency: CleaningFrequency
        let tasks: [CleaningTask]

        var id: String { frequency.rawValue }
    }

    private let modelContext: ModelContext

    var operatorName: String
    var showsCompletedTasks: Bool = true

    private(set) var errorMessage: String?

    init(context: ModelContext, preferences: UserPreferences? = nil) {
        self.modelContext = context
        self.operatorName = (preferences ?? UserPreferences.shared).operatorName
    }

    // MARK: - Présentation

    /// Découpe les tâches actives en sections ordonnées du quotidien au trimestriel.
    func sections(
        from tasks: [CleaningTask],
        at reference: Date = .now,
        calendar: Calendar = .current
    ) -> [Section] {
        let visible = tasks
            .filter(\.isActive)
            .filter { showsCompletedTasks || !$0.isCompleted(on: reference, calendar: calendar) }

        return CleaningFrequency.allCases
            .sorted { $0.sortWeight < $1.sortWeight }
            .compactMap { frequency in
                let matching = visible
                    .filter { $0.frequency == frequency }
                    .sorted { $0.sortIndex < $1.sortIndex }
                return matching.isEmpty ? nil : Section(frequency: frequency, tasks: matching)
            }
    }

    /// Nombre de tâches encore à faire à la date de référence.
    func remainingCount(
        from tasks: [CleaningTask],
        at reference: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        tasks.filter { $0.isDue(at: reference, calendar: calendar) }.count
    }

    /// Libellé d'échéance affiché sous chaque tâche.
    func dueLabel(
        for task: CleaningTask,
        at reference: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if task.isCompleted(on: reference, calendar: calendar) {
            return "Fait aujourd'hui"
        }
        if task.isOverdue(at: reference, calendar: calendar) {
            return "En retard"
        }
        if task.isDue(at: reference, calendar: calendar) {
            return "À faire"
        }
        guard let next = task.nextDueDate(calendar: calendar) else { return "À faire" }
        return "Prochaine échéance le \(AppFormatters.shortDate(next))"
    }

    // MARK: - Actions

    /// Enregistre l'exécution d'une opération de nettoyage.
    @discardableResult
    func complete(
        _ task: CleaningTask,
        comment: String = "",
        productUsed: String? = nil,
        photoData: Data? = nil,
        at date: Date = .now
    ) -> Bool {
        let record = CleaningRecord(
            task: task,
            completedAt: date,
            operatorName: operatorName.trimmingCharacters(in: .whitespacesAndNewlines),
            productUsed: productUsed,
            comment: comment,
            photoData: photoData
        )
        modelContext.insert(record)
        return persist()
    }

    /// Annule le pointage du jour, en cas de clic par erreur.
    @discardableResult
    func undoCompletion(
        for task: CleaningTask,
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let todayRecords = task.records.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
        guard !todayRecords.isEmpty else { return false }

        todayRecords.forEach { modelContext.delete($0) }
        return persist()
    }

    /// Archive une ligne du plan de nettoyage sans détruire son historique.
    func archive(_ task: CleaningTask) {
        task.isActive = false
        _ = persist()
    }

    func restore(_ task: CleaningTask) {
        task.isActive = true
        _ = persist()
    }

    /// Suppression définitive, y compris l'historique d'exécution : à réserver
    /// à une ligne créée par erreur. Pour retirer une opération du plan sans
    /// perdre ses preuves, utiliser `archive(_:)`.
    func delete(_ task: CleaningTask) {
        modelContext.delete(task)
        _ = persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try modelContext.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
            return false
        }
    }
}
