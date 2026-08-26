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

    @State private var preferences: UserPreferences
    @State private var notificationService: NotificationService
    @State private var subscription: SubscriptionManager
    @State private var router = AppRouter()
    @State private var inspector = InspectorAccess.shared
    @State private var directory = EstablishmentDirectory.shared
    @State private var roles = RoleSession.shared

    init() {
        _preferences = State(initialValue: UserPreferences.shared)
        _notificationService = State(initialValue: NotificationService.shared)
        _subscription = State(initialValue: SubscriptionManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            // Le conteneur SwiftData est ouvert par `AppRootView` : il change
            // avec l'établissement actif.
            AppRootView()
                .environment(\.locale, AppFormatters.locale)
                .environment(preferences)
                .environment(notificationService)
                .environment(subscription)
                .environment(router)
                .environment(inspector)
                .environment(directory)
                .environment(roles)
                .task {
                    // Les rappels sont reprogrammés à chaque lancement : ils
                    // suivent ainsi les réglages sans code de synchronisation.
                    await notificationService.applySchedule(from: preferences)
                }
                .task {
                    await subscription.configure()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 700)
        #endif
    }
}
