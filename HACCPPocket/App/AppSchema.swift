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
    static let currentVersion: any VersionedSchema.Type = HACCPSchemaV7.self

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

    // MARK: - Synchronisation iCloud

    /// Synchronisation des registres entre les appareils d'un même compte
    /// iCloud (iPhone, iPad, Mac).
    ///
    /// Désactivée pour l'instant : CloudKit exige la capacité iCloud dans le
    /// projet Xcode, qui n'est accordée qu'avec un compte développeur payant.
    /// Tant qu'elle est à `false`, l'application reste strictement locale.
    ///
    /// Le schéma, lui, respecte déjà toutes les contraintes CloudKit — voir
    /// `SchemaVersions.swift`. Le jour venu, il n'y aura donc que trois
    /// gestes, et aucune migration supplémentaire :
    ///
    ///   1. Xcode → cible HACCPPocket → Signing & Capabilities → + Capability
    ///      → iCloud, puis cocher « CloudKit » et créer le conteneur
    ///      `iCloud.com.<votre-identifiant>.HACCPPocket` ;
    ///   2. ajouter aussi la capacité « Background Modes » et y cocher
    ///      « Remote notifications », sans quoi les modifications faites sur
    ///      un autre appareil n'arrivent qu'au prochain lancement ;
    ///   3. passer cette constante à `true`.
    static let usesCloudSync = false

    // MARK: - Emplacement du store

    /// Fichier de base actuellement ouvert.
    ///
    /// Chaque établissement possède le sien : basculer d'un établissement à
    /// l'autre revient à ouvrir un autre registre, sans qu'aucune donnée ne
    /// puisse se croiser. La valeur est posée avant l'ouverture, par la vue
    /// racine, à partir de l'annuaire des établissements.
    static var activeStoreName: String = EstablishmentDirectory.legacyStoreName

    /// Configuration de production. On la construit à un seul endroit pour que
    /// la procédure de secours vise exactement le fichier qu'ouvre SwiftData,
    /// sans avoir à deviner son emplacement.
    private static var productionConfiguration: ModelConfiguration {
        ModelConfiguration(
            activeStoreName,
            schema: schema,
            cloudKitDatabase: usesCloudSync ? .automatic : .none
        )
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
    static func openStore(for site: SiteReference) -> StoreResult {
        activeStoreName = site.storeName
        return openStore()
    }

    @MainActor
    static func openStore() -> StoreResult {

        // 0. Une remise en service demandée depuis les réglages s'exécute
        //    avant toute ouverture : c'est le seul moment où les fichiers ne
        //    sont tenus par personne.
        performPendingRestoreIfNeeded()

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

    /// Préfixe des bases écartées. Volontairement lisible : un utilisateur
    /// doit pouvoir reconnaître ce fichier s'il tombe dessus.
    private static var archivePrefix: String { "\(activeStoreName)-illisible-" }

    /// Renomme la base défaillante avec un horodatage à la minute et renvoie
    /// sa nouvelle adresse. Rien n'est supprimé, et rien n'est écrasé : deux
    /// incidents le même jour produisent deux fichiers distincts.
    @discardableResult
    static func setStoreAside(at date: Date = .now) throws -> URL {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let originalName = storeURL.lastPathComponent
        let archivedName = "\(archivePrefix)\(AppFormatters.fileTimestamp(date)).store"

        for source in storeFileURLs where fileManager.fileExists(atPath: source.path) {
            // HACCPPocket.store.wal devient HACCPPocket-illisible-….store.wal :
            // le trio reste cohérent si quelqu'un doit rouvrir la base.
            let targetName = source.lastPathComponent
                .replacingOccurrences(of: originalName, with: archivedName)
            let target = directory.appending(path: targetName)

            // Un fichier déjà présent ne serait pas remplacé : on cherche un
            // nom libre plutôt que de détruire une sauvegarde antérieure.
            try fileManager.moveItem(at: source, to: freeURL(from: target))
        }

        return directory.appending(path: archivedName)
    }

    /// Décale le nom tant qu'un fichier existe déjà.
    private static func freeURL(from url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent

        for suffix in 2...99 {
            let candidate = directory.appending(path: "\(suffix)-\(name)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    // MARK: - Bases mises de côté

    /// Une base écartée lors d'un incident, telle qu'elle est proposée à
    /// l'utilisateur dans les réglages.
    struct ArchivedStore: Identifiable, Hashable {
        let fileName: String
        let url: URL
        let modifiedAt: Date
        let byteSize: Int

        var id: String { fileName }
    }

    /// Inventaire des bases écartées, la plus récente en tête.
    static func archivedStores() -> [ArchivedStore] {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()

        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []

        var found: [ArchivedStore] = []

        for url in contents {
            let name = url.lastPathComponent
            // On ne liste que le fichier principal : les .shm et .wal
            // l'accompagnent et n'ont pas à apparaître.
            guard name.hasPrefix(archivePrefix), name.hasSuffix(".store") else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            found.append(
                ArchivedStore(
                    fileName: name,
                    url: url,
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    byteSize: values?.fileSize ?? 0
                )
            )
        }

        return found.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Remise en service d'une base écartée

    private static let pendingRestoreKey = "haccp.store.pendingRestore"

    /// Demande la remise en service d'une base écartée.
    ///
    /// L'échange de fichiers n'a pas lieu tout de suite : SwiftData tient la
    /// base courante ouverte, et permuter des fichiers sous ses pieds est le
    /// meilleur moyen de casser les deux. On note l'intention, et le prochain
    /// lancement fera l'échange avant d'ouvrir quoi que ce soit.
    static func requestRestore(of archive: ArchivedStore, defaults: UserDefaults = .standard) {
        defaults.set(archive.fileName, forKey: pendingRestoreKey)
    }

    static func pendingRestoreFileName(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: pendingRestoreKey)
    }

    static func cancelPendingRestore(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingRestoreKey)
    }

    /// Exécute l'échange demandé, avant toute ouverture de conteneur.
    ///
    /// La base courante n'est pas détruite : elle est écartée à son tour, ce
    /// qui rend l'opération réversible. Se tromper de fichier ne coûte donc
    /// qu'un aller-retour.
    private static func performPendingRestoreIfNeeded(defaults: UserDefaults = .standard) {
        guard let fileName = pendingRestoreFileName(defaults: defaults) else { return }
        defaults.removeObject(forKey: pendingRestoreKey)

        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let archiveURL = directory.appending(path: fileName)

        guard fileManager.fileExists(atPath: archiveURL.path) else { return }

        // La base courante prend la place d'une archive.
        try? setStoreAside()

        let originalName = storeURL.lastPathComponent
        for suffix in ["", ".shm", ".wal"] {
            let source = directory.appending(path: fileName + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = directory.appending(path: originalName + suffix)
            try? fileManager.moveItem(at: source, to: target)
        }
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
