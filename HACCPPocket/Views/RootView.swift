//
//  RootView.swift
//  HACCPPocket
//
//  Racine de la navigation, adaptée à la taille de l'écran.
//
//  Sur iPhone : une barre de cinq onglets, et les registres s'atteignent
//  depuis le tableau de bord. Sur iPad et Mac : une barre latérale qui porte
//  tout, parce qu'un écran de cette taille n'a aucune raison de cacher la
//  moitié de l'application derrière un tableau de bord.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {

    @Environment(AppRouter.self) private var router
    @Environment(InspectorAccess.self) private var inspector
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// La première configuration ne s'affiche qu'une fois.
    @AppStorage("haccp.didCompleteOnboarding") private var didCompleteOnboarding = false

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if inspector.isActive {
                // Le verrouillage ne consiste pas à désactiver des boutons :
                // l'application est remplacée par une consultation, où il n'y
                // en a aucun.
                InspectorModeView()
            } else if usesSidebar {
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

        return TabView(selection: $router.tabSelection) {
            ForEach(AppRouter.Destination.tabCases) { destination in
                screen(for: destination)
                    .tabItem { Label(destination.title, systemImage: destination.systemImage) }
                    .tag(destination)
            }
        }
        .tint(.brand)
    }

    // MARK: - iPad et Mac

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
        } detail: {
            // `id` force la reconstruction du détail : sans lui, la pile de
            // navigation de l'écran précédent survivrait au changement.
            screen(for: router.selection)
                .id(router.selection)
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

            ForEach(AppRouter.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.destinations) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(BrandAssets.productName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `List` attend une sélection optionnelle ; le routeur, lui, a toujours un
    /// écran courant. On ignore donc la désélection.
    private var sidebarSelection: Binding<AppRouter.Destination?> {
        Binding(
            get: { router.selection },
            set: { newValue in
                if let newValue { router.selection = newValue }
            }
        )
    }

    // MARK: - Écrans

    /// Les écrans de registre sont normalement empilés depuis le tableau de
    /// bord et n'apportent donc pas leur propre `NavigationStack`. Présentés
    /// directement depuis la barre latérale, il faut le leur fournir.
    @ViewBuilder
    private func screen(for destination: AppRouter.Destination) -> some View {
        switch destination {
        case .today:
            DashboardView()
        case .temperatures:
            TemperatureListView()
        case .products:
            ProductListView()
        case .cleaning:
            CleaningPlanView()
        case .settings:
            SettingsView()

        case .registers:
            // Cet écran apporte désormais sa propre pile de navigation.
            RegistersHubView()
        case .menu:
            NavigationStack { MenuListView() }
        case .history:
            NavigationStack { HistoryView() }
        case .report:
            NavigationStack { ReportView() }
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
        .environment(InspectorAccess.shared)
        .environment(EstablishmentDirectory.shared)
        .environment(RoleSession.shared)
}
