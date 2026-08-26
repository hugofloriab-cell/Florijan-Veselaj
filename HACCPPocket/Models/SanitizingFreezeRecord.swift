//
//  SanitizingFreezeRecord.swift
//  HACCPPocket
//
//  Traitement assainissant par le froid, pour le poisson servi cru.
//
//  Un poisson destiné à être consommé cru — tartare, carpaccio, sushi,
//  marinade, fumage à froid — doit subir une congélation assainissante qui
//  détruit les larves d'anisakis. Ce n'est pas une précaution : c'est une
//  obligation, et c'est l'un des premiers points vérifiés dès qu'un
//  établissement affiche du poisson cru à sa carte.
//
//  Deux barèmes sont admis : −20 °C pendant au moins 24 heures, ou −35 °C
//  pendant au moins 15 heures, mesurés au cœur du produit.
//

import Foundation
import SwiftData

// MARK: - Barème

enum SanitizingSchedule: String, Codable, CaseIterable, Identifiable, Sendable {
    case minus20
    case minus35

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minus20: "−20 °C pendant 24 h"
        case .minus35: "−35 °C pendant 15 h"
        }
    }

    /// Température maximale admise au cœur du produit.
    var targetTemperature: Double {
        switch self {
        case .minus20: -20
        case .minus35: -35
        }
    }

    /// Durée minimale du traitement.
    var minimumDuration: TimeInterval {
        switch self {
        case .minus20: 24 * 3600
        case .minus35: 15 * 3600
        }
    }

    var detail: String {
        switch self {
        case .minus20:
            "Le barème le plus courant, réalisable dans un congélateur professionnel."
        case .minus35:
            "Barème rapide, réservé aux cellules de surgélation. Peu d'établissements en disposent."
        }
    }
}

// MARK: - Enregistrement

@Model
final class SanitizingFreezeRecord {

    var productName: String = ""
    var batchNumber: String = ""
    var supplier: String = ""

    /// Destination du produit : tartare, sushi, carpaccio, fumage à froid.
    var intendedUse: String = ""

    var scheduleRawValue: String = SanitizingSchedule.minus20.rawValue

    var startedAt: Date = Date.now
    var finishedAt: Date?

    /// Température relevée au cœur, en fin de traitement.
    var coreTemperature: Double?

    var equipmentName: String = ""
    var quantity: String = ""
    var operatorName: String = ""
    var comment: String = ""

    /// Conformité tranchée à la clôture : durée tenue et température atteinte.
    var isCompliant: Bool = true

    var createdAt: Date = Date.now

    init(
        productName: String = "",
        batchNumber: String = "",
        supplier: String = "",
        intendedUse: String = "",
        schedule: SanitizingSchedule = .minus20,
        startedAt: Date = .now,
        equipmentName: String = "",
        quantity: String = "",
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.productName = productName
        self.batchNumber = batchNumber
        self.supplier = supplier
        self.intendedUse = intendedUse
        self.scheduleRawValue = schedule.rawValue
        self.startedAt = startedAt
        self.finishedAt = nil
        self.coreTemperature = nil
        self.equipmentName = equipmentName
        self.quantity = quantity
        self.operatorName = operatorName
        self.comment = comment
        self.isCompliant = true
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var schedule: SanitizingSchedule {
        get { SanitizingSchedule(rawValue: scheduleRawValue) ?? .minus20 }
        set { scheduleRawValue = newValue.rawValue }
    }

    var isFinished: Bool { finishedAt != nil }

    var displayName: String {
        productName.isEmpty ? "Produit sans nom" : productName
    }

    // MARK: - Durée

    func duration(at reference: Date = .now) -> TimeInterval {
        (finishedAt ?? reference).timeIntervalSince(startedAt)
    }

    /// Temps restant avant d'atteindre la durée minimale. Négatif une fois
    /// le barème tenu — et c'est le seul cas où l'on peut clôturer.
    func remainingTime(at reference: Date = .now) -> TimeInterval {
        schedule.minimumDuration - duration(at: reference)
    }

    func isScheduleMet(at reference: Date = .now) -> Bool {
        duration(at: reference) >= schedule.minimumDuration
    }

    /// Ex. « 18 h 30 »
    func formattedDuration(at reference: Date = .now) -> String {
        let total = Int(max(0, duration(at: reference)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    func timeProgress(at reference: Date = .now) -> Double {
        guard schedule.minimumDuration > 0 else { return 0 }
        return min(1, max(0, duration(at: reference) / schedule.minimumDuration))
    }

    // MARK: - Clôture

    func finish(at date: Date = .now, coreTemperature: Double?) {
        self.finishedAt = date
        self.coreTemperature = coreTemperature
        recomputeCompliance()
    }

    func recomputeCompliance() {
        guard let finishedAt else {
            isCompliant = true
            return
        }

        let heldLongEnough = finishedAt.timeIntervalSince(startedAt) >= schedule.minimumDuration
        let reachedTarget = (coreTemperature ?? 0) <= schedule.targetTemperature

        isCompliant = heldLongEnough && reachedTarget
    }

    /// Ce qui a échoué, pour l'écrire au registre plutôt que de laisser un
    /// simple « non conforme ».
    var failureReason: String? {
        guard isFinished, !isCompliant else { return nil }

        var reasons: [String] = []
        if !isScheduleMet() {
            reasons.append("durée de \(formattedDuration()) inférieure au barème")
        }
        if let coreTemperature, coreTemperature > schedule.targetTemperature {
            reasons.append("température à cœur de \(AppFormatters.temperature(coreTemperature)) au-dessus de la cible")
        }
        if coreTemperature == nil {
            reasons.append("température à cœur non relevée")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: ", ")
    }

    var statusLabel: String {
        if !isFinished { return isScheduleMet() ? "Barème atteint" : "En cours" }
        return isCompliant ? "Conforme" : "Non conforme"
    }
}
