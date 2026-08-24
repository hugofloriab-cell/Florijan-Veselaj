//
//  AppRouter.swift
//  HACCPPocket
//
//  Navigation partagée entre les écrans. Sert notamment à ce qu'une ligne du
//  tableau de bord renvoie sur l'écran concerné : c'est le geste attendu quand
//  on lit « il vous reste 3 opérations de nettoyage ».
//
//  Un iPhone n'affiche que cinq onglets ; un iPad a une barre latérale qui
//  peut tout porter. Le routeur décrit donc l'ensemble des destinations, et
//  chaque présentation y puise ce qu'elle sait montrer.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {

    // MARK: - Destinations

    enum Destination: String, CaseIterable, Hashable, Identifiable {

        // Le quotidien : ces quatre écrans plus les réglages forment la barre
        // d'onglets de l'iPhone.
        case today
        case temperatures
        case products
        case cleaning

        // Les registres : accessibles depuis le tableau de bord sur iPhone,
        // directement dans la barre latérale sur iPad et Mac.
        case registers
        case menu
        case history
        case report

        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today:        "Aujourd'hui"
            case .temperatures: "Températures"
            case .products:     "Produits"
            case .cleaning:     "Nettoyage"
            case .registers:    "Registres"
            case .menu:         "Ma carte"
            case .history:      "Historique"
            case .report:       "Registre mensuel"
            case .settings:     "Réglages"
            }
        }

        var systemImage: String {
            switch self {
            case .today:        "checklist"
            case .temperatures: "thermometer.medium"
            case .products:     "shippingbox"
            case .cleaning:     "sparkles"
            case .registers:    "folder"
            case .menu:         "fork.knife"
            case .history:      "clock.arrow.circlepath"
            case .report:       "doc.text"
            case .settings:     "gearshape"
            }
        }

        /// Les cinq écrans qui tiennent dans une barre d'onglets. Au-delà, iOS
        /// replie le reste dans un onglet « Plus » que personne ne va chercher.
        static let tabCases: [Destination] = [
            .today, .temperatures, .products, .cleaning, .settings
        ]

        var isTab: Bool { Destination.tabCases.contains(self) }
    }

    // MARK: - Barre latérale

    struct SidebarSection: Identifiable {
        let title: String
        let destinations: [Destination]
        var id: String { title }
    }

    /// Découpage de la barre latérale : le quotidien d'un côté, ce qu'on sort
    /// pour un contrôle de l'autre.
    static let sidebarSections: [SidebarSection] = [
        SidebarSection(
            title: "Au quotidien",
            destinations: [.today, .temperatures, .products, .cleaning]
        ),
        SidebarSection(
            title: "Registres",
            destinations: [.registers, .menu, .history, .report]
        ),
        SidebarSection(
            title: "Configuration",
            destinations: [.settings]
        )
    ]

    // MARK: - Sélection

    var selection: Destination = .today

    /// La barre d'onglets ne connaît que cinq écrans. On lui présente donc
    /// toujours une valeur qu'elle sait afficher, quitte à retomber sur
    /// l'accueil si la sélection vient de la barre latérale.
    var tabSelection: Destination {
        get { selection.isTab ? selection : .today }
        set { selection = newValue }
    }

    func show(_ destination: Destination) {
        selection = destination
    }
}
