//
//  Dish.swift
//  HACCPPocket
//
//  Un plat de la carte, et les allergènes qu'il contient.
//
//  L'obligation d'information du consommateur porte sur ce qui est servi,
//  pas sur ce qui est stocké : un contrôleur demande la fiche allergènes de
//  la carte, pas celle du frigo. C'est ce modèle qui y répond.
//

import Foundation
import SwiftData

// MARK: - Catégorie

enum DishCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case starter
    case main
    case side
    case dessert
    case drink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .starter: "Entrées"
        case .main:    "Plats"
        case .side:    "Accompagnements"
        case .dessert: "Desserts"
        case .drink:   "Boissons"
        }
    }

    /// Singulier, pour les formulaires.
    var singularLabel: String {
        switch self {
        case .starter: "Entrée"
        case .main:    "Plat"
        case .side:    "Accompagnement"
        case .dessert: "Dessert"
        case .drink:   "Boisson"
        }
    }

    var systemImage: String {
        switch self {
        case .starter: "leaf"
        case .main:    "fork.knife"
        case .side:    "carrot"
        case .dessert: "birthday.cake"
        case .drink:   "cup.and.saucer"
        }
    }

    /// Ordre d'apparition sur la carte imprimée.
    var sortWeight: Int {
        switch self {
        case .starter: 0
        case .main:    1
        case .side:    2
        case .dessert: 3
        case .drink:   4
        }
    }
}

// MARK: - Plat

@Model
final class Dish {

    /// Toutes les propriétés portent une valeur par défaut : c'est une
    /// exigence de la synchronisation iCloud, qui ne sait pas représenter un
    /// champ obligatoire sans valeur.
    var name: String = ""

    var categoryRawValue: String = DishCategory.main.rawValue

    /// Description libre affichée sur la carte.
    var summary: String = ""

    /// Composition, en texte libre. Elle n'est pas obligatoire, mais c'est
    /// elle qui permet de justifier les allergènes cochés en cas de contrôle.
    var composition: String = ""

    /// Allergènes présents, stockés en valeurs brutes : SwiftData ne sait pas
    /// filtrer sur une énumération, et un tableau de chaînes reste lisible
    /// dans un export comme dans une sauvegarde.
    var allergenRawValues: [String] = []

    /// Un plat retiré de la carte reste dans la base : l'historique des
    /// fiches allergènes doit pouvoir être reconstitué.
    var isAvailable: Bool = true

    /// Mention « fait maison », au sens du décret n° 2014-797.
    var isHomemade: Bool = true

    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        name: String = "",
        category: DishCategory = .main,
        summary: String = "",
        composition: String = "",
        allergens: Set<Allergen> = [],
        isAvailable: Bool = true,
        isHomemade: Bool = true,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.name = name
        self.categoryRawValue = category.rawValue
        self.summary = summary
        self.composition = composition
        self.allergenRawValues = Allergen.rawValues(from: allergens)
        self.isAvailable = isAvailable
        self.isHomemade = isHomemade
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: - Accès typé

    var category: DishCategory {
        get { DishCategory(rawValue: categoryRawValue) ?? .main }
        set { categoryRawValue = newValue.rawValue }
    }

    var allergens: Set<Allergen> {
        get { Allergen.set(from: allergenRawValues) }
        set { allergenRawValues = Allergen.rawValues(from: newValue) }
    }

    // MARK: - Affichage

    var displayName: String {
        name.isEmpty ? "Plat sans nom" : name
    }

    /// Ex. « Gluten, Lait, Œufs ».
    var allergenSummary: String {
        Allergen.summary(of: allergens)
    }

    /// Un plat sans allergène coché est ambigu : est-il vraiment exempt, ou
    /// la fiche n'a-t-elle jamais été remplie ? Cette distinction est portée
    /// par `composition` — un plat documenté et sans allergène est valide.
    var needsAllergenReview: Bool {
        allergenRawValues.isEmpty && composition.isEmpty
    }

    func touch(at date: Date = .now) {
        updatedAt = date
    }
}
