//
//  Establishment.swift
//  HACCPPocket
//
//  Fiche d'identité de l'établissement. Une seule instance est censée exister :
//  elle alimente l'en-tête des exports PDF présentés lors d'un contrôle DDPP.
//

import Foundation
import SwiftData

@Model
final class Establishment {

    /// Raison sociale / enseigne.
    var name: String = ""

    /// Adresse complète (multi-lignes autorisées).
    var address: String = ""

    /// Numéro SIRET, affiché sur les documents officiels.
    var siret: String = ""

    /// Nom du responsable du Plan de Maîtrise Sanitaire.
    var managerName: String = ""

    /// Numéro d'agrément sanitaire, si l'établissement en possède un.
    var approvalNumber: String = ""

    /// Logo affiché en en-tête des PDF. Stocké hors base pour ne pas alourdir le store.
    @Attribute(.externalStorage) var logoData: Data?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        name: String = "",
        address: String = "",
        siret: String = "",
        managerName: String = "",
        approvalNumber: String = "",
        logoData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.address = address
        self.siret = siret
        self.managerName = managerName
        self.approvalNumber = approvalNumber
        self.logoData = logoData
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Logique métier

extension Establishment {

    /// Nom à afficher partout dans l'app quand la fiche n'est pas encore remplie.
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Mon établissement"
            : name
    }

    /// Un export PDF n'est réellement exploitable que si ces champs sont renseignés.
    var isReadyForExport: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Champs manquants, listés dans l'écran Réglages pour guider l'utilisateur.
    var missingFields: [String] {
        var missing: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Raison sociale") }
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Adresse") }
        if managerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Responsable PMS") }
        return missing
    }

    /// À appeler après toute modification pour horodater la fiche.
    func touch(at date: Date = .now) {
        updatedAt = date
    }
}
