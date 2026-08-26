//
//  ShiftHygieneCheck.swift
//  HACCPPocket
//
//  Contrôle d'hygiène à la prise de poste.
//
//  C'est le contrôle le plus court et le plus rentable de la cuisine. La
//  contamination la plus fréquente ne vient ni du frigo ni du fournisseur :
//  elle vient des mains. Trente secondes en début de service, et le registre
//  prouve que le sujet est tenu — ce que le PMS exige et que presque personne
//  ne trace.
//

import Foundation
import SwiftData

// MARK: - Points de contrôle

enum HygieneCheckItem: String, Codable, CaseIterable, Identifiable, Sendable {

    case handWashing
    case cleanUniform
    case hairCovering
    case noJewellery
    case shortNails
    case coveredWounds
    case noSymptoms
    case noSmokingEating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .handWashing:     "Mains lavées"
        case .cleanUniform:    "Tenue propre et complète"
        case .hairCovering:    "Cheveux couverts"
        case .noJewellery:     "Sans bijou ni montre"
        case .shortNails:      "Ongles courts, sans vernis"
        case .coveredWounds:   "Plaies protégées"
        case .noSymptoms:      "Aucun symptôme"
        case .noSmokingEating: "Ni tabac ni nourriture au poste"
        }
    }

    var detail: String {
        switch self {
        case .handWashing:
            "Savon, 30 secondes, ongles et poignets compris, séchage à usage unique."
        case .cleanUniform:
            "Veste, pantalon et chaussures propres, réservés au service, changés chaque jour."
        case .hairCovering:
            "Charlotte ou calot couvrant l'ensemble de la chevelure, barbe comprise."
        case .noJewellery:
            "Bagues, montres, bracelets : ils retiennent l'humidité et les résidus, et tombent dans les préparations."
        case .shortNails:
            "Le vernis s'écaille dans les plats, et les faux ongles se décollent."
        case .coveredWounds:
            "Pansement étanche et coloré, plus un gant à usage unique par-dessus."
        case .noSymptoms:
            "Diarrhée, vomissements, fièvre, angine, lésion cutanée infectée : le poste change ou le service s'arrête."
        case .noSmokingEating:
            "Y compris chewing-gum et boisson posée sur le plan de travail."
        }
    }

    var systemImage: String {
        switch self {
        case .handWashing:     "hands.and.sparkles"
        case .cleanUniform:    "tshirt"
        case .hairCovering:    "person.crop.circle"
        case .noJewellery:     "hand.raised.slash"
        case .shortNails:      "hand.point.up"
        case .coveredWounds:   "bandage"
        case .noSymptoms:      "thermometer.medium"
        case .noSmokingEating: "nosign"
        }
    }

    /// Le point qui, s'il échoue, interdit le poste plutôt que de demander une
    /// simple correction.
    var isDisqualifying: Bool {
        self == .noSymptoms
    }

    var note: RegulatoryNote? {
        switch self {
        case .noSymptoms:
            RegulatoryNote(
                title: "Travailler malade",
                explanation: "Une personne atteinte d'une maladie transmissible par les aliments, ou porteuse d'une plaie infectée, ne doit pas manipuler de denrées. Ce n'est pas une recommandation : c'est une interdiction, et elle vaut aussi pour le chef. Reclassez la personne à un poste sans contact avec les aliments, ou renvoyez-la chez elle.",
                origin: .regulation("Règlement (CE) n° 852/2004, annexe II, chapitre VIII")
            )
        case .handWashing:
            RegulatoryNote(
                title: "Pourquoi 30 secondes",
                explanation: "En dessous, le savon n'a pas le temps de décoller le film gras qui protège les bactéries. C'est la durée, pas la température de l'eau, qui fait le travail — se laver les mains à l'eau brûlante pendant cinq secondes ne sert à rien.",
                origin: .practice
            )
        default:
            nil
        }
    }
}

// MARK: - Enregistrement

@Model
final class ShiftHygieneCheck {

    var personName: String = ""

    /// Service concerné : matin, midi, soir, coupure.
    var shiftLabel: String = ""

    var checkedAt: Date = Date.now

    /// Points contrôlés et conformes, en valeurs brutes.
    var passedRawValues: [String] = []

    /// Points contrôlés et non conformes.
    var failedRawValues: [String] = []

    /// Ce qui a été fait des non-conformités constatées.
    var correctiveAction: String = ""

    /// Signature de la personne contrôlée, tracée à l'écran.
    @Attribute(.externalStorage) var signatureData: Data?

    /// Nom de la personne qui a réalisé le contrôle.
    var checkedBy: String = ""

    var comment: String = ""
    var createdAt: Date = Date.now

    init(
        personName: String = "",
        shiftLabel: String = "",
        checkedAt: Date = .now,
        passed: Set<HygieneCheckItem> = [],
        failed: Set<HygieneCheckItem> = [],
        correctiveAction: String = "",
        signatureData: Data? = nil,
        checkedBy: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.personName = personName
        self.shiftLabel = shiftLabel
        self.checkedAt = checkedAt
        self.passedRawValues = ShiftHygieneCheck.rawValues(from: passed)
        self.failedRawValues = ShiftHygieneCheck.rawValues(from: failed)
        self.correctiveAction = correctiveAction
        self.signatureData = signatureData
        self.checkedBy = checkedBy
        self.comment = comment
        self.createdAt = createdAt
    }

    // MARK: - Conversions

    static func rawValues(from items: Set<HygieneCheckItem>) -> [String] {
        HygieneCheckItem.allCases.filter { items.contains($0) }.map(\.rawValue)
    }

    static func items(from rawValues: [String]) -> Set<HygieneCheckItem> {
        Set(rawValues.compactMap { HygieneCheckItem(rawValue: $0) })
    }

    var passed: Set<HygieneCheckItem> {
        get { ShiftHygieneCheck.items(from: passedRawValues) }
        set { passedRawValues = ShiftHygieneCheck.rawValues(from: newValue) }
    }

    var failed: Set<HygieneCheckItem> {
        get { ShiftHygieneCheck.items(from: failedRawValues) }
        set { failedRawValues = ShiftHygieneCheck.rawValues(from: newValue) }
    }

    // MARK: - Lecture

    var displayName: String {
        personName.isEmpty ? "Personne non nommée" : personName
    }

    var isCompliant: Bool { failedRawValues.isEmpty }

    /// Un symptôme constaté interdit le poste : la non-conformité n'est plus
    /// une correction à faire, c'est une décision à prendre.
    var isDisqualified: Bool {
        failed.contains { $0.isDisqualifying }
    }

    var hasSignature: Bool { signatureData != nil }

    /// Un contrôle où rien n'a été coché n'a pas eu lieu.
    var isIncomplete: Bool {
        passedRawValues.isEmpty && failedRawValues.isEmpty
    }

    var statusLabel: String {
        if isIncomplete { return "Non renseigné" }
        if isDisqualified { return "Poste interdit" }
        return isCompliant ? "Conforme" : "\(failedRawValues.count) écart(s)"
    }

    var failureSummary: String {
        let items = HygieneCheckItem.allCases.filter { failed.contains($0) }
        return items.map(\.label).joined(separator: ", ")
    }
}
