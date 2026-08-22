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

    /// Construit au lancement : si le store est illisible, mieux vaut échouer
    /// franchement que travailler sur une base corrompue.
    private let container: ModelContainer

    @State private var preferences: UserPreferences
    @State private var notificationService: NotificationService
    @State private var subscription: SubscriptionManager

    init() {
        do {
            container = try AppSchema.makeContainer()
        } catch {
            fatalError("Échec de l'initialisation du stockage local : \(error)")
        }

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
