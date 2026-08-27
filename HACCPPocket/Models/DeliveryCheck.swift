//
//  DeliveryCheck.swift
//  HACCPPocket
//
//  Contrôle à réception des marchandises : c'est le premier maillon du PMS.
//  Température du produit livré, état de l'emballage, décision d'acceptation.
//

import Foundation
import SwiftData

// MARK: - Décision

enum DeliveryDecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case accepted
    case partiallyAccepted
    case refused

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accepted:          "Acceptée"
        case .partiallyAccepted: "Acceptée partiellement"
        case .refused:           "Refusée"
        }
    }

    var systemImage: String {
        switch self {
        case .accepted:          "checkmark.seal"
        case .partiallyAccepted: "exclamationmark.triangle"
        case .refused:           "xmark.seal"
        }
    }

    /// Un refus ou une acceptation partielle impose un motif écrit.
    var requiresReason: Bool { self != .accepted }
}

// MARK: - Modèle

@Model
final class DeliveryCheck {

    var receivedAt: Date = Date.now

    var supplierName: String = ""

    /// Désignation de la marchandise contrôlée.
    var productLabel: String = ""

    var batchNumber: String = ""

    /// Température relevée à cœur ou en surface, en °C. `nil` pour l'épicerie sèche.
    var temperature: Double?

    /// Seuil maximal admis pour cette livraison (ex. 4 °C en frais, -18 °C en surgelé).
    var temperatureLimit: Double?

    var packagingIntact: Bool = true

    /// Étiquetage conforme : DLC lisible, numéro de lot présent, marque de salubrité.
    var labellingCompliant: Bool = true

    var decisionRawValue: String = ""

    /// Motif de refus ou réserve émise sur le bon de livraison.
    var reason: String = ""

    var operatorName: String = ""

    /// Photo libre de la marchandise. Conservée pour les enregistrements
    /// saisis avant que les pièces justificatives ne soient séparées.
    @Attribute(.externalStorage) var photoData: Data?

    /// Pièces justificatives photographiées : bon de livraison, facture,
    /// constat de non-conformité. Chacune porte sa nature, annoncée avant la
    /// prise de vue.
    @Relationship(deleteRule: .cascade, inverse: \DeliveryDocument.delivery)
    var documents: [DeliveryDocument] = []

    var notes: String = ""
    var createdAt: Date = Date.now

    init(
        supplierName: String,
        productLabel: String = "",
        receivedAt: Date = .now,
        temperature: Double? = nil,
        temperatureLimit: Double? = nil,
        packagingIntact: Bool = true,
        labellingCompliant: Bool = true,
        decision: DeliveryDecision = .accepted,
        reason: String = "",
        batchNumber: String = "",
        operatorName: String = "",
        photoData: Data? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.supplierName = supplierName
        self.productLabel = productLabel
        self.receivedAt = receivedAt
        self.temperature = temperature
        self.temperatureLimit = temperatureLimit
        self.packagingIntact = packagingIntact
        self.labellingCompliant = labellingCompliant
        self.decisionRawValue = decision.rawValue
        self.reason = reason
        self.batchNumber = batchNumber
        self.operatorName = operatorName
        self.photoData = photoData
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - Logique métier

extension DeliveryCheck {

    var decision: DeliveryDecision {
        get { DeliveryDecision(rawValue: decisionRawValue) ?? .accepted }
        set { decisionRawValue = newValue.rawValue }
    }

    /// La température relevée dépasse-t-elle le seuil admis ?
    var isTemperatureCompliant: Bool {
        guard let temperature, let temperatureLimit else { return true }
        return temperature <= temperatureLimit
    }

    /// Synthèse des trois points de contrôle réglementaires.
    var isFullyCompliant: Bool {
        isTemperatureCompliant && packagingIntact && labellingCompliant
    }

    /// Liste des anomalies, réutilisée telle quelle dans le PDF mensuel.
    var anomalies: [String] {
        var found: [String] = []
        if !isTemperatureCompliant { found.append("Température hors seuil") }
        if !packagingIntact { found.append("Emballage endommagé") }
        if !labellingCompliant { found.append("Étiquetage non conforme") }
        return found
    }

    var formattedTemperature: String {
        guard let temperature else { return "—" }
        return AppFormatters.temperature(temperature)
    }

    /// Un contrôle non conforme sans motif renseigné est un dossier incomplet.
    var needsReason: Bool {
        decision.requiresReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Pièces justificatives

    /// Documents photographiés, groupés par nature puis du plus récent au
    /// plus ancien.
    var orderedDocuments: [DeliveryDocument] {
        documents.sorted { left, right in
            if left.kind.sortWeight != right.kind.sortWeight {
                return left.kind.sortWeight < right.kind.sortWeight
            }
            return left.capturedAt > right.capturedAt
        }
    }

    /// Au moins une pièce photographiée.
    ///
    /// La photo libre des anciens enregistrements compte : ils ont été saisis
    /// quand rien n'était exigé, les marquer incomplets aujourd'hui
    /// reviendrait à leur reprocher une règle qui n'existait pas.
    var hasJustification: Bool {
        documents.contains(where: \.hasPhoto) || photoData != nil
    }

    /// Une réception refusée ou acceptée sous réserve sans photo du constat
    /// est difficile à défendre : c'est la photo qui montre ce qui a été vu.
    var lacksNonConformityEvidence: Bool {
        decision.requiresReason && !documents.contains { $0.kind == .nonConformity && $0.hasPhoto }
    }
}
