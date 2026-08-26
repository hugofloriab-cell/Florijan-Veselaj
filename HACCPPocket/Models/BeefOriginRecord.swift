//
//  BeefOriginRecord.swift
//  HACCPPocket
//
//  Traçabilité de l'origine de la viande bovine.
//
//  Tout établissement servant de la viande bovine doit informer le
//  consommateur de son origine : pays de naissance, d'élevage et d'abattage.
//  L'information s'affiche en salle, et l'établissement doit pouvoir la
//  justifier lot par lot à partir des documents du fournisseur.
//
//  Quand les trois pays sont identiques, l'affichage se simplifie en
//  « Origine : France » — mais les trois doivent être connus pour le dire.
//

import Foundation
import SwiftData

@Model
final class BeefOriginRecord {

    /// Désignation commerciale : entrecôte, bavette, viande hachée…
    var cutName: String = ""

    var batchNumber: String = ""
    var supplier: String = ""

    /// Les trois pays exigés par l'affichage.
    var birthCountry: String = ""
    var rearingCountry: String = ""
    var slaughterCountry: String = ""

    /// Numéro d'agrément de l'abattoir.
    var slaughterhouseApproval: String = ""

    /// Numéro d'agrément de l'atelier de découpe.
    var cuttingPlantApproval: String = ""

    var receivedAt: Date = Date.now
    var quantity: String = ""

    /// Photo de l'étiquette du fournisseur : c'est elle qui fait foi.
    @Attribute(.externalStorage) var labelPhotoData: Data?

    var operatorName: String = ""
    var comment: String = ""
    var createdAt: Date = Date.now

    init(
        cutName: String = "",
        batchNumber: String = "",
        supplier: String = "",
        birthCountry: String = "",
        rearingCountry: String = "",
        slaughterCountry: String = "",
        slaughterhouseApproval: String = "",
        cuttingPlantApproval: String = "",
        receivedAt: Date = .now,
        quantity: String = "",
        labelPhotoData: Data? = nil,
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.cutName = cutName
        self.batchNumber = batchNumber
        self.supplier = supplier
        self.birthCountry = birthCountry
        self.rearingCountry = rearingCountry
        self.slaughterCountry = slaughterCountry
        self.slaughterhouseApproval = slaughterhouseApproval
        self.cuttingPlantApproval = cuttingPlantApproval
        self.receivedAt = receivedAt
        self.quantity = quantity
        self.labelPhotoData = labelPhotoData
        self.operatorName = operatorName
        self.comment = comment
        self.createdAt = createdAt
    }

    // MARK: - Affichage

    var displayName: String {
        cutName.isEmpty ? "Pièce sans désignation" : cutName
    }

    private var countries: [String] {
        [birthCountry, rearingCountry, slaughterCountry]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var isComplete: Bool {
        countries.allSatisfy { !$0.isEmpty }
    }

    /// Mention exacte à afficher en salle.
    ///
    /// Les trois pays identiques autorisent la forme courte. Sinon, il faut
    /// les citer tous les trois : c'est précisément ce que le consommateur a
    /// le droit de savoir.
    var displayMention: String {
        guard isComplete else { return "Origine incomplète" }

        let unique = Set(countries.map { $0.lowercased() })
        if unique.count == 1 {
            return "Origine : \(countries[0])"
        }

        return "Né en \(birthCountry), élevé en \(rearingCountry), abattu en \(slaughterCountry)"
    }

    var statusLabel: String {
        isComplete ? "Complet" : "À compléter"
    }

    var hasLabelPhoto: Bool { labelPhotoData != nil }
}
