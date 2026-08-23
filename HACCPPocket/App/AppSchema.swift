//
//  AppSchema.swift
//  HACCPPocket
//
//  Point unique de construction du `ModelContainer`. Tout est strictement
//  local : aucune configuration CloudKit, aucun réseau, donc aucun coût
//  d'infrastructure.
//
//  Les versions du schéma et le plan de migration vivent dans
//  `SchemaVersions.swift` — c'est là qu'il faut aller avant de toucher au
//  moindre `@Model`.
//

import Foundation
import SwiftData

enum AppSchema {

    // MARK: - Version courante

    /// La version de schéma que l'application utilise aujourd'hui.
    /// Une seule ligne à changer le jour où l'on passe en V2.
    static let currentVersion: any VersionedSchema.Type = HACCPSchemaV1.self

    /// Toutes les entités persistées. Ajouter un modèle dans la version de
    /// schéma courante, et nulle part ailleurs.
    static var models: [any PersistentModel.Type] {
        currentVersion.models
    }

    static var schema: Schema {
        Schema(versionedSchema: currentVersion)
    }

    /// Ex. « v1.0.0 ». Affiché dans les réglages : en cas de problème chez un
    /// utilisateur, c'est la première chose à lui demander.
    static var versionDescription: String {
        let version = currentVersion.versionIdentifier
        return "v\(version.major).\(version.minor).\(version.patch)"
    }

    // MARK: - Emplacement du store

    /// Configuration de production. On la construit à un seul endroit pour que
    /// la procédure de secours vise exactement le fichier qu'ouvre SwiftData,
    /// sans avoir à deviner son emplacement.
    private static var productionConfiguration: ModelConfiguration {
        ModelConfiguration("HACCPPocket", schema: schema)
    }

    /// Emplacement réel du fichier de base de données, lu depuis la
    /// configuration elle-même plutôt que reconstruit à la main.
    static var storeURL: URL {
        productionConfiguration.url
    }

    /// SQLite écrit deux fichiers annexes à côté du store. Les oublier lors
    /// d'une mise à l'écart laisserait une base à moitié déplacée, donc
    /// illisible dans les deux emplacements.
    private static var storeFileURLs: [URL] {
        let store = storeURL
        return [
            store,
            store.appendingPathExtension("shm"),
            store.appendingPathExtension("wal")
        ]
    }

    // MARK: - Ouverture

    /// Résultat de l'ouverture du stockage : l'application a besoin de savoir
    /// si tout s'est bien passé pour pouvoir prévenir l'utilisateur.
    enum StoreOutcome: Equatable, Sendable {
        /// Ouverture normale, données intactes.
        case opened
        /// La base existante était illisible. Elle a été mise de côté sous ce
        /// nom de fichier, et l'application repart sur une base vierge.
        case recovered(archivedFileName: String)
        /// Même une base neuve n'a pas pu être créée sur le disque.
        /// L'application fonctionne en mémoire : rien ne sera conservé.
        case memoryFallback
    }

    struct StoreResult {
        let container: ModelContainer
        let outcome: StoreOutcome
    }

    /// Ouvre le stockage de production.
    ///
    /// Aucun chemin de ce code ne fait planter l'application sur une base
    /// abîmée. Une base illisible est mise de côté — jamais supprimée — pour
    /// qu'elle reste récupérable, et l'application se relance sur une base
    /// vierge plutôt que de boucler sur un crash au lancement.
    @MainActor
    static func openStore() -> StoreResult {

        // 1. Tentative normale, avec le plan de migration.
        if let container = try? makeContainer() {
            SeedData.seedIfNeeded(in: container.mainContext)
            return StoreResult(container: container, outcome: .opened)
        }

        // 2. La migration a échoué. On écarte la base sans la détruire.
        let archivedName = (try? setStoreAside())?.lastPathComponent

        if let container = try? makeContainer() {
            SeedData.seedAfterRecovery(in: container.mainContext)
            return StoreResult(
                container: container,
                outcome: .recovered(archivedFileName: archivedName ?? storeURL.lastPathComponent)
            )
        }

        // 3. Le disque lui-même refuse. L'application doit quand même
        //    s'ouvrir : mieux vaut une session sans persistance qu'un écran
        //    noir, l'utilisateur sera prévenu dans les réglages.
        if let container = try? makeContainer(inMemory: true) {
            // On amorce sans toucher au drapeau : l'incident peut être
            // passager, et le vrai store devra rester amorcé une seule fois.
            SeedData.populate(context: container.mainContext, includeSampleActivity: false)
            return StoreResult(container: container, outcome: .memoryFallback)
        }

        // 4. Cas théorique : un conteneur en mémoire ne peut échouer que si le
        //    schéma lui-même est invalide, c'est-à-dire une erreur de
        //    développement à corriger avant toute publication.
        fatalError("Schéma SwiftData invalide : le conteneur en mémoire n'a pas pu être créé.")
    }

    /// Construction nue du conteneur, sans filet.
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : productionConfiguration

        return try ModelContainer(
            for: schema,
            migrationPlan: HACCPMigrationPlan.self,
            configurations: configuration
        )
    }

    // MARK: - Mise à l'écart d'une base illisible

    /// Renomme la base défaillante avec un horodatage et renvoie sa nouvelle
    /// adresse. Rien n'est supprimé : ces fichiers restent récupérables.
    @discardableResult
    static func setStoreAside(at date: Date = .now) throws -> URL {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let originalName = storeURL.lastPathComponent              // HACCPPocket.store
        let archivedName = "HACCPPocket-illisible-\(AppFormatters.fileStamp(date)).store"

        for source in storeFileURLs where fileManager.fileExists(atPath: source.path) {
            // HACCPPocket.store.wal devient HACCPPocket-illisible-….store.wal :
            // le trio reste cohérent si quelqu'un doit rouvrir la base.
            let targetName = source.lastPathComponent
                .replacingOccurrences(of: originalName, with: archivedName)
            let target = directory.appending(path: targetName)

            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: source, to: target)
        }

        return directory.appending(path: archivedName)
    }

    // MARK: - Prévisualisations

    /// Conteneur volatil utilisé par les `#Preview` : jeu de données complet,
    /// jamais écrit sur disque.
    @MainActor
    static let preview: ModelContainer = {
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            SeedData.populate(context: container.mainContext, includeSampleActivity: true)
            return container
        } catch {
            fatalError("Impossible de créer le conteneur de prévisualisation : \(error)")
        }
    }()
}
