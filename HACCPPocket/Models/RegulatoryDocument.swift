//
//  RegulatoryDocument.swift
//  HACCPPocket
//
//  Archive documentaire : plan de maîtrise sanitaire, contrats, procédures.
//
//  Le PMS est le document qui chapeaute tout le reste : il décrit les
//  dangers, les mesures de maîtrise et les procédures de l'établissement.
//  Un contrôleur le demande en premier, et c'est souvent celui qu'on met le
//  plus de temps à retrouver — parce qu'il vit dans un classeur, une clé USB,
//  ou la boîte mail du comptable.
//

import Foundation
import SwiftData

// MARK: - Nature du document

enum DocumentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case sanitaryPlan
    case hazardAnalysis
    case flowDiagram
    case procedure
    case contract
    case certificate
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sanitaryPlan:   "Plan de maîtrise sanitaire"
        case .hazardAnalysis: "Analyse des dangers"
        case .flowDiagram:    "Diagramme de fabrication"
        case .procedure:      "Procédure interne"
        case .contract:       "Contrat de prestation"
        case .certificate:    "Attestation ou agrément"
        case .other:          "Autre document"
        }
    }

    var detail: String {
        switch self {
        case .sanitaryPlan:
            "Le document cadre : bonnes pratiques d'hygiène, plan HACCP, traçabilité et gestion des non-conformités."
        case .hazardAnalysis:
            "L'identification des dangers biologiques, chimiques et physiques, et les mesures de maîtrise retenues."
        case .flowDiagram:
            "Le parcours des denrées, de la réception au service, avec les points de contrôle."
        case .procedure:
            "Les modes opératoires écrits de l'établissement."
        case .contract:
            "Nuisibles, collecte des huiles, maintenance, blanchisserie, laboratoire."
        case .certificate:
            "Agrément sanitaire, attestations d'assurance, certificats de conformité du matériel."
        case .other:
            "Tout ce qui doit être retrouvé rapidement le jour d'un contrôle."
        }
    }

    var systemImage: String {
        switch self {
        case .sanitaryPlan:   "doc.text.fill"
        case .hazardAnalysis: "exclamationmark.shield"
        case .flowDiagram:    "arrow.triangle.branch"
        case .procedure:      "list.number"
        case .contract:       "signature"
        case .certificate:    "rosette"
        case .other:          "doc"
        }
    }

    /// Ordre d'affichage : le PMS d'abord, c'est lui qu'on cherche.
    var sortWeight: Int {
        switch self {
        case .sanitaryPlan:   0
        case .hazardAnalysis: 1
        case .flowDiagram:    2
        case .procedure:      3
        case .contract:       4
        case .certificate:    5
        case .other:          6
        }
    }
}

// MARK: - Document

@Model
final class RegulatoryDocument {

    var title: String = ""
    var categoryRawValue: String = DocumentCategory.sanitaryPlan.rawValue

    /// Qui a établi ou délivré le document.
    var issuer: String = ""

    var issuedAt: Date = Date.now

    /// Échéance, pour les contrats et attestations qui se renouvellent.
    var expiresAt: Date?

    /// Référence, numéro de contrat, version.
    var reference: String = ""

    /// Le document lui-même, photographié ou importé.
    @Attribute(.externalStorage) var fileData: Data?

    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Délai d'alerte avant échéance.
    static let warningDays = 45

    init(
        title: String = "",
        category: DocumentCategory = .sanitaryPlan,
        issuer: String = "",
        issuedAt: Date = .now,
        expiresAt: Date? = nil,
        reference: String = "",
        fileData: Data? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.title = title
        self.categoryRawValue = category.rawValue
        self.issuer = issuer
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.reference = reference
        self.fileData = fileData
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: - Accès typé

    var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var displayName: String {
        title.isEmpty ? category.label : title
    }

    var hasFile: Bool { fileData != nil }

    // MARK: - Échéances

    func isExpired(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let expiresAt else { return false }
        return calendar.startOfDay(for: expiresAt) < calendar.startOfDay(for: reference)
    }

    func isExpiringSoon(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let expiresAt, !isExpired(at: reference, calendar: calendar) else { return false }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: expiresAt)
        ).day ?? 0
        return days <= RegulatoryDocument.warningDays
    }

    /// Un document archivé sans fichier joint ne sert à rien : c'est une
    /// ligne dans une liste, pas une preuve.
    var isIncomplete: Bool { !hasFile }

    var needsAction: Bool {
        isExpired() || isExpiringSoon() || isIncomplete
    }

    var statusLabel: String {
        if isExpired() { return "Expiré" }
        if isExpiringSoon() { return "À renouveler" }
        if isIncomplete { return "Sans pièce jointe" }
        return "À jour"
    }

    func touch(at date: Date = .now) {
        updatedAt = date
    }
}
