//
//  StaffTraining.swift
//  HACCPPocket
//
//  Formations du personnel à l'hygiène alimentaire. Au moins une personne de
//  l'établissement doit justifier d'une formation, et l'attestation est
//  réclamée en contrôle.
//

import Foundation
import SwiftData

@Model
final class StaffTraining {

    var personName: String

    /// Intitulé, par exemple « Hygiène alimentaire — 14 heures ».
    var title: String

    var organisation: String

    var completedAt: Date

    /// Certaines formations doivent être renouvelées ; laisser vide sinon.
    var expiresAt: Date?

    /// Photo ou scan de l'attestation.
    @Attribute(.externalStorage) var certificateData: Data?

    var notes: String
    var createdAt: Date

    init(
        personName: String,
        title: String = "Hygiène alimentaire",
        organisation: String = "",
        completedAt: Date = .now,
        expiresAt: Date? = nil,
        certificateData: Data? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.personName = personName
        self.title = title
        self.organisation = organisation
        self.completedAt = completedAt
        self.expiresAt = expiresAt
        self.certificateData = certificateData
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension StaffTraining {

    func isExpired(at reference: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < reference
    }

    func daysUntilExpiry(from reference: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let expiresAt else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: expiresAt)
        ).day
    }

    /// Signalée trois mois avant l'échéance : le temps de replanifier une session.
    func isExpiringSoon(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let days = daysUntilExpiry(from: reference, calendar: calendar) else { return false }
        return days >= 0 && days <= 90
    }

    var statusLabel: String {
        if isExpired() { return "À renouveler" }
        if isExpiringSoon() { return "Expire bientôt" }
        return expiresAt == nil ? "Sans échéance" : "Valide"
    }

    var hasCertificate: Bool { certificateData != nil }
}
