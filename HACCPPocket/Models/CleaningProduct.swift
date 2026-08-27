//
//  CleaningProduct.swift
//  HACCPPocket
//
//  Fiches techniques des produits d'entretien.
//
//  Un désinfectant mal dilué ou essuyé trop tôt ne désinfecte pas. Or le
//  dosage et le temps de contact sont écrits en petit sur un bidon rangé sous
//  l'évier, et personne ne va les relire. Cette fiche met l'information là où
//  le geste se fait.
//
//  Elle archive aussi la fiche de données de sécurité, que l'employeur doit
//  tenir à disposition de son personnel.
//

import Foundation
import SwiftData

// MARK: - Nature du produit

enum CleaningProductKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case detergent
    case disinfectant
    case combined
    case degreaser
    case descaler
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detergent:    "Détergent"
        case .disinfectant: "Désinfectant"
        case .combined:     "Détergent-désinfectant"
        case .degreaser:    "Dégraissant"
        case .descaler:     "Détartrant"
        case .other:        "Autre"
        }
    }

    var systemImage: String {
        switch self {
        case .detergent:    "bubbles.and.sparkles"
        case .disinfectant: "shield.lefthalf.filled"
        case .combined:     "sparkles"
        case .degreaser:    "drop.triangle"
        case .descaler:     "waterbottle"
        case .other:        "shippingbox"
        }
    }

    /// Seuls les produits à action désinfectante imposent un temps de contact.
    var requiresContactTime: Bool {
        self == .disinfectant || self == .combined
    }
}

// MARK: - Fiche produit

@Model
final class CleaningProduct {

    var name: String = ""
    var supplier: String = ""
    var kindRawValue: String = CleaningProductKind.detergent.rawValue

    /// Dilution telle qu'elle est écrite sur le bidon : « 2 % », « 20 mL/L ».
    var dilution: String = ""

    /// Temps de contact en secondes. Zéro quand le produit n'en demande pas.
    var contactTimeSeconds: Int = 0

    var requiresRinsing: Bool = true

    /// Surfaces et zones concernées.
    var usage: String = ""

    /// Mentions de danger reprises de l'étiquette.
    var hazards: String = ""

    /// Norme d'efficacité revendiquée : EN 1276, EN 13697…
    var standard: String = ""

    /// Fiche de données de sécurité, photographiée ou importée.
    @Attribute(.externalStorage) var safetyDataSheet: Data?

    /// Photo du bidon, pour l'identifier d'un coup d'œil.
    ///
    /// En plonge, personne ne lit une fiche : on cherche le bidon bleu. Une
    /// photo du contenant évite la confusion entre deux produits au nom
    /// commercial voisin — et c'est exactement le genre de confusion qui met
    /// du dégraissant là où il fallait un désinfectant alimentaire.
    @Attribute(.externalStorage) var containerPhotoData: Data?

    var isActive: Bool = true
    var comment: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        name: String = "",
        supplier: String = "",
        kind: CleaningProductKind = .detergent,
        dilution: String = "",
        contactTimeSeconds: Int = 0,
        requiresRinsing: Bool = true,
        usage: String = "",
        hazards: String = "",
        standard: String = "",
        safetyDataSheet: Data? = nil,
        containerPhotoData: Data? = nil,
        isActive: Bool = true,
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.name = name
        self.supplier = supplier
        self.kindRawValue = kind.rawValue
        self.dilution = dilution
        self.contactTimeSeconds = contactTimeSeconds
        self.requiresRinsing = requiresRinsing
        self.usage = usage
        self.hazards = hazards
        self.standard = standard
        self.safetyDataSheet = safetyDataSheet
        self.containerPhotoData = containerPhotoData
        self.isActive = isActive
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: - Accès typé

    var kind: CleaningProductKind {
        get { CleaningProductKind(rawValue: kindRawValue) ?? .detergent }
        set { kindRawValue = newValue.rawValue }
    }

    var displayName: String {
        name.isEmpty ? "Produit sans nom" : name
    }

    var hasSafetyDataSheet: Bool { safetyDataSheet != nil }

    var hasContainerPhoto: Bool { containerPhotoData != nil }

    /// Ex. « 5 min », « 30 s ».
    var formattedContactTime: String {
        guard contactTimeSeconds > 0 else { return "Non applicable" }
        if contactTimeSeconds >= 60 {
            let minutes = contactTimeSeconds / 60
            let seconds = contactTimeSeconds % 60
            return seconds == 0 ? "\(minutes) min" : "\(minutes) min \(seconds) s"
        }
        return "\(contactTimeSeconds) s"
    }

    /// Une fiche sans dosage ni temps de contact ne sert à rien : c'est
    /// exactement l'information qu'on vient y chercher.
    var isIncomplete: Bool {
        if dilution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if kind.requiresContactTime && contactTimeSeconds == 0 { return true }
        return false
    }

    func touch(at date: Date = .now) {
        updatedAt = date
    }
}
