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
//  1. Laisser `HACCPSchemaV1` exactement tel quel.
//
//  2. Créer `HACCPSchemaV2` en dessous, avec la version 2.0.0 et la liste
//     complète des modèles — y compris ceux qui n'ont pas changé.
//
//  3. Décrire le passage de V1 à V2 :
//
//     • Changement LÉGER (`.lightweight`) — SwiftData s'en charge seul.
//       Cas couverts : ajouter un modèle, ajouter une propriété qui possède
//       une valeur par défaut ou qui est optionnelle, supprimer une propriété,
//       ajouter ou retirer un index.
//
//         static let v1ToV2 = MigrationStage.lightweight(
//             fromVersion: HACCPSchemaV1.self,
//             toVersion: HACCPSchemaV2.self
//         )
//
//     • Changement LOURD (`.custom`) — il faut écrire la transformation.
//       Cas concernés : renommer une propriété, changer son type, rendre
//       obligatoire une propriété qui était optionnelle, découper ou fusionner
//       un modèle. Sans ça, les valeurs existantes sont perdues.
//
//         static let v1ToV2 = MigrationStage.custom(
//             fromVersion: HACCPSchemaV1.self,
//             toVersion: HACCPSchemaV2.self,
//             willMigrate: nil,
//             didMigrate: { context in
//                 // Ici, les objets sont déjà au format V2 mais les nouvelles
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
//  4. Déclarer la nouvelle version et l'étape dans `HACCPMigrationPlan` :
//     `schemas` dans l'ordre chronologique, `stages` dans le même ordre.
//
//  5. Pointer `AppSchema.currentVersion` sur `HACCPSchemaV2.self`.
//
//  6. TESTER LA MIGRATION AVANT DE PUBLIER, et pas sur une base vide :
//     installer la version précédente depuis TestFlight ou l'App Store,
//     saisir des données dans chaque registre, puis lancer la nouvelle version
//     par-dessus SANS supprimer l'application. Les données doivent être là.
//     C'est le seul test qui compte.
//

import Foundation
import SwiftData

// MARK: - Version 1

/// Schéma de la première version publiée.
///
/// Les modèles ne sont pas imbriqués dans l'énumération : tant qu'aucune
/// version ultérieure ne modifie leur forme, la référence directe suffit et
/// évite de dupliquer douze déclarations. Le jour où un modèle change, c'est
/// lui — et lui seul — qui devra être recopié à l'intérieur de la version qui
/// le fige.
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

// MARK: - Plan de migration

/// Chaîne des versions successives du schéma.
///
/// `schemas` doit être dans l'ordre chronologique, et `stages` contenir une
/// étape par passage d'une version à la suivante. Aujourd'hui une seule
/// version existe, donc aucune étape n'est nécessaire — mais le plan est déjà
/// en place, et c'est tout l'intérêt : la migration suivante sera une addition
/// et non une reprise en catastrophe.
enum HACCPMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [HACCPSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
