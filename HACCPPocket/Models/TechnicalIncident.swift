//
//  TechnicalIncident.swift
//  HACCPPocket
//
//  Déclaration d'une panne : technique, informatique, électrique, mécanique.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE REGISTRE EXISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Une chambre froide qui remonte, une hotte qui s'arrête, un lave-vaisselle
//  qui ne monte plus à température : ces pannes ont toutes une conséquence
//  sanitaire, et elles se signalent aujourd'hui par un message oral en fin de
//  service, qui se perd.
//
//  Ce que la déclaration change : elle date l'incident, nomme qui l'a
//  constaté, décrit ce qui a été fait en attendant, et part par courriel à la
//  personne qui peut agir. En cas de contrôle, elle montre que la panne a été
//  vue et traitée — ce qui fait toute la différence entre un incident et une
//  négligence.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE L'ENVOI PAR COURRIEL EST, ET N'EST PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'application n'envoie rien elle-même : elle prépare le message et ouvre
//  la fenêtre de courrier du téléphone. C'est l'utilisateur qui appuie sur
//  « Envoyer », depuis sa propre adresse.
//
//  Ce choix n'est pas une limitation subie : envoyer directement supposerait
//  un serveur de messagerie, donc un coût mensuel et une adresse expéditrice
//  qui ne serait pas celle du restaurant. Le message part de la boîte du
//  restaurateur, atterrit dans ses messages envoyés, et le destinataire peut
//  y répondre.
//
//  Conséquence assumée : l'application ne peut pas garantir qu'un message a
//  été envoyé. Elle note donc « transmis » sur déclaration de l'utilisateur,
//  et le dit.
//

import Foundation
import SwiftData

// MARK: - Nature de la panne

enum IncidentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case refrigeration
    case electrical
    case mechanical
    case plumbing
    case computing
    case building
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .refrigeration: "Froid"
        case .electrical:    "Électricité"
        case .mechanical:    "Mécanique"
        case .plumbing:      "Plomberie"
        case .computing:     "Informatique"
        case .building:      "Bâtiment"
        case .other:         "Autre"
        }
    }

    var systemImage: String {
        switch self {
        case .refrigeration: "snowflake"
        case .electrical:    "bolt"
        case .mechanical:    "gearshape.2"
        case .plumbing:      "drop"
        case .computing:     "desktopcomputer"
        case .building:      "building.2"
        case .other:         "wrench.and.screwdriver"
        }
    }

    /// Une panne de froid met des denrées en jeu immédiatement. Les autres
    /// aussi parfois, mais celle-là toujours.
    var isFoodCritical: Bool { self == .refrigeration }

    /// Ce qu'il faut penser à préciser pour cette nature de panne.
    var reportingHint: String {
        switch self {
        case .refrigeration:
            return "Précisez l'enceinte, la température relevée, et ce que vous avez fait des denrées."
        case .electrical:
            return "Précisez ce qui ne s'allume plus et si le disjoncteur a sauté. Ne rouvrez pas un tableau vous-même."
        case .mechanical:
            return "Précisez la machine, le bruit ou le blocage constaté, et si elle a été mise hors service."
        case .plumbing:
            return "Précisez l'emplacement de la fuite et si l'arrivée d'eau a été coupée."
        case .computing:
            return "Précisez l'appareil, le message affiché, et ce qui ne fonctionne plus concrètement."
        case .building:
            return "Précisez l'emplacement : un carrelage descellé ou un joint fissuré est un point d'entrée pour les nuisibles."
        case .other:
            return "Décrivez ce qui est cassé et ce que ça empêche de faire."
        }
    }
}

// MARK: - Urgence

enum IncidentSeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case blocking
    case degraded
    case minor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocking: "Bloquant"
        case .degraded: "Gêne le service"
        case .minor:    "À planifier"
        }
    }

    var detail: String {
        switch self {
        case .blocking:
            return "Le service ne peut pas continuer en l'état, ou des denrées sont en jeu."
        case .degraded:
            return "On peut travailler, mais dans de moins bonnes conditions."
        case .minor:
            return "Rien d'urgent : à traiter à la prochaine intervention."
        }
    }

    var systemImage: String {
        switch self {
        case .blocking: "exclamationmark.octagon.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .minor:    "wrench.adjustable"
        }
    }

    var sortWeight: Int {
        switch self {
        case .blocking: 0
        case .degraded: 1
        case .minor:    2
        }
    }
}

// MARK: - Modèle

@Model
final class TechnicalIncident {

    var kindRawValue: String = IncidentKind.other.rawValue
    var severityRawValue: String = IncidentSeverity.degraded.rawValue

    /// Équipement ou emplacement concerné.
    var equipmentName: String = ""

    /// Ce qui a été constaté.
    var descriptionText: String = ""

    /// Mesure conservatoire prise en attendant l'intervention. C'est la partie
    /// qui compte en contrôle : elle montre que la panne a été gérée.
    var immediateAction: String = ""

    var reportedAt: Date = Date.now
    var reportedBy: String = ""

    /// À qui la déclaration a été adressée.
    var recipientName: String = ""
    var recipientEmail: String = ""

    /// L'utilisateur déclare avoir envoyé le message. L'application ne peut
    /// pas le vérifier — elle ouvre la fenêtre de courrier, rien de plus.
    var sentAt: Date?

    /// Résolution effective.
    var resolvedAt: Date?
    var resolutionNote: String = ""

    @Attribute(.externalStorage) var photoData: Data?

    var createdAt: Date = Date.now

    init(
        kind: IncidentKind = .other,
        severity: IncidentSeverity = .degraded,
        equipmentName: String = "",
        descriptionText: String = "",
        immediateAction: String = "",
        reportedAt: Date = .now,
        reportedBy: String = "",
        recipientName: String = "",
        recipientEmail: String = "",
        sentAt: Date? = nil,
        resolvedAt: Date? = nil,
        resolutionNote: String = "",
        photoData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.kindRawValue = kind.rawValue
        self.severityRawValue = severity.rawValue
        self.equipmentName = equipmentName
        self.descriptionText = descriptionText
        self.immediateAction = immediateAction
        self.reportedAt = reportedAt
        self.reportedBy = reportedBy
        self.recipientName = recipientName
        self.recipientEmail = recipientEmail
        self.sentAt = sentAt
        self.resolvedAt = resolvedAt
        self.resolutionNote = resolutionNote
        self.photoData = photoData
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension TechnicalIncident {

    var kind: IncidentKind {
        get { IncidentKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var severity: IncidentSeverity {
        get { IncidentSeverity(rawValue: severityRawValue) ?? .degraded }
        set { severityRawValue = newValue.rawValue }
    }

    var displayName: String {
        equipmentName.isEmpty ? kind.label : equipmentName
    }

    var isResolved: Bool { resolvedAt != nil }
    var isSent: Bool { sentAt != nil }
    var hasPhoto: Bool { photoData != nil }

    /// Une panne déclarée mais jamais transmise dort dans le téléphone.
    var needsSending: Bool { !isResolved && !isSent }

    /// Nombre de jours depuis la déclaration, pour signaler ce qui traîne.
    func daysOpen(at reference: Date = .now, calendar: Calendar = .current) -> Int {
        guard !isResolved else { return 0 }
        let from = calendar.startOfDay(for: reportedAt)
        let to = calendar.startOfDay(for: reference)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    var needsAction: Bool {
        !isResolved
    }

    var statusLabel: String {
        if isResolved { return "Résolu" }
        if !isSent { return "À transmettre" }

        let days = daysOpen()
        if days == 0 { return "Transmis aujourd'hui" }
        return days == 1 ? "Ouvert depuis 1 jour" : "Ouvert depuis \(days) jours"
    }

    /// Objet du courriel.
    var mailSubject: String {
        "[\(severity.label)] \(kind.label) — \(displayName)"
    }

    /// Corps du courriel, prêt à partir.
    ///
    /// Construit ligne par ligne : une concaténation de dix termes optionnels
    /// est exactement le genre d'expression que le compilateur met un temps
    /// déraisonnable à résoudre.
    func mailBody(establishment: Establishment?) -> String {
        var lines: [String] = []

        if let name = establishment?.name, !name.isEmpty {
            lines.append(name)
            if let address = establishment?.address, !address.isEmpty {
                lines.append(address)
            }
            lines.append("")
        }

        lines.append("Déclaration d'incident technique")
        lines.append("")
        lines.append("Nature : \(kind.label)")
        lines.append("Urgence : \(severity.label) — \(severity.detail)")

        if !equipmentName.isEmpty {
            lines.append("Équipement : \(equipmentName)")
        }

        lines.append("Constaté le : \(AppFormatters.dateAndTime(reportedAt))")

        if !reportedBy.isEmpty {
            lines.append("Constaté par : \(reportedBy)")
        }

        lines.append("")
        lines.append("Description :")
        lines.append(descriptionText.isEmpty ? "(non renseignée)" : descriptionText)

        if !immediateAction.isEmpty {
            lines.append("")
            lines.append("Mesure prise en attendant :")
            lines.append(immediateAction)
        }

        if kind.isFoodCritical {
            lines.append("")
            lines.append("Cet incident concerne une enceinte frigorifique : des denrées peuvent être en jeu.")
        }

        lines.append("")
        lines.append("— Message préparé par \(BrandAssets.productName)")

        return lines.joined(separator: "\n")
    }
}
