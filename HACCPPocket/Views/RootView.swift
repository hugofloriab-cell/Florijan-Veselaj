//
//  RootView.swift
//  HACCPPocket
//
//  Racine de la navigation. Chaque onglet correspond à un registre du Plan de
//  Maîtrise Sanitaire. La sélection passe par `AppRouter`, afin qu'un autre
//  écran puisse y renvoyer.
//

import SwiftUI
import SwiftData

struct RootView: View {

    @Environment(AppRouter.self) private var router

    /// La première configuration ne s'affiche qu'une fois.
    @AppStorage("haccp.didCompleteOnboarding") private var didCompleteOnboarding = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label(AppRouter.Tab.today.title, systemImage: AppRouter.Tab.today.systemImage) }
                .tag(AppRouter.Tab.today)

            TemperatureListView()
                .tabItem { Label(AppRouter.Tab.temperatures.title, systemImage: AppRouter.Tab.temperatures.systemImage) }
                .tag(AppRouter.Tab.temperatures)

            ProductListView()
                .tabItem { Label(AppRouter.Tab.products.title, systemImage: AppRouter.Tab.products.systemImage) }
                .tag(AppRouter.Tab.products)

            CleaningPlanView()
                .tabItem { Label(AppRouter.Tab.cleaning.title, systemImage: AppRouter.Tab.cleaning.systemImage) }
                .tag(AppRouter.Tab.cleaning)

            SettingsView()
                .tabItem { Label(AppRouter.Tab.settings.title, systemImage: AppRouter.Tab.settings.systemImage) }
                .tag(AppRouter.Tab.settings)
        }
        .tint(.brand)
        .fullScreenCover(isPresented: showsOnboarding) {
            OnboardingView()
        }
    }

    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { !didCompleteOnboarding },
            set: { didCompleteOnboarding = !$0 }
        )
    }
}

#Preview {
    RootView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(NotificationService.shared)
        .environment(SubscriptionManager.shared)
        .environment(AppRouter())
}
