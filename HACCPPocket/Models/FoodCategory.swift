//
//  FoodCategory.swift
//  HACCPPocket
//
//  Les familles d'aliments et leur durée de vie après ouverture.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CE FICHIER N'EST PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Il n'existe aucun tableau réglementaire des DLC secondaires. Le règlement
//  (CE) n° 852/2004 pose le principe inverse : c'est à l'exploitant de fixer
//  les durées de vie de ses préparations, et de pouvoir les justifier — par
//  un guide de bonnes pratiques de sa filière, par des analyses, ou par son
//  plan de maîtrise sanitaire.
//
//  Les durées ci-dessous sont donc des USAGES professionnels largement
//  répandus, proposés pour éviter le calcul mental et la page blanche. Elles
//  sont toutes modifiables, et l'application le dit à l'utilisateur au lieu
//  de les présenter comme la loi.
//
//  La seule règle vraiment intangible est ailleurs : on ne prolonge jamais un
//  produit au-delà de la DLC imprimée par le fournisseur.
//

import Foundation

enum FoodCategory: String, CaseIterable, Identifiable, Sendable {

    case rawMeat
    case rawFish
    case cookedDish
    case charcuterie
    case openedDairy
    case cheese
    case cutVegetables
    case sauce
    case openedCan
    case vacuumPacked
    case pastry
    case dryGoods

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rawMeat:        "Viande crue"
        case .rawFish:        "Poisson cru"
        case .cookedDish:     "Plat cuisiné maison"
        case .charcuterie:    "Charcuterie tranchée"
        case .openedDairy:    "Produit laitier ouvert"
        case .cheese:         "Fromage à la coupe"
        case .cutVegetables:  "Légumes crus découpés"
        case .sauce:          "Sauce ou fond maison"
        case .openedCan:      "Conserve ouverte"
        case .vacuumPacked:   "Sous-vide entamé"
        case .pastry:         "Pâtisserie, crème"
        case .dryGoods:       "Épicerie sèche ouverte"
        }
    }

    /// Durée de vie proposée après ouverture ou fabrication, en jours.
    var shelfLifeDays: Int {
        switch self {
        case .rawMeat:        1
        case .rawFish:        1
        case .cookedDish:     3
        case .charcuterie:    3
        case .openedDairy:    3
        case .cheese:         5
        case .cutVegetables:  2
        case .sauce:          3
        case .openedCan:      2
        case .vacuumPacked:   2
        case .pastry:         1
        case .dryGoods:       30
        }
    }

    var systemImage: String {
        switch self {
        case .rawMeat:        "fork.knife"
        case .rawFish:        "fish"
        case .cookedDish:     "takeoutbag.and.cup.and.straw"
        case .charcuterie:    "rectangle.stack"
        case .openedDairy:    "drop"
        case .cheese:         "triangle"
        case .cutVegetables:  "carrot"
        case .sauce:          "drop.halffull"
        case .openedCan:      "cylinder"
        case .vacuumPacked:   "shippingbox"
        case .pastry:         "birthday.cake"
        case .dryGoods:       "bag"
        }
    }

    /// Zone de stockage la plus probable : elle pré-remplit le formulaire.
    var suggestedStorage: StorageZone {
        switch self {
        case .dryGoods: .ambient
        default:        .positiveCold
        }
    }

    /// Le « pourquoi » de la durée, derrière la pastille ⓘ.
    var note: RegulatoryNote {
        RegulatoryNote(title: label, explanation: explanation, origin: .practice)
    }

    private var explanation: String {
        switch self {
        case .rawMeat:
            "Une viande crue entamée a été manipulée et exposée à l'air. Vingt-quatre heures est la durée d'usage ; au-delà, l'altération devient visible et la charge bactérienne trop élevée pour une cuisson à point."
        case .rawFish:
            "Le poisson cru est la denrée la plus fragile de la cuisine. Passé un jour, le risque d'histamine devient réel — et l'histamine ne se détruit pas à la cuisson."
        case .cookedDish:
            "Trois jours après fabrication, c'est l'usage le plus répandu pour un plat cuisiné refroidi correctement et conservé à +3 °C. Il suppose un refroidissement rapide en règle : sans lui, la durée ne vaut rien."
        case .charcuterie:
            "Trancher expose une surface neuve à l'air et aux mains. La charcuterie tranchée ne se conserve pas comme la pièce entière dont elle vient."
        case .openedDairy:
            "Après ouverture, la protection du conditionnement n'existe plus. Trois jours est l'usage, sauf mention contraire du fabricant — qui l'emporte toujours."
        case .cheese:
            "Les fromages affinés supportent mieux le temps que les frais : leur acidité et leur faible humidité freinent les bactéries. Cinq jours pour un fromage à la coupe correctement filmé."
        case .cutVegetables:
            "Découper un légume libère son eau et ses sucres, et met à nu une surface que la terre a pu contaminer. Deux jours, et seulement après lavage et désinfection."
        case .sauce:
            "Une sauce maison contient souvent œuf, crème ou fond : trois ingrédients qui font d'elle un milieu de culture idéal. Trois jours au maximum, à +3 °C."
        case .openedCan:
            "Une conserve ouverte n'est plus une conserve. Transvasez systématiquement dans un contenant alimentaire : le métal nu s'oxyde au contact de l'air et migre dans l'aliment."
        case .vacuumPacked:
            "Le sous-vide entamé perd tout l'intérêt du sous-vide. Il redevient un produit ordinaire, avec une durée très courte."
        case .pastry:
            "Crème pâtissière, chantilly, mousse : ce sont des préparations à base d'œuf et de lait non cuites ou peu cuites. Un jour, pas deux."
        case .dryGoods:
            "Farines, semoules, légumes secs : le risque n'est pas bactérien mais lié aux insectes et au rancissement. Refermez hermétiquement et datez l'ouverture."
        }
    }
}
