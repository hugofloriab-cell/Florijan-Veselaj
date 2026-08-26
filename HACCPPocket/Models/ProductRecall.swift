//
//  ProductRecall.swift
//  HACCPPocket
//
//  Registre des retraits et rappels de produits.
//
//  Un fournisseur signale un lot contaminé, ou l'alerte paraît sur
//  RappelConso. À partir de cet instant, l'établissement doit isoler le lot,
//  vérifier ce qu'il en a fait, et parfois prévenir ses clients et
//  l'administration. Ces heures-là ne s'improvisent pas.
//
//  La différence entre les deux mots compte :
//  — RETRAIT : le produit est encore chez vous, il n'est pas parti au client.
//  — RAPPEL : le produit a déjà été servi ou vendu. L'information doit alors
//    remonter au consommateur.
//

import Foundation
import SwiftData

// MARK: - Portée

enum RecallScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case withdrawal   // Retrait : stock uniquement
    case recall       // Rappel : produit déjà servi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withdrawal: "Retrait"
        case .recall:     "Rappel"
        }
    }

    var detail: String {
        switch self {
        case .withdrawal:
            "Le produit est encore en stock : il suffit de l'isoler et de le sortir du circuit."
        case .recall:
            "Le produit a déjà été servi ou vendu : l'information doit remonter au consommateur."
        }
    }

    var systemImage: String {
        switch self {
        case .withdrawal: "arrow.uturn.backward.circle"
        case .recall:     "megaphone"
        }
    }

    /// Un rappel impose d'informer, et généralement de déclarer.
    var requiresPublicNotice: Bool { self == .recall }
}

// MARK: - Sort du lot

enum RecallOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case returned
    case destroyed
    case noneHeld

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending:   "En cours de traitement"
        case .returned:  "Retourné au fournisseur"
        case .destroyed: "Détruit sur place"
        case .noneHeld:  "Aucun stock concerné"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:   "clock"
        case .returned:  "shippingbox.and.arrow.backward"
        case .destroyed: "trash"
        case .noneHeld:  "checkmark.circle"
        }
    }
}

// MARK: - Enregistrement

@Model
final class ProductRecall {

    var productName: String = ""
    var brand: String = ""

    /// Lots visés par l'alerte, tels qu'ils sont annoncés.
    var affectedBatches: String = ""

    var supplier: String = ""

    /// Référence de l'avis : numéro fournisseur, ou fiche RappelConso.
    var noticeReference: String = ""

    /// Motif du retrait : le danger annoncé.
    var reason: String = ""

    var scopeRawValue: String = RecallScope.withdrawal.rawValue

    /// Quand l'établissement a eu connaissance de l'alerte. C'est de cette
    /// date que part le délai de réaction.
    var noticedAt: Date = Date.now

    /// Isolement effectif du lot.
    var isolatedAt: Date?

    var quantityHeld: String = ""
    var outcomeRawValue: String = RecallOutcome.pending.rawValue

    /// Preuve de destruction ou de retour : bon, photo, bordereau.
    @Attribute(.externalStorage) var proofData: Data?

    /// Le produit a-t-il été servi avant l'alerte ?
    var wasServed: Bool = false

    var customersInformed: Bool = false
    var authorityInformed: Bool = false
    var authorityInformedAt: Date?

    var operatorName: String = ""
    var notes: String = ""
    var closedAt: Date?
    var createdAt: Date = Date.now

    init(
        productName: String = "",
        brand: String = "",
        affectedBatches: String = "",
        supplier: String = "",
        noticeReference: String = "",
        reason: String = "",
        scope: RecallScope = .withdrawal,
        noticedAt: Date = .now,
        quantityHeld: String = "",
        outcome: RecallOutcome = .pending,
        wasServed: Bool = false,
        operatorName: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.productName = productName
        self.brand = brand
        self.affectedBatches = affectedBatches
        self.supplier = supplier
        self.noticeReference = noticeReference
        self.reason = reason
        self.scopeRawValue = scope.rawValue
        self.noticedAt = noticedAt
        self.isolatedAt = nil
        self.quantityHeld = quantityHeld
        self.outcomeRawValue = outcome.rawValue
        self.wasServed = wasServed
        self.customersInformed = false
        self.authorityInformed = false
        self.authorityInformedAt = nil
        self.operatorName = operatorName
        self.notes = notes
        self.closedAt = nil
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var scope: RecallScope {
        get { RecallScope(rawValue: scopeRawValue) ?? .withdrawal }
        set { scopeRawValue = newValue.rawValue }
    }

    var outcome: RecallOutcome {
        get { RecallOutcome(rawValue: outcomeRawValue) ?? .pending }
        set { outcomeRawValue = newValue.rawValue }
    }

    var displayName: String {
        productName.isEmpty ? "Produit non précisé" : productName
    }

    var isClosed: Bool { closedAt != nil }
    var hasProof: Bool { proofData != nil }

    // MARK: - Ce qu'il reste à faire

    /// Les étapes non tenues, formulées telles qu'on doit les lire dans
    /// l'urgence : chacune est une action, pas un constat.
    var pendingSteps: [String] {
        var steps: [String] = []

        if isolatedAt == nil && outcome != .noneHeld {
            steps.append("Isoler le lot et l'étiqueter « ne pas utiliser »")
        }
        if outcome == .pending {
            steps.append("Décider du sort du lot : retour ou destruction")
        }
        if outcome == .destroyed && !hasProof {
            steps.append("Joindre la preuve de destruction")
        }
        if wasServed && !customersInformed {
            steps.append("Informer les consommateurs concernés")
        }
        if wasServed && !authorityInformed {
            steps.append("Déclarer à la DDPP du département")
        }
        return steps
    }

    var isComplete: Bool { pendingSteps.isEmpty }

    var needsAction: Bool { !isClosed && !isComplete }

    var statusLabel: String {
        if isClosed { return "Clôturé" }
        if isComplete { return "Prêt à clôturer" }
        return "\(pendingSteps.count) action(s)"
    }

    /// Délai écoulé depuis la prise de connaissance : c'est ce chiffre qu'un
    /// contrôleur regarde en premier.
    func hoursSinceNotice(at date: Date = .now) -> Int {
        max(0, Int(date.timeIntervalSince(noticedAt) / 3600))
    }
}
