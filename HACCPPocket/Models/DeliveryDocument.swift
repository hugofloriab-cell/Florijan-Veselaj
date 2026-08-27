//
//  DeliveryDocument.swift
//  HACCPPocket
//
//  Pièce justificative photographiée à la réception d'une livraison.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI LA NATURE SE CHOISIT AVANT LA PHOTO
//  ─────────────────────────────────────────────────────────────────────────
//
//  Un bon de livraison et une facture ne se ressemblent pas assez pour être
//  distingués six mois plus tard sur une photo prise de travers dans une
//  chambre froide. Demander la nature après coup revient à ne jamais la
//  demander : la personne a rangé le téléphone et est passée à autre chose.
//
//  L'ordre est donc imposé : on annonce ce qu'on va photographier, puis on
//  photographie. C'est une contrainte d'une seconde qui rend l'album
//  consultable.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CES PHOTOS NE SONT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Elles ne figurent pas dans le registre mensuel. Un registre se lit : des
//  lignes, des températures, des décisions. Y coller trente photos de bons de
//  livraison le rendrait illisible et impossible à imprimer.
//
//  Elles vivent dans la page « Photos », d'où elles peuvent être imprimées
//  séparément si un contrôleur demande à voir les justificatifs.
//

import Foundation
import SwiftData

// MARK: - Nature du document

/// Ce qu'on photographie. La liste est courte à dessein : au-delà de six
/// choix, on passe plus de temps à choisir qu'à photographier.
enum DeliveryDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case deliveryNote
    case invoice
    case transportDocument
    case productLabel
    case nonConformity
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deliveryNote:      "Bon de livraison"
        case .invoice:           "Facture"
        case .transportDocument: "Document de transport"
        case .productLabel:      "Étiquette produit"
        case .nonConformity:     "Constat de non-conformité"
        case .other:             "Autre document"
        }
    }

    var systemImage: String {
        switch self {
        case .deliveryNote:      "doc.text"
        case .invoice:           "eurosign.circle"
        case .transportDocument: "truck.box"
        case .productLabel:      "tag"
        case .nonConformity:     "exclamationmark.triangle"
        case .other:             "doc"
        }
    }

    /// Ce que la personne doit cadrer. Affiché juste avant l'appareil photo :
    /// c'est le moment où le conseil sert à quelque chose.
    var captureHint: String {
        switch self {
        case .deliveryNote:
            return "Cadrez le bon en entier : le nom du fournisseur, la date et les lots doivent être lisibles."
        case .invoice:
            return "Cadrez la facture en entier. Elle sert de preuve d'achat en cas de retrait ou de rappel."
        case .transportDocument:
            return "Photographiez le relevé de température du transporteur s'il en fournit un."
        case .productLabel:
            return "Cadrez l'étiquette du produit : dénomination, lot et date limite."
        case .nonConformity:
            return "Photographiez ce que vous refusez — emballage percé, givre, étiquette absente. C'est cette photo qui justifie le refus."
        case .other:
            return "Cadrez le document en entier, à plat et bien éclairé."
        }
    }

    /// Ordre d'affichage dans l'album et dans le menu de choix.
    var sortWeight: Int {
        switch self {
        case .deliveryNote:      0
        case .invoice:           1
        case .transportDocument: 2
        case .productLabel:      3
        case .nonConformity:     4
        case .other:             5
        }
    }
}

// MARK: - Modèle

@Model
final class DeliveryDocument {

    /// Nature annoncée avant la prise de vue.
    var kindRawValue: String = DeliveryDocumentKind.deliveryNote.rawValue

    @Attribute(.externalStorage) var photoData: Data?

    var capturedAt: Date = Date.now

    /// Précision libre : numéro du bon, remarque sur ce qui est visible.
    var note: String = ""

    var delivery: DeliveryCheck?

    init(
        kind: DeliveryDocumentKind = .deliveryNote,
        photoData: Data? = nil,
        capturedAt: Date = .now,
        note: String = "",
        delivery: DeliveryCheck? = nil
    ) {
        self.kindRawValue = kind.rawValue
        self.photoData = photoData
        self.capturedAt = capturedAt
        self.note = note
        self.delivery = delivery
    }

    var kind: DeliveryDocumentKind {
        get { DeliveryDocumentKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var hasPhoto: Bool { photoData != nil }

    /// Intitulé porté sous la vignette dans l'album.
    var caption: String {
        let supplier = delivery?.supplierName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return supplier.isEmpty ? kind.label : "\(kind.label) — \(supplier)"
    }
}
