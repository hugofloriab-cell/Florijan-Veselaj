//
//  RegulatoryReference.swift
//  HACCPPocket
//
//  Le socle réglementaire de l'application : ce qui vient d'un texte, ce qui
//  relève de l'usage professionnel, et la différence entre les deux.
//
//  ─────────────────────────────────────────────────────────────────────────
//  UNE RÈGLE, ET ELLE N'EST PAS NÉGOCIABLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Cette application sert de preuve lors d'un contrôle. Présenter un usage
//  professionnel comme une obligation légale y serait une faute : le jour où
//  un inspecteur demande « sur quel texte vous appuyez-vous ? », il faut
//  pouvoir répondre, ou dire honnêtement qu'il s'agit d'une pratique que
//  l'exploitant a choisie et qu'il assume.
//
//  Chaque valeur porte donc sa provenance :
//
//    • `.regulation` — la valeur figure dans un texte, qui est cité. Elle
//      est proposée telle quelle et ne se discute pas.
//    • `.practice`   — usage professionnel courant. L'application le propose
//      pour rendre service, mais la responsabilité reste celle de
//      l'exploitant : le règlement (CE) n° 852/2004 lui impose de fixer ses
//      propres durées de vie et de pouvoir les justifier.
//
//  Et dans tous les cas : une consigne du fabricant plus stricte que le
//  texte l'emporte sur le texte.
//

import Foundation

// MARK: - Provenance

enum RegulatoryOrigin: Sendable, Equatable {

    /// La valeur vient d'un texte, cité en clair.
    case regulation(String)

    /// Usage professionnel : proposé, modifiable, sous la responsabilité de
    /// l'exploitant.
    case practice

    var badge: String {
        switch self {
        case .regulation: "Réglementaire"
        case .practice:   "Usage professionnel"
        }
    }

    var systemImage: String {
        switch self {
        case .regulation: "checkmark.seal.fill"
        case .practice:   "person.crop.circle.badge.questionmark"
        }
    }

    var source: String? {
        switch self {
        case .regulation(let text): text
        case .practice:             nil
        }
    }

    var disclaimer: String {
        switch self {
        case .regulation:
            "Cette valeur figure dans un texte réglementaire. Une consigne du fabricant plus stricte l'emporte."
        case .practice:
            "Cette valeur est un usage professionnel courant, pas une obligation écrite. Le règlement (CE) n° 852/2004 vous laisse fixer vos propres durées, à condition de pouvoir les justifier. Ajustez-la si votre plan de maîtrise sanitaire dit autre chose."
        }
    }
}

// MARK: - Note explicative

/// Le « pourquoi » derrière un chiffre, affiché derrière une pastille ⓘ.
struct RegulatoryNote: Identifiable, Sendable, Equatable {
    let title: String
    let explanation: String
    let origin: RegulatoryOrigin

    var id: String { title }
}

// MARK: - Normes de conservation

/// Ce que contient une enceinte, et la température qui s'y applique.
///
/// Le tableau vient de l'annexe I de l'arrêté du 21 décembre 2009, qui fixe
/// les températures maximales de conservation des denrées animales et
/// d'origine animale.
enum ColdChainStandard: String, CaseIterable, Identifiable, Sendable {

    case mincedMeat
    case offal
    case meatPreparations
    case poultry
    case redMeat
    case freshFish
    case smokedFish
    case dairy
    case preparedDishes
    case rawVegetables
    case frozen
    case deepFrozen
    case hotHolding

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mincedMeat:       "Viandes hachées"
        case .offal:            "Abats"
        case .meatPreparations: "Préparations de viandes"
        case .poultry:          "Volailles, lapin, petit gibier"
        case .redMeat:          "Viandes de boucherie"
        case .freshFish:        "Produits de la pêche frais"
        case .smokedFish:       "Poissons fumés, saumurés"
        case .dairy:            "Produits laitiers frais"
        case .preparedDishes:   "Plats cuisinés, préparations élaborées à l'avance"
        case .rawVegetables:    "Fruits et légumes"
        case .frozen:           "Denrées congelées"
        case .deepFrozen:       "Surgelés, glaces"
        case .hotHolding:       "Maintien au chaud"
        }
    }

    /// Plage acceptée, bornes comprises.
    var range: ClosedRange<Double> {
        switch self {
        case .mincedMeat:       0...2
        case .offal:            0...3
        case .meatPreparations: 0...4
        case .poultry:          0...4
        case .redMeat:          0...7
        case .freshFish:        0...2
        case .smokedFish:       0...4
        case .dairy:            0...4
        case .preparedDishes:   0...3
        case .rawVegetables:    0...8
        case .frozen:           (-18)...(-12)
        case .deepFrozen:       (-24)...(-18)
        case .hotHolding:       63...90
        }
    }

    var systemImage: String {
        switch self {
        case .mincedMeat, .meatPreparations, .redMeat: "fork.knife"
        case .offal:            "heart"
        case .poultry:          "bird"
        case .freshFish, .smokedFish: "fish"
        case .dairy:            "drop"
        case .preparedDishes:   "takeoutbag.and.cup.and.straw"
        case .rawVegetables:    "carrot"
        case .frozen, .deepFrozen: "snowflake"
        case .hotHolding:       "flame"
        }
    }

    /// Les enceintes auxquelles cette norme peut s'appliquer.
    var applicableTypes: [EquipmentType] {
        switch self {
        case .frozen, .deepFrozen:
            [.negativeCold, .blastChiller]
        case .hotHolding:
            [.hotHolding]
        default:
            [.positiveCold, .coldRoom, .displayCase]
        }
    }

    var note: RegulatoryNote {
        RegulatoryNote(
            title: label,
            explanation: explanation,
            origin: origin
        )
    }

    private var origin: RegulatoryOrigin {
        switch self {
        case .rawVegetables:
            // Les fruits et légumes ne figurent pas dans l'annexe I, qui ne
            // couvre que les denrées animales : c'est un usage.
            .practice
        default:
            .regulation("Arrêté du 21 décembre 2009, annexe I")
        }
    }

    private var explanation: String {
        switch self {
        case .mincedMeat:
            "La viande hachée offre une surface immense aux bactéries : ce qui était en surface se retrouve à cœur. D'où la température la plus basse du tableau, +2 °C, et une DLC très courte."
        case .offal:
            "Les abats sont riches en sang et en enzymes, deux accélérateurs d'altération. Le texte impose +3 °C."
        case .meatPreparations:
            "Viande assaisonnée, marinée ou additionnée d'ingrédients : la manipulation a rompu l'intégrité du muscle, d'où +4 °C."
        case .poultry:
            "Les volailles portent fréquemment des salmonelles. +4 °C limite leur multiplication, mais ne les élimine pas : seule la cuisson à cœur le fait."
        case .redMeat:
            "Le muscle entier est protégé par sa surface : l'altération y est plus lente, ce qui autorise +7 °C. Découpée ou hachée, la même viande retombe à +4 ou +2 °C."
        case .freshFish:
            "Le poisson frais se conserve sous glace fondante, soit 0 à +2 °C. Au-delà, l'histamine se forme — et elle ne se détruit pas à la cuisson."
        case .smokedFish:
            "Le fumage et le salage ralentissent l'altération sans la stopper. Le risque Listeria reste présent, d'où +4 °C."
        case .dairy:
            "En l'absence de consigne du fabricant, +4 °C. Si l'étiquette indique une température plus basse, c'est elle qui s'applique."
        case .preparedDishes:
            "Un plat cuisiné a été manipulé, refroidi, parfois reconditionné : autant d'occasions de recontamination. +3 °C est la température des préparations culinaires élaborées à l'avance."
        case .rawVegetables:
            "Aucune température n'est imposée par l'annexe I, qui ne couvre que les denrées animales. La fourchette proposée correspond à l'usage ; adaptez-la à vos produits."
        case .frozen:
            "Congelé, à distinguer du surgelé : la congélation est plus lente et forme de plus gros cristaux. La chaîne du froid doit rester sous −12 °C."
        case .deepFrozen:
            "−18 °C est la référence du surgelé. À cette température, l'eau n'est plus disponible pour les micro-organismes : ils ne se multiplient plus."
        case .hotHolding:
            "Entre +10 et +63 °C se trouve la zone où les bactéries se multiplient le plus vite. Un plat maintenu au chaud doit donc rester au-dessus de +63 °C, sans interruption."
        }
    }
}

// MARK: - Verdict d'un relevé

/// Comment lire une température : la nuance entre « conforme » et « conforme
/// mais à la limite » vaut une alerte précoce, et c'est elle qui évite la
/// non-conformité du lendemain.
enum ReadingVerdict: Sendable, Equatable {

    case compliant
    case borderline
    case outOfRange

    /// Marge sous laquelle une valeur encore dans la plage est signalée.
    static let borderlineMargin: Double = 1.0

    static func evaluate(_ value: Double, in range: ClosedRange<Double>) -> ReadingVerdict {
        guard range.contains(value) else { return .outOfRange }

        let toLower = value - range.lowerBound
        let toUpper = range.upperBound - value

        if min(toLower, toUpper) <= borderlineMargin { return .borderline }
        return .compliant
    }

    var title: String {
        switch self {
        case .compliant:  "Conforme"
        case .borderline: "Conforme, mais à la limite"
        case .outOfRange: "Hors plage — action requise"
        }
    }

    var advice: String {
        switch self {
        case .compliant:
            "Rien à signaler. Le relevé part au registre tel quel."
        case .borderline:
            "La valeur est dans la plage, mais tout près d'une borne. Vérifiez la fermeture de la porte et le chargement de l'enceinte : c'est souvent la veille d'une non-conformité."
        case .outOfRange:
            "Un écart doit être suivi d'une action corrective écrite. L'application va vous guider."
        }
    }

    var systemImage: String {
        switch self {
        case .compliant:  "checkmark.seal.fill"
        case .borderline: "exclamationmark.circle.fill"
        case .outOfRange: "exclamationmark.triangle.fill"
        }
    }
}
