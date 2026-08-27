//
//  MedicalFitnessRecord.swift
//  HACCPPocket
//
//  Suivi médical du personnel manipulant des denrées.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE DIT VRAIMENT LA RÈGLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le règlement (CE) n° 852/2004 pose une interdiction claire : une personne
//  atteinte d'une maladie transmissible par les aliments ne doit pas
//  manipuler de denrées. C'est ce principe qui est réglementaire.
//
//  Le suivi médical qui permet de s'en assurer relève, lui, du code du
//  travail : visite d'information et de prévention à l'embauche, puis
//  périodique, par le service de prévention et de santé au travail. Ce n'est
//  pas un « certificat d'aptitude alimentaire » — cette pièce spécifique
//  n'existe plus dans les textes.
//
//  Ce registre archive donc ce que l'employeur détient réellement : les
//  attestations de suivi et les avis d'aptitude délivrés par la médecine du
//  travail. L'application ne prétend pas qu'un document particulier est
//  obligatoire, elle aide à ne pas les perdre et à voir venir les échéances.
//

import Foundation
import SwiftData

// MARK: - Avis

enum FitnessVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case fit
    case fitWithRestrictions
    case unfit
    case pending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit:                 "Apte"
        case .fitWithRestrictions: "Apte avec aménagement"
        case .unfit:               "Inapte au poste"
        case .pending:             "Visite à programmer"
        }
    }

    var systemImage: String {
        switch self {
        case .fit:                 "checkmark.seal.fill"
        case .fitWithRestrictions: "exclamationmark.circle.fill"
        case .unfit:               "xmark.seal.fill"
        case .pending:             "calendar.badge.clock"
        }
    }

    /// Un avis qui appelle une décision de l'employeur.
    var needsAttention: Bool {
        self != .fit
    }
}

// MARK: - Enregistrement

@Model
final class MedicalFitnessRecord {

    var personName: String = ""

    /// Poste occupé : c'est lui que l'avis d'aptitude vise.
    var jobTitle: String = ""

    /// Service de prévention et de santé au travail.
    var occupationalHealthService: String = ""

    var examinedAt: Date = Date.now

    /// Échéance du prochain suivi. La périodicité dépend du poste et du
    /// service de santé : elle n'est pas la même pour tout le monde.
    var nextVisitDate: Date?

    var verdictRawValue: String = FitnessVerdict.fit.rawValue

    /// Aménagements ou restrictions prononcés.
    var restrictions: String = ""

    /// Attestation de suivi ou avis d'aptitude, photographié ou importé.
    @Attribute(.externalStorage) var documentData: Data?

    var comment: String = ""
    var createdAt: Date = Date.now

    /// Délai d'alerte avant l'échéance.
    static let warningDays = 60

    init(
        personName: String = "",
        jobTitle: String = "",
        occupationalHealthService: String = "",
        examinedAt: Date = .now,
        nextVisitDate: Date? = nil,
        verdict: FitnessVerdict = .fit,
        restrictions: String = "",
        documentData: Data? = nil,
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.personName = personName
        self.jobTitle = jobTitle
        self.occupationalHealthService = occupationalHealthService
        self.examinedAt = examinedAt
        self.nextVisitDate = nextVisitDate
        self.verdictRawValue = verdict.rawValue
        self.restrictions = restrictions
        self.documentData = documentData
        self.comment = comment
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var verdict: FitnessVerdict {
        get { FitnessVerdict(rawValue: verdictRawValue) ?? .fit }
        set { verdictRawValue = newValue.rawValue }
    }

    var displayName: String {
        personName.isEmpty ? "Personne non nommée" : personName
    }

    /// Prénom seul, pour l'affichage en équipe.
    ///
    /// En cuisine on s'appelle par le prénom, et une liste de noms complets
    /// se lit mal sur un téléphone. Le nom entier reste disponible dans la
    /// fiche : c'est lui qui compte sur un document.
    var firstName: String {
        let trimmed = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Sans nom" }
        return trimmed.components(separatedBy: " ").first ?? trimmed
    }

    /// Clé de regroupement : deux fiches d'une même personne doivent se
    /// rejoindre malgré une majuscule ou un espace de différence.
    var personKey: String {
        personName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)
            .lowercased()
    }

    var hasDocument: Bool { documentData != nil }

    // MARK: - Confidentialité

    /// Le contenu de l'avis est-il autre chose qu'un simple « apte » ?
    ///
    /// ⚠️ Ce qui suit n'est pas un détail d'affichage. L'avis d'aptitude et
    /// ses éventuelles restrictions relèvent du suivi médical du salarié.
    /// L'employeur les détient parce qu'il doit les appliquer, mais il n'a
    /// aucune raison de les afficher, de les imprimer dans un registre, ni de
    /// les remettre spontanément à qui que ce soit.
    ///
    /// Ce que le registre mensuel montre est donc uniquement : visite
    /// effectuée, ou non. Le reste ne sort que sur demande explicite.
    var hasConfidentialContent: Bool {
        hasDocument
            || !restrictions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || verdict == .fitWithRestrictions
            || verdict == .unfit
    }

    /// Mention portée au registre mensuel. Rien d'autre n'en sort.
    func registerMention(for period: DateInterval) -> String {
        period.contains(examinedAt)
            ? "Visite effectuée le \(AppFormatters.shortDate(examinedAt))"
            : "Aucune visite sur la période"
    }

    // MARK: - Échéances

    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let nextVisitDate else { return false }
        return calendar.startOfDay(for: nextVisitDate) < calendar.startOfDay(for: reference)
    }

    func isDueSoon(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let nextVisitDate, !isOverdue(at: reference, calendar: calendar) else { return false }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: nextVisitDate)
        ).day ?? 0
        return days <= MedicalFitnessRecord.warningDays
    }

    var needsAction: Bool {
        isOverdue() || isDueSoon() || verdict.needsAttention
    }

    var statusLabel: String {
        if isOverdue() { return "Visite dépassée" }
        if verdict != .fit { return verdict.label }
        if isDueSoon() { return "Visite à prévoir" }
        return "À jour"
    }
}
