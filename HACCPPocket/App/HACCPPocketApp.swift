//
//  HACCPPocketApp.swift
//  HACCPPocket
//
//  Point d'entrée de l'application. Le conteneur SwiftData est construit une
//  seule fois ici puis injecté dans l'environnement de toutes les vues.
//

import SwiftUI
import SwiftData

@main
struct HACCPPocketApp: App {

    /// Construit au lancement : si le store est illisible, mieux vaut échouer
    /// franchement que travailler sur une base corrompue.
    private let container: ModelContainer

    init() {
        do {
            container = try AppSchema.makeContainer()
        } catch {
            fatalError("Échec de l'initialisation du stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1_000, height: 700)
        #endif
    }
}
