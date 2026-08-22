//
//  RootView.swift
//  HACCPPocket
//
//  Racine de la navigation. Une barre d'onglets : chaque onglet correspond à
//  un registre du Plan de Maîtrise Sanitaire.
//

import SwiftUI
import SwiftData

struct RootView: View {

    /// Onglet sélectionné, conservé entre deux lancements.
    @SceneStorage("haccp.selectedTab") private var selection: String = Tab.today.rawValue

    private enum Tab: String, CaseIterable {
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

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label(Tab.today.title, systemImage: Tab.today.systemImage) }
                .tag(Tab.today.rawValue)

            TemperatureListView()
                .tabItem { Label(Tab.temperatures.title, systemImage: Tab.temperatures.systemImage) }
                .tag(Tab.temperatures.rawValue)

            ProductListView()
                .tabItem { Label(Tab.products.title, systemImage: Tab.products.systemImage) }
                .tag(Tab.products.rawValue)

            CleaningPlanView()
                .tabItem { Label(Tab.cleaning.title, systemImage: Tab.cleaning.systemImage) }
                .tag(Tab.cleaning.rawValue)

            SettingsView()
                .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.systemImage) }
                .tag(Tab.settings.rawValue)
        }
        .tint(.teal)
    }
}

#Preview {
    RootView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(NotificationService.shared)
}
