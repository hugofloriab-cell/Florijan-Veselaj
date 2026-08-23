//
//  OilCheckRecord.swift
//  HACCPPocket
//
//  Suivi des bains de friture. En France, un bain dont les composés polaires
//  dépassent 25 % doit être changé : c'est le seuil que retient l'application.
//

import Foundation
import SwiftData

// MARK: - Aspect du bain

enum OilAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case clear
    case amber
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear: "Clair"
        case .amber: "Ambré"
        case .dark:  "Foncé"
        }
    }

    /// Un bain foncé est suspect même quand la mesure manque.
    var isSuspect: Bool { self == .dark }
}

// MARK: - Suite donnée

enum OilAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case kept
    case filtered
    case changed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kept:     "Bain conservé"
        case .filtered: "Bain filtré"
        case .changed:  "Bain changé"
        }
    }

    var systemImage: String {
        switch self {
        case .kept:     "checkmark.circle"
        case .filtered: "line.3.horizontal.decrease.circle"
        case .changed:  "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Modèle

@Model
final class OilCheckRecord {

    /// Seuil réglementaire de composés polaires, en pourcentage.
    static let polarCompoundsLimit: Double = 25

    var checkedAt: Date

    /// Friteuse concernée, saisie librement : toutes n'ont pas de nom officiel.
    var fryerName: String

    /// Mesure au testeur, en pourcentage. `nil` si contrôle visuel seul.
    var polarCompounds: Double?

    /// Seuil appliqué au moment du contrôle, figé pour l'historique.
    var polarCompoundsLimit: Double

    var appearanceRawValue: String
    var actionRawValue: String

    var operatorName: String
    var comment: String

    var isCompliant: Bool
    var createdAt: Date

    init(
        fryerName: String,
        checkedAt: Date = .now,
        polarCompounds: Double? = nil,
        appearance: OilAppearance = .clear,
        action: OilAction = .kept,
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.fryerName = fryerName
        self.checkedAt = checkedAt
        self.polarCompounds = polarCompounds
        self.polarCompoundsLimit = OilCheckRecord.polarCompoundsLimit
        self.appearanceRawValue = appearance.rawValue
        self.actionRawValue = action.rawValue
        self.operatorName = operatorName
        self.comment = comment
        self.createdAt = createdAt

        // Conformité posée à la création puis recalculée à chaque modification.
        if let polarCompounds {
            self.isCompliant = polarCompounds <= OilCheckRecord.polarCompoundsLimit
        } else {
            self.isCompliant = !appearance.isSuspect
        }
    }
}

// MARK: - Logique métier

extension OilCheckRecord {

    var appearance: OilAppearance {
        get { OilAppearance(rawValue: appearanceRawValue) ?? .clear }
        set { appearanceRawValue = newValue.rawValue }
    }

    var action: OilAction {
        get { OilAction(rawValue: actionRawValue) ?? .kept }
        set { actionRawValue = newValue.rawValue }
    }

    var formattedPolarCompounds: String {
        guard let polarCompounds else { return "Non mesuré" }
        return "\(polarCompounds.formatted(.number.precision(.fractionLength(1)).locale(AppFormatters.locale))) %"
    }

    /// À défaut de mesure, l'aspect fait foi : un bain foncé est non conforme.
    func recomputeCompliance() {
        if let polarCompounds {
            isCompliant = polarCompounds <= polarCompoundsLimit
        } else {
            isCompliant = !appearance.isSuspect
        }
    }

    /// Un bain hors seuil qui n'a été ni filtré ni changé est un manquement.
    var needsAction: Bool {
        !isCompliant && action == .kept
    }

    var statusLabel: String {
        if isCompliant { return "Conforme" }
        return polarCompounds == nil ? "Aspect dégradé" : "Hors seuil"
    }
}
