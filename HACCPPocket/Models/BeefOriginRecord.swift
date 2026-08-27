//
//  BeefOriginRecord.swift
//  HACCPPocket
//
//  Traçabilité de l'origine des viandes servies.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE LE DÉCRET DE 2022 A CHANGÉ
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le décret n° 2002-1455 ne visait que la viande bovine. Le décret
//  n° 2022-65 du 26 janvier 2022 l'a étendu au porc, au mouton et à la
//  volaille. Un restaurant qui affiche l'origine de son bœuf et rien d'autre
//  n'est donc plus à jour.
//
//  L'information doit être portée à la connaissance du consommateur de façon
//  lisible et visible : affichage, mention sur la carte, ou tout autre
//  support. Le registre, lui, liste toutes les viandes proposées et sert à
//  produire ce support.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI LE TYPE S'APPELLE ENCORE BeefOriginRecord
//  ─────────────────────────────────────────────────────────────────────────
//
//  Renommer une classe `@Model` change le nom de l'entité stockée, ce que
//  SwiftData ne sait pas migrer sans une étape personnalisée qui doit relire
//  l'ancienne forme. Le jeu n'en vaut pas la chandelle : le nom du type reste,
//  toute l'interface parle des viandes. C'est le seul endroit du projet où
//  le code et l'écran ne portent pas le même mot, et c'est délibéré.
//

import Foundation
import SwiftData

// MARK: - Espèce

/// Les quatre familles visées par l'obligation d'affichage.
enum MeatSpecies: String, Codable, CaseIterable, Identifiable, Sendable {
    case bovine
    case porcine
    case ovine
    case poultry

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bovine:  "Bovine"
        case .porcine: "Porcine"
        case .ovine:   "Ovine"
        case .poultry: "Volaille"
        }
    }

    var systemImage: String {
        switch self {
        case .bovine:  "fork.knife"
        case .porcine: "circle.grid.2x2"
        case .ovine:   "cloud"
        case .poultry: "bird"
        }
    }

    /// Ordre d'apparition sur le document affiché en salle.
    var sortWeight: Int {
        switch self {
        case .bovine:  0
        case .porcine: 1
        case .ovine:   2
        case .poultry: 3
        }
    }
}

@Model
final class BeefOriginRecord {

    /// Désignation commerciale : entrecôte, bavette, viande hachée…
    var cutName: String = ""

    /// Espèce, au sens du décret de 2022.
    var speciesRawValue: String = MeatSpecies.bovine.rawValue

    /// La viande figure-t-elle à la carte en ce moment ? Le document affiché
    /// en salle ne liste que celles-là.
    var isOnMenu: Bool = true

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
        species: MeatSpecies = .bovine,
        isOnMenu: Bool = true,
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
        self.speciesRawValue = species.rawValue
        self.isOnMenu = isOnMenu
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

    var species: MeatSpecies {
        get { MeatSpecies(rawValue: speciesRawValue) ?? .bovine }
        set { speciesRawValue = newValue.rawValue }
    }

    var displayName: String {
        cutName.isEmpty ? "Viande sans désignation" : cutName
    }

    /// Intitulé repris tel quel sur le document affiché en salle.
    var documentTitle: String {
        "Viande \(species.label.lowercased()) : \(displayName)"
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
