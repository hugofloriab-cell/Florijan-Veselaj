//
//  EquipmentMaintenance.swift
//  HACCPPocket
//
//  Carnet d'entretien du matériel et étalonnage des sondes.
//
//  Une sonde qui ment rend faux l'ensemble du registre de températures :
//  chaque relevé consigné devient invérifiable. C'est le maillon le plus
//  discret et le plus critique de la chaîne, et presque personne ne le trace.
//
//  Le carnet sert aussi à démontrer qu'une enceinte tombée en panne a été
//  réparée, et quand.
//

import Foundation
import SwiftData

// MARK: - Nature de l'intervention

enum MaintenanceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case calibration
    case breakdown
    case preventive
    case repair
    case installation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calibration:  "Étalonnage"
        case .breakdown:    "Panne"
        case .preventive:   "Entretien préventif"
        case .repair:       "Réparation"
        case .installation: "Mise en service"
        }
    }

    var systemImage: String {
        switch self {
        case .calibration:  "thermometer.variable"
        case .breakdown:    "bolt.trianglebadge.exclamationmark"
        case .preventive:   "wrench.and.screwdriver"
        case .repair:       "hammer"
        case .installation: "shippingbox"
        }
    }

    /// Seul l'étalonnage compare une mesure à une référence.
    var isCalibration: Bool { self == .calibration }
}

// MARK: - Intervention

@Model
final class EquipmentMaintenance {

    /// Matériel concerné, saisi librement : une sonde ou un lave-vaisselle ne
    /// sont pas des enceintes du registre de températures.
    var equipmentName: String = ""

    var kindRawValue: String = MaintenanceKind.calibration.rawValue

    var occurredAt: Date = Date.now

    /// Prestataire, ou « interne ».
    var provider: String = ""

    /// Ce qui a été constaté.
    var observation: String = ""

    /// Ce qui a été fait.
    var actionTaken: String = ""

    // MARK: Étalonnage

    /// Référence utilisée : eau glacée à 0 °C, eau bouillante, étalon.
    var calibrationReference: String = ""

    /// Valeur attendue de la référence.
    var expectedValue: Double?

    /// Valeur lue sur l'appareil contrôlé.
    var measuredValue: Double?

    // MARK: Suite

    /// Prochaine échéance : contrat d'entretien, prochain étalonnage.
    var nextDueDate: Date?

    /// L'intervention a-t-elle clos le problème ?
    var isResolved: Bool = true

    /// Rapport d'intervention ou facture.
    @Attribute(.externalStorage) var documentData: Data?

    var operatorName: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    /// Écart au-delà duquel une sonde n'est plus fiable.
    static let acceptableDeviation: Double = 0.5

    init(
        equipmentName: String = "",
        kind: MaintenanceKind = .calibration,
        occurredAt: Date = .now,
        provider: String = "",
        observation: String = "",
        actionTaken: String = "",
        calibrationReference: String = "",
        expectedValue: Double? = nil,
        measuredValue: Double? = nil,
        nextDueDate: Date? = nil,
        isResolved: Bool = true,
        documentData: Data? = nil,
        operatorName: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.equipmentName = equipmentName
        self.kindRawValue = kind.rawValue
        self.occurredAt = occurredAt
        self.provider = provider
        self.observation = observation
        self.actionTaken = actionTaken
        self.calibrationReference = calibrationReference
        self.expectedValue = expectedValue
        self.measuredValue = measuredValue
        self.nextDueDate = nextDueDate
        self.isResolved = isResolved
        self.documentData = documentData
        self.operatorName = operatorName
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var kind: MaintenanceKind {
        get { MaintenanceKind(rawValue: kindRawValue) ?? .preventive }
        set { kindRawValue = newValue.rawValue }
    }

    var displayName: String {
        equipmentName.isEmpty ? "Matériel non précisé" : equipmentName
    }

    var hasDocument: Bool { documentData != nil }

    // MARK: - Étalonnage

    /// Écart entre la valeur lue et la référence.
    var deviation: Double? {
        guard let expectedValue, let measuredValue else { return nil }
        return measuredValue - expectedValue
    }

    /// Une sonde qui s'écarte de plus d'un demi-degré doit être ajustée ou
    /// remplacée : au-delà, elle fausse les décisions qu'on prend avec elle.
    var isCalibrationAcceptable: Bool? {
        guard let deviation else { return nil }
        return abs(deviation) <= EquipmentMaintenance.acceptableDeviation
    }

    // MARK: - Échéances

    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let nextDueDate else { return false }
        return calendar.startOfDay(for: nextDueDate) < calendar.startOfDay(for: reference)
    }

    var needsAction: Bool {
        if !isResolved { return true }
        if isOverdue() { return true }
        if kind.isCalibration, isCalibrationAcceptable == false { return true }
        return false
    }

    var statusLabel: String {
        if !isResolved { return "En cours" }
        if isOverdue() { return "Échéance dépassée" }
        if kind.isCalibration {
            guard let acceptable = isCalibrationAcceptable else { return "Sans mesure" }
            return acceptable ? "Sonde conforme" : "Sonde à régler"
        }
        return "Terminé"
    }
}
