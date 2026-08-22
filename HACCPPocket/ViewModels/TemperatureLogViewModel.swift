//
//  TemperatureLogViewModel.swift
//  HACCPPocket
//
//  Saisie d'un relevé de température : validation, contrôle de conformité en
//  temps réel et enregistrement. Le formulaire refuse d'enregistrer un écart
//  sans action corrective, comme l'exige un plan de maîtrise sanitaire.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TemperatureLogViewModel {

    // MARK: - Dépendances

    private let modelContext: ModelContext
    let equipment: Equipment

    /// Relevé en cours de modification. `nil` pour une nouvelle saisie.
    private let existingReading: TemperatureReading?

    // MARK: - État du formulaire

    var valueText: String
    var moment: ReadingMoment
    var recordedAt: Date
    var operatorName: String
    var comment: String
    var correctiveAction: String

    private(set) var errorMessage: String?

    // MARK: - Initialisation

    init(
        equipment: Equipment,
        reading: TemperatureReading? = nil,
        moment: ReadingMoment? = nil,
        context: ModelContext,
        preferences: UserPreferences? = nil
    ) {
        let prefs = preferences ?? UserPreferences.shared

        self.equipment = equipment
        self.existingReading = reading
        self.modelContext = context

        if let reading {
            self.valueText = reading.value.formatted(.number.precision(.fractionLength(1)).locale(AppFormatters.locale))
            self.moment = reading.moment
            self.recordedAt = reading.recordedAt
            self.operatorName = reading.operatorName
            self.comment = reading.comment
            self.correctiveAction = reading.correctiveAction
        } else {
            self.valueText = ""
            self.moment = moment ?? .suggested()
            self.recordedAt = .now
            self.operatorName = prefs.operatorName
            self.comment = ""
            self.correctiveAction = ""
        }
    }

    var isEditing: Bool { existingReading != nil }

    // MARK: - Validation en direct

    /// Valeur saisie convertie, ou `nil` si la saisie n'est pas encore un nombre.
    var value: Double? {
        AppFormatters.parseTemperature(valueText)
    }

    /// Plage attendue pour cet équipement.
    var acceptedRange: ClosedRange<Double> {
        equipment.acceptedRange
    }

    /// `nil` tant qu'aucune valeur exploitable n'est saisie.
    var isCompliant: Bool? {
        guard let value else { return nil }
        return acceptedRange.contains(value)
    }

    /// Écart par rapport à la plage, 0 si conforme.
    var deviation: Double? {
        guard let value else { return nil }
        if value < acceptedRange.lowerBound { return value - acceptedRange.lowerBound }
        if value > acceptedRange.upperBound { return value - acceptedRange.upperBound }
        return 0
    }

    /// Un écart impose une action corrective écrite.
    var requiresCorrectiveAction: Bool {
        isCompliant == false
    }

    private var hasCorrectiveAction: Bool {
        !correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Message d'aide affiché sous le champ de saisie.
    var validationHint: String? {
        guard let value else {
            return valueText.isEmpty ? nil : "Saisissez une température valide (ex. 3,5)."
        }
        if acceptedRange.contains(value) { return nil }
        if let deviation {
            return "Écart de \(AppFormatters.deviation(deviation)) par rapport à la plage \(equipment.formattedRange)."
        }
        return nil
    }

    var canSave: Bool {
        guard value != nil else { return false }
        if requiresCorrectiveAction && !hasCorrectiveAction { return false }
        return true
    }

    // MARK: - Enregistrement

    /// Enregistre le relevé. Renvoie `false` et remplit `errorMessage` en cas
    /// d'échec, pour que la vue puisse afficher une alerte.
    @discardableResult
    func save() -> Bool {
        errorMessage = nil

        guard let value else {
            errorMessage = "Température invalide."
            return false
        }

        guard !requiresCorrectiveAction || hasCorrectiveAction else {
            errorMessage = "Un relevé hors plage exige une action corrective."
            return false
        }

        let trimmedOperator = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let reading = existingReading {
            reading.value = value
            reading.moment = moment
            reading.recordedAt = recordedAt
            reading.operatorName = trimmedOperator
            reading.comment = comment
            reading.correctiveAction = correctiveAction
            reading.recomputeCompliance()
        } else {
            let reading = TemperatureReading(
                value: value,
                equipment: equipment,
                moment: moment,
                operatorName: trimmedOperator,
                comment: comment,
                correctiveAction: correctiveAction,
                recordedAt: recordedAt
            )
            modelContext.insert(reading)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
            return false
        }
    }

    /// Supprime le relevé en cours d'édition. Réservé à la correction d'une
    /// saisie erronée : l'historique réglementaire ne se purge pas.
    @discardableResult
    func deleteExisting() -> Bool {
        guard let reading = existingReading else { return false }
        modelContext.delete(reading)
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Suppression impossible : \(error.localizedDescription)"
            return false
        }
    }
}
