//
//  Allergen.swift
//  HACCPPocket
//
//  Les quatorze allergènes à déclaration obligatoire.
//
//  Liste fixée par l'annexe II du règlement (UE) n° 1169/2011, dit « INCO ».
//  Elle ne bouge pas au gré des modes : c'est une liste réglementaire fermée,
//  et l'information du consommateur porte sur ces quatorze substances, ni
//  plus, ni moins.
//

import Foundation

enum Allergen: String, Codable, CaseIterable, Identifiable, Sendable {

    case gluten
    case crustaceans
    case eggs
    case fish
    case peanuts
    case soybeans
    case milk
    case nuts
    case celery
    case mustard
    case sesame
    case sulphites
    case lupin
    case molluscs

    var id: String { rawValue }

    /// Intitulé réglementaire, tel qu'il doit apparaître sur la fiche.
    var label: String {
        switch self {
        case .gluten:      "Céréales contenant du gluten"
        case .crustaceans: "Crustacés"
        case .eggs:        "Œufs"
        case .fish:        "Poissons"
        case .peanuts:     "Arachides"
        case .soybeans:    "Soja"
        case .milk:        "Lait"
        case .nuts:        "Fruits à coque"
        case .celery:      "Céleri"
        case .mustard:     "Moutarde"
        case .sesame:      "Graines de sésame"
        case .sulphites:   "Anhydride sulfureux et sulfites"
        case .lupin:       "Lupin"
        case .molluscs:    "Mollusques"
        }
    }

    /// Version courte, pour les en-têtes de colonnes du tableau imprimé.
    var shortLabel: String {
        switch self {
        case .gluten:      "Gluten"
        case .crustaceans: "Crustacés"
        case .eggs:        "Œufs"
        case .fish:        "Poissons"
        case .peanuts:     "Arachides"
        case .soybeans:    "Soja"
        case .milk:        "Lait"
        case .nuts:        "Fruits à coque"
        case .celery:      "Céleri"
        case .mustard:     "Moutarde"
        case .sesame:      "Sésame"
        case .sulphites:   "Sulfites"
        case .lupin:       "Lupin"
        case .molluscs:    "Mollusques"
        }
    }

    /// Précision réglementaire. C'est elle qui évite les oublis : beaucoup de
    /// cuisiniers ignorent que l'épeautre est du gluten ou que la sauce
    /// Worcestershire contient du poisson.
    var detail: String {
        switch self {
        case .gluten:      "Blé, seigle, orge, avoine, épeautre, kamut"
        case .crustaceans: "Crevettes, crabes, langoustines, homard"
        case .eggs:        "Y compris mayonnaise, pâtes fraîches, meringue"
        case .fish:        "Y compris sauce Worcestershire, bouillons, tapenade"
        case .peanuts:     "Cacahuètes, huile d'arachide non raffinée"
        case .soybeans:    "Sauce soja, tofu, lécithine de soja"
        case .milk:        "Y compris lactose, beurre, crème, fromages"
        case .nuts:        "Amandes, noisettes, noix, pistaches, noix de cajou"
        case .celery:      "Branche, rave, sel de céleri, bouillons"
        case .mustard:     "Graines, condiment, vinaigrettes"
        case .sesame:      "Graines, huile, tahini, pain aux graines"
        case .sulphites:   "Au-delà de 10 mg/kg : vin, fruits secs, charcuterie"
        case .lupin:       "Farine de lupin, présente dans certaines pâtisseries"
        case .molluscs:    "Moules, huîtres, calamars, escargots, coquilles"
        }
    }

    var systemImage: String {
        switch self {
        case .gluten:      "laurel.leading"
        case .crustaceans: "fish"
        case .eggs:        "oval"
        case .fish:        "fish"
        case .peanuts:     "circle.grid.2x2"
        case .soybeans:    "leaf"
        case .milk:        "drop"
        case .nuts:        "circle.hexagongrid"
        case .celery:      "leaf.arrow.trianglehead.clockwise"
        case .mustard:     "drop.halffull"
        case .sesame:      "circle.dotted"
        case .sulphites:   "wineglass"
        case .lupin:       "camera.macro"
        case .molluscs:    "shell"
        }
    }

    // MARK: - Conversions

    /// Reconstruit un ensemble d'allergènes depuis les valeurs stockées, en
    /// ignorant silencieusement une valeur inconnue : une base écrite par une
    /// version plus récente ne doit jamais faire échouer la lecture.
    static func set(from rawValues: [String]) -> Set<Allergen> {
        Set(rawValues.compactMap { Allergen(rawValue: $0) })
    }

    /// Sérialisation stable, dans l'ordre réglementaire, pour que deux fiches
    /// identiques produisent le même enregistrement.
    static func rawValues(from allergens: Set<Allergen>) -> [String] {
        Allergen.allCases.filter { allergens.contains($0) }.map(\.rawValue)
    }

    /// Liste lisible, ex. « Gluten, Lait, Œufs ».
    static func summary(of allergens: Set<Allergen>) -> String {
        let ordered = Allergen.allCases.filter { allergens.contains($0) }
        return ordered.isEmpty ? "Aucun" : ordered.map(\.shortLabel).joined(separator: ", ")
    }
}
