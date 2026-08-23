//
//  PestControlVisit.swift
//  HACCPPocket
//
//  Registre de lutte contre les nuisibles. Le contrat avec un prestataire et
//  ses rapports de visite font partie des pièces réclamées en contrôle.
//

import Foundation
import SwiftData

@Model
final class PestControlVisit {

    var visitedAt: Date = Date.now

    var company: String = ""
    var technician: String = ""

    /// Constat du technicien : traces, captures, zones à surveiller.
    var findings: String = ""

    var baitsReplaced: Bool = true
    var deviceCount: Int = 0

    /// Mesures prises ou recommandées.
    var actionsTaken: String = ""

    var nextVisitDate: Date?

    /// Photo du rapport laissé par le prestataire.
    @Attribute(.externalStorage) var reportPhotoData: Data?

    /// Vrai si le technicien a constaté une présence de nuisibles.
    var hasInfestation: Bool = false

    var createdAt: Date = Date.now

    init(
        company: String,
        visitedAt: Date = .now,
        technician: String = "",
        findings: String = "",
        baitsReplaced: Bool = true,
        deviceCount: Int = 0,
        actionsTaken: String = "",
        nextVisitDate: Date? = nil,
        hasInfestation: Bool = false,
        reportPhotoData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.company = company
        self.visitedAt = visitedAt
        self.technician = technician
        self.findings = findings
        self.baitsReplaced = baitsReplaced
        self.deviceCount = deviceCount
        self.actionsTaken = actionsTaken
        self.nextVisitDate = nextVisitDate
        self.hasInfestation = hasInfestation
        self.reportPhotoData = reportPhotoData
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension PestControlVisit {

    /// La visite suivante est-elle en retard ?
    func isNextVisitOverdue(at reference: Date = .now) -> Bool {
        guard let nextVisitDate else { return false }
        return nextVisitDate < reference
    }

    func daysUntilNextVisit(from reference: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let nextVisitDate else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: nextVisitDate)
        ).day
    }

    /// Un constat de présence sans mesure écrite est un dossier incomplet.
    var needsAction: Bool {
        hasInfestation && actionsTaken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusLabel: String {
        hasInfestation ? "Présence constatée" : "Aucune présence"
    }
}
