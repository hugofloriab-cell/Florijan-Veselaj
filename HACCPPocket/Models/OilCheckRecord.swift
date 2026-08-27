//
//  OilCheckRecord.swift
//  HACCPPocket
//
//  Suivi des bains de friture. En France, un bain dont les composés polaires
//  dépassent 25 % doit être changé : c'est le seuil que retient l'application.
//
//  Trois façons de contrôler, de la moins fiable à la plus précise :
//  l'aspect, la bandelette, le testeur électronique. Elles ne produisent pas
//  le même genre de résultat — un chiffre pour le testeur, une plage de
//  couleur pour la bandelette, une impression pour l'œil — et le modèle les
//  distingue au lieu de tout ramener à un pourcentage qu'on n'a pas mesuré.
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

// MARK: - Méthode de contrôle

enum OilTestMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Aspect, odeur, fumée : le contrôle du pauvre, mais mieux que rien.
    case visual
    /// Bandelette colorimétrique : une plage, pas un chiffre.
    case strip
    /// Testeur électronique : un pourcentage de composés polaires.
    case meter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .visual: "Aspect seul"
        case .strip:  "Bandelette"
        case .meter:  "Testeur électronique"
        }
    }

    var systemImage: String {
        switch self {
        case .visual: "eye"
        case .strip:  "list.bullet.rectangle"
        case .meter:  "gauge.with.dots.needle.bottom.50percent"
        }
    }

    /// Ce que la méthode vaut réellement, dit sans détour.
    var reliabilityNote: String {
        switch self {
        case .visual:
            return "Un bain peut être hors seuil sans avoir l'air sale, et un bain foncé n'est pas forcément à jeter. L'aspect ne se substitue pas à une mesure."
        case .strip:
            return "La bandelette situe le bain par rapport au seuil, elle ne le mesure pas. Un résultat proche de la limite se traite comme un dépassement."
        case .meter:
            return "Le testeur donne un pourcentage de composés polaires directement comparable au seuil de 25 %."
        }
    }
}

// MARK: - Lecture d'une bandelette

/// Résultat d'une bandelette, dans le vocabulaire des fabricants : une plage
/// de couleur, pas une valeur.
enum OilStripResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case good
    case borderline
    case discard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .good:       "Sous le seuil"
        case .borderline: "Proche du seuil"
        case .discard:    "Au-dessus du seuil"
        }
    }

    var detail: String {
        switch self {
        case .good:
            return "Le bain peut servir. Refaites un contrôle au rythme habituel."
        case .borderline:
            return "Le bain est en fin de vie. Filtrez et recontrôlez au prochain service, ou changez-le tout de suite."
        case .discard:
            return "Le bain est à changer. Une bandelette qui dépasse ne se rediscute pas."
        }
    }

    var systemImage: String {
        switch self {
        case .good:       "checkmark.circle"
        case .borderline: "exclamationmark.circle"
        case .discard:    "xmark.octagon"
        }
    }

    /// Seule la plage haute rend le bain non conforme. La plage intermédiaire
    /// est un avertissement : la porter en non-conformité remplirait le
    /// registre d'écarts que rien n'impose de traiter.
    var isCompliant: Bool { self != .discard }
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

    var checkedAt: Date = Date.now

    /// Friteuse concernée, saisie librement : toutes n'ont pas de nom officiel.
    var fryerName: String = ""

    /// Comment le bain a été contrôlé.
    ///
    /// Par défaut l'aspect : c'est ce que faisaient les enregistrements
    /// antérieurs à la bandelette, et les relire ainsi les décrit fidèlement.
    var methodRawValue: String = OilTestMethod.visual.rawValue

    /// Mesure au testeur, en pourcentage. `nil` hors contrôle au testeur.
    var polarCompounds: Double?

    /// Plage lue sur la bandelette. Vide hors contrôle à la bandelette.
    var stripResultRawValue: String = ""

    /// Seuil appliqué au moment du contrôle, figé pour l'historique.
    var polarCompoundsLimit: Double = 0

    var appearanceRawValue: String = ""
    var actionRawValue: String = ""

    var operatorName: String = ""
    var comment: String = ""

    var isCompliant: Bool = true
    var createdAt: Date = Date.now

    init(
        fryerName: String,
        checkedAt: Date = .now,
        method: OilTestMethod = .visual,
        polarCompounds: Double? = nil,
        stripResult: OilStripResult? = nil,
        appearance: OilAppearance = .clear,
        action: OilAction = .kept,
        operatorName: String = "",
        comment: String = "",
        createdAt: Date = .now
    ) {
        self.fryerName = fryerName
        self.checkedAt = checkedAt
        self.methodRawValue = method.rawValue
        self.polarCompounds = polarCompounds
        self.stripResultRawValue = stripResult?.rawValue ?? ""
        self.polarCompoundsLimit = OilCheckRecord.polarCompoundsLimit
        self.appearanceRawValue = appearance.rawValue
        self.actionRawValue = action.rawValue
        self.operatorName = operatorName
        self.comment = comment
        self.createdAt = createdAt

        // Conformité posée à la création puis recalculée à chaque
        // modification. Chaque méthode a son propre juge.
        switch method {
        case .meter:
            self.isCompliant = (polarCompounds ?? 0) <= OilCheckRecord.polarCompoundsLimit
        case .strip:
            self.isCompliant = stripResult?.isCompliant ?? true
        case .visual:
            self.isCompliant = !appearance.isSuspect
        }
    }
}

// MARK: - Logique métier

extension OilCheckRecord {

    var method: OilTestMethod {
        get { OilTestMethod(rawValue: methodRawValue) ?? .visual }
        set { methodRawValue = newValue.rawValue }
    }

    var stripResult: OilStripResult? {
        get { OilStripResult(rawValue: stripResultRawValue) }
        set { stripResultRawValue = newValue?.rawValue ?? "" }
    }

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

    /// Chaque méthode est jugée sur ce qu'elle produit réellement.
    func recomputeCompliance() {
        switch method {
        case .meter:
            isCompliant = (polarCompounds ?? 0) <= polarCompoundsLimit
        case .strip:
            isCompliant = stripResult?.isCompliant ?? true
        case .visual:
            isCompliant = !appearance.isSuspect
        }
    }

    /// Résultat affiché en une ligne, quelle que soit la méthode.
    var measurementLabel: String {
        switch method {
        case .meter:  return formattedPolarCompounds
        case .strip:  return stripResult?.label ?? "Bandelette non lue"
        case .visual: return "Aspect \(appearance.label.lowercased())"
        }
    }

    /// Une bandelette en plage intermédiaire n'est pas une non-conformité,
    /// mais laisser passer le service suivant sans rien faire en est une en
    /// devenir. L'écran le signale.
    var isBorderline: Bool {
        method == .strip && stripResult == .borderline
    }

    /// Un bain hors seuil qui n'a été ni filtré ni changé est un manquement.
    var needsAction: Bool {
        !isCompliant && action == .kept
    }

    var statusLabel: String {
        if isBorderline { return "À surveiller" }
        if isCompliant { return "Conforme" }

        switch method {
        case .meter:  return "Hors seuil"
        case .strip:  return "Bandelette au-dessus du seuil"
        case .visual: return "Aspect dégradé"
        }
    }
}
