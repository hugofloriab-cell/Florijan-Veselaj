//
//  RootView.swift
//  HACCPPocket
//
//  Racine de la navigation. Une barre d'onglets : chaque onglet correspond à
//  un registre du Plan de Maîtrise Sanitaire.
//

import SwiftUI

struct RootView: View {

    /// Onglet sélectionné, conservé entre deux lancements.
    @SceneStorage("haccp.selectedTab") private var selection: String = Tab.today.rawValue

    private enum Tab: String, CaseIterable {
        case today
        case temperatures

        var title: String {
            switch self {
            case .today:        "Aujourd'hui"
            case .temperatures: "Températures"
            }
        }

        var systemImage: String {
            switch self {
            case .today:        "checklist"
            case .temperatures: "thermometer.medium"
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
