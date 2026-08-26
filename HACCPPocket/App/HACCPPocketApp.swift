//
//  HACCPPocketApp.swift
//  HACCPPocket
//
//  Point d'entrée. Construit le conteneur SwiftData, injecte les réglages et le
//  service de notifications dans l'environnement, puis reprogramme les rappels
//  quotidiens à chaque lancement.
//

import SwiftUI
import SwiftData

@main
struct HACCPPocketApp: App {

    private let container: ModelContainer

    /// État de l'ouverture du stockage. Une base illisible ne fait plus
    /// planter le lancement : elle est mise de côté et l'utilisateur est
    /// prévenu depuis les réglages.
    private let storeOutcome: AppSchema.StoreOutcome

    @State private var preferences: UserPreferences
    @State private var notificationService: NotificationService
    @State private var subscription: SubscriptionManager
    @State private var router = AppRouter()
    @State private var inspector = InspectorAccess.shared

    init() {
        let store = AppSchema.openStore()
        container = store.container
        storeOutcome = store.outcome

        _preferences = State(initialValue: UserPreferences.shared)
        _notificationService = State(initialValue: NotificationService.shared)
        _subscription = State(initialValue: SubscriptionManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, AppFormatters.locale)
                .environment(preferences)
                .environment(notificationService)
                .environment(subscription)
                .environment(router)
                .environment(inspector)
                .environment(\.storeOutcome, storeOutcome)
                .task {
                    // Les rappels sont reprogrammés à chaque lancement : ils
                    // suivent ainsi les réglages sans code de synchronisation.
                    await notificationService.applySchedule(from: preferences)
                }
                .task {
                    await subscription.configure()
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1_000, height: 700)
        #endif
    }
}
