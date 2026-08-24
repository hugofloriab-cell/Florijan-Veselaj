//
//  SchemaVersions.swift
//  HACCPPocket
//
//  Versions du schéma SwiftData et plan de migration.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER EXISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Les données de cette application sont un document légal : un restaurateur
//  doit pouvoir présenter trois ans de registres à un contrôleur. Perdre la
//  base au cours d'une mise à jour n'est pas un incident technique, c'est la
//  fin de l'application.
//
//  Sans plan de migration déclaré, SwiftData tente une migration implicite.
//  Elle réussit sur des changements simples, mais échoue — et fait planter le
//  lancement — dès qu'un modèle change de forme. Ce fichier remplace ce pari
//  par un contrat explicite : chaque version du schéma est nommée, figée, et
//  reliée à la suivante par une étape de migration.
//
//  ─────────────────────────────────────────────────────────────────────────
//  COMMENT AJOUTER UNE VERSION — à lire avant toute modification d'un @Model
//  ─────────────────────────────────────────────────────────────────────────
//
//  Règle absolue : dès que l'application est publiée, une version de schéma
//  déjà livrée ne se modifie JAMAIS. On en ajoute une nouvelle.
//
//  Le passage de V1 à V2, plus bas, sert d'exemple complet.
//
//  1. Laisser les versions existantes exactement telles quelles.
//
//  2. Créer la version suivante en dessous, avec un numéro incrémenté et la
//     liste complète des modèles — y compris ceux qui n'ont pas changé.
//
//  3. Ne PAS recopier les modèles tant que la migration reste légère.
//     SwiftData n'a pas besoin de la forme d'origine décrite en Swift : elle
//     est enregistrée dans le store, et c'est là qu'il la lit. Référencer
//     directement les modèles courants dans chaque version suffit.
//
//     ⚠️ Piège vérifié à nos dépens le 24 août 2026 : recopier un seul modèle
//     à l'intérieur d'une version, en laissant les autres pointer sur le
//     modèle de haut niveau, fait échouer la migration. Deux classes `@Model`
//     portant le même nom d'entité coexistent alors dans le module, et
//     SwiftData ne sait plus laquelle correspond au store. La base est alors
//     mise de côté et l'utilisateur repart d'un registre vierge.
//
//     Si une migration personnalisée impose vraiment de relire les anciennes
//     valeurs, alors TOUTES les versions doivent imbriquer TOUS leurs
//     modèles, et la version courante être exposée par des `typealias`.
//     C'est un chantier à part entière, à ne lancer que s'il est inévitable.
//
//  4. Décrire le passage d'une version à l'autre :
//
//     • Changement LÉGER (`.lightweight`) — SwiftData s'en charge seul.
//       Cas couverts : ajouter un modèle, ajouter une propriété qui possède
//       une valeur par défaut ou qui est optionnelle, supprimer une propriété,
//       ajouter ou retirer un index.
//
//         static let v2ToV3 = MigrationStage.lightweight(
//             fromVersion: HACCPSchemaV2.self,
//             toVersion: HACCPSchemaV3.self
//         )
//
//     • Changement LOURD (`.custom`) — il faut écrire la transformation.
//       Cas concernés : renommer une propriété, changer son type, rendre
//       obligatoire une propriété qui était optionnelle, découper ou fusionner
//       un modèle. Sans ça, les valeurs existantes sont perdues.
//
//         static let v2ToV3 = MigrationStage.custom(
//             fromVersion: HACCPSchemaV2.self,
//             toVersion: HACCPSchemaV3.self,
//             willMigrate: nil,
//             didMigrate: { context in
//                 // Ici, les objets sont déjà au format V3 mais les nouvelles
//                 // propriétés sont vides : c'est le moment de les remplir à
//                 // partir des anciennes valeurs.
//                 let equipments = try context.fetch(FetchDescriptor<Equipment>())
//                 for equipment in equipments {
//                     equipment.nouvelleProprieté = ...
//                 }
//                 try context.save()
//             }
//         )
//
//  5. Déclarer la nouvelle version et l'étape dans `HACCPMigrationPlan` :
//     `schemas` dans l'ordre chronologique, `stages` dans le même ordre.
//
//  6. Pointer `AppSchema.currentVersion` sur la nouvelle version.
//
//  7. TESTER LA MIGRATION AVANT DE PUBLIER, et pas sur une base vide :
//     installer la version précédente depuis TestFlight ou l'App Store,
//     saisir des données dans chaque registre, puis lancer la nouvelle version
//     par-dessus SANS supprimer l'application. Les données doivent être là.
//     C'est le seul test qui compte.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CONTRAINTES iCLOUD
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le schéma est tenu compatible avec la synchronisation CloudKit, même
//  tant qu'elle est désactivée : c'est ce qui permettra de l'activer plus
//  tard par une seule ligne, sans migration supplémentaire. Trois règles à
//  respecter dans tout nouveau modèle :
//
//    • toute propriété non optionnelle porte une valeur par défaut ;
//    • aucune contrainte d'unicité (`@Attribute(.unique)`) ;
//    • toute relation est optionnelle, possède son inverse, et une relation
//      « à plusieurs » est initialisée à `[]`.
//

import Foundation
import SwiftData

// MARK: - Version 1

/// Schéma de la première version publiée.
///
/// Les modèles sont référencés directement, sans copie figée. Pour une
/// migration légère, SwiftData n'a pas besoin de la forme d'origine décrite
/// en Swift : il la lit dans le store lui-même, où elle est enregistrée. Ce
/// n'est que pour une migration personnalisée, où il faut relire les
/// anciennes valeurs, que les versions doivent porter leur propre copie des
/// modèles — et dans ce cas **toutes** les versions, sans exception.
enum HACCPSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Establishment.self,
            Equipment.self,
            TemperatureReading.self,
            TrackedProduct.self,
            DeliveryCheck.self,
            CleaningTask.self,
            CleaningRecord.self,
            ThermalProcessRecord.self,
            ThermalCheckpoint.self,
            OilCheckRecord.self,
            PestControlVisit.self,
            StaffTraining.self
        ]
    }
}

// MARK: - Version 2

/// Ajoute la carte des plats et les allergènes.
///
/// Deux changements par rapport à la V1, tous deux additifs :
/// — le modèle `Dish`, qui n'existait pas ;
/// — `TrackedProduct.allergenRawValues`, qui possède une valeur par défaut.
///
/// Cette version rend aussi l'ensemble du schéma compatible avec la
/// synchronisation iCloud : chaque propriété non optionnelle porte désormais
/// une valeur par défaut, exigence de CloudKit. Ce point ne modifie pas la
/// forme du store — c'est du confort pour plus tard, obtenu sans migration
/// supplémentaire le jour où la synchronisation sera activée.
enum HACCPSchemaV2: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Establishment.self,
            Equipment.self,
            TemperatureReading.self,
            TrackedProduct.self,
            DeliveryCheck.self,
            CleaningTask.self,
            CleaningRecord.self,
            ThermalProcessRecord.self,
            ThermalCheckpoint.self,
            OilCheckRecord.self,
            PestControlVisit.self,
            StaffTraining.self,
            Dish.self
        ]
    }
}

// MARK: - Plan de migration

/// Chaîne des versions successives du schéma.
///
/// `schemas` est dans l'ordre chronologique, `stages` contient une étape par
/// passage d'une version à la suivante.
enum HACCPMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [HACCPSchemaV1.self, HACCPSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    /// V1 → V2 : uniquement des ajouts munis de valeurs par défaut, donc
    /// SwiftData sait s'en charger seul. Les registres existants sont
    /// conservés tels quels, avec une liste d'allergènes vide.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV1.self,
        toVersion: HACCPSchemaV2.self
    )
}
