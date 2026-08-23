//
//  RootView.swift
//  HACCPPocket
//
//  Racine de la navigation, adaptée à la taille de l'écran.
//
//  Sur iPhone : une barre d'onglets. Sur iPad et Mac : une barre latérale,
//  qui est la convention de ces plateformes et libère la hauteur d'écran.
//  La sélection passe par `AppRouter` dans les deux cas, si bien qu'un
//  raccourci du tableau de bord fonctionne quelle que soit la présentation.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {

    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// La première configuration ne s'affiche qu'une fois.
    @AppStorage("haccp.didCompleteOnboarding") private var didCompleteOnboarding = false

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if usesSidebar {
                splitLayout
            } else {
                tabLayout
            }
        }
        .fullScreenCover(isPresented: showsOnboarding) {
            OnboardingView()
        }
    }

    /// Un iPhone Pro Max en paysage passe en classe « regular » : sans le test
    /// d'appareil, il basculerait en présentation iPad, ce qui n'a pas de sens
    /// sur un écran de cette taille.
    private var usesSidebar: Bool {
        #if canImport(UIKit)
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone
        #else
        horizontalSizeClass == .regular
        #endif
    }

    // MARK: - iPhone

    private var tabLayout: some View {
        @Bindable var router = router

        return TabView(selection: $router.selectedTab) {
            ForEach(AppRouter.Tab.allCases, id: \.self) { tab in
                destination(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.brand)
    }

    // MARK: - iPad et Mac

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            destination(for: router.selectedTab)
                .id(router.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.brand)
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                HStack(spacing: 12) {
                    BrandLogo(size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(BrandAssets.productName)
                            .font(.subheadline.weight(.semibold))
                        Text("Traçabilité sanitaire")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .selectionDisabled()
            }

            Section("Registres") {
                ForEach(AppRouter.Tab.allCases, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("HACCP Pocket")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `List` attend une sélection optionnelle ; le routeur, lui, a toujours un
    /// onglet courant. On ignore donc la désélection.
    private var sidebarSelection: Binding<AppRouter.Tab?> {
        Binding(
            get: { router.selectedTab },
            set: { newValue in
                if let newValue { router.selectedTab = newValue }
            }
        )
    }

    // MARK: - Écrans

    @ViewBuilder
    private func destination(for tab: AppRouter.Tab) -> some View {
        switch tab {
        case .today:        DashboardView()
        case .temperatures: TemperatureListView()
        case .products:     ProductListView()
        case .cleaning:     CleaningPlanView()
        case .settings:     SettingsView()
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
