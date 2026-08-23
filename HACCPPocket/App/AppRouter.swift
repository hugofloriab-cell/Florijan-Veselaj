//
//  AppRouter.swift
//  HACCPPocket
//
//  Navigation partagée entre les écrans. Sert notamment à ce qu'une ligne du
//  tableau de bord renvoie sur l'onglet concerné : c'est le geste attendu quand
//  on lit « il vous reste 3 opérations de nettoyage ».
//

import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {

    enum Tab: String, CaseIterable {
        case today
        case temperatures
        case products
        case cleaning
        case settings

        var title: String {
            switch self {
            case .today:        "Aujourd'hui"
            case .temperatures: "Températures"
            case .products:     "Produits"
            case .cleaning:     "Nettoyage"
            case .settings:     "Réglages"
            }
        }

        var systemImage: String {
            switch self {
            case .today:        "checklist"
            case .temperatures: "thermometer.medium"
            case .products:     "shippingbox"
            case .cleaning:     "sparkles"
            case .settings:     "gearshape"
            }
        }
    }

    var selectedTab: Tab = .today

    func show(_ tab: Tab) {
        selectedTab = tab
    }
}
