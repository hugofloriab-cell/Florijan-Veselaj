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
//     ⚠️ Piège vérifié à nos dépens le 27 août 2026, et c'est le point 3
//     ci-dessous qui y menait tout droit. Une nouvelle version ne se
//     justifie QUE si la LISTE DES MODÈLES change — un modèle ajouté ou
//     retiré. Ajouter des propriétés à un modèle existant n'en demande pas.
//
//     La raison tient au point 3 : comme aucune version ne recopie ses
//     modèles, chacune pointe sur les classes de haut niveau. Deux versions
//     qui déclarent la même liste décrivent donc, mot pour mot, le même
//     schéma. SwiftData en calcule la somme de contrôle, tombe deux fois sur
//     la même, et lève l'exception :
//
//         Duplicate version checksums detected
//
//     C'est une NSException, pas une erreur Swift : elle traverse le `try`
//     de `makeContainer` sans être attrapée, et le filet de secours d'
//     `AppSchema.openStore()` ne peut rien pour elle. L'application s'arrête
//     au lancement, sur toutes les machines à la fois.
//
//     Une propriété munie d'une valeur par défaut ou optionnelle n'a de
//     toute façon besoin d'aucune étape : SwiftData la voit manquante dans
//     le store, l'ajoute avec sa valeur par défaut, et c'est réglé. Il suffit
//     de l'écrire dans le modèle et de ne toucher à rien ici.
//
//     Concrètement, avant d'ajouter une version, poser la question :
//     « est-ce que `models` va changer de contenu ? » Si la réponse est non,
//     il n'y a pas de version à ajouter.
//
//  3. Ne PAS recopier les modèles tant que la migration reste légère.
//     (C'est ce choix qui rend le point 2 ci-dessus indispensable.)
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
//       Le seul cas qui justifie une étape ici est l'ajout ou le retrait d'un
//       modèle. Les changements de propriétés légers — valeur par défaut,
//       optionnelle, propriété supprimée, index — sont pris en charge sans
//       qu'on déclare quoi que ce soit, et déclarer une version pour eux
//       fait planter le lancement (voir le point 2).
//
//         static let v3ToV4 = MigrationStage.lightweight(
//             fromVersion: HACCPSchemaV3.self,
//             toVersion: HACCPSchemaV4.self
//         )
//
//     • Changement LOURD (`.custom`) — il faut écrire la transformation.
//       Cas concernés : renommer une propriété, changer son type, rendre
//       obligatoire une propriété qui était optionnelle, découper ou fusionner
//       un modèle. Sans ça, les valeurs existantes sont perdues.
//
//         static let v3ToV4 = MigrationStage.custom(
//             fromVersion: HACCPSchemaV3.self,
//             toVersion: HACCPSchemaV4.self,
//             willMigrate: nil,
//             didMigrate: { context in
//                 // Ici, les objets sont déjà au format V4 mais les nouvelles
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

// MARK: - Version 3

/// Ajoute les registres opérationnels manquants : décongélation, plats
/// témoins, traitement assainissant du poisson cru et origine de la viande
/// bovine.
///
/// Quatre modèles nouveaux, aucun modèle modifié : la migration reste légère.
enum HACCPSchemaV3: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
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
            Dish.self,
            ThawingRecord.self,
            FoodSample.self,
            SanitizingFreezeRecord.self,
            BeefOriginRecord.self
        ]
    }
}

// MARK: - Version 4

/// Ajoute le suivi du personnel et les fiches produits d'entretien, plus
/// l'émargement des opérations de nettoyage.
///
/// Trois modèles nouveaux, et une propriété optionnelle ajoutée à
/// `CleaningRecord` : la migration reste légère.
enum HACCPSchemaV4: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
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
            Dish.self,
            ThawingRecord.self,
            FoodSample.self,
            SanitizingFreezeRecord.self,
            BeefOriginRecord.self,
            ShiftHygieneCheck.self,
            MedicalFitnessRecord.self,
            CleaningProduct.self
        ]
    }
}

// MARK: - Version 5

/// Ajoute l'archive documentaire, le carnet d'entretien et le registre des
/// retraits-rappels. Trois modèles nouveaux, rien de modifié.
enum HACCPSchemaV5: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
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
            Dish.self,
            ThawingRecord.self,
            FoodSample.self,
            SanitizingFreezeRecord.self,
            BeefOriginRecord.self,
            ShiftHygieneCheck.self,
            MedicalFitnessRecord.self,
            CleaningProduct.self,
            RegulatoryDocument.self,
            EquipmentMaintenance.self,
            ProductRecall.self
        ]
    }
}

// MARK: - Version 6

/// Ajoute les analyses de laboratoire, les contrôles du réseau d'eau et les
/// bordereaux de collecte des huiles usagées.
enum HACCPSchemaV6: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        HACCPSchemaV5.models + [
            LabAnalysis.self,
            WaterControl.self,
            WasteOilCollection.self
        ]
    }
}

// MARK: - Version 7

/// Ajoute les scellés mensuels d'intégrité.
enum HACCPSchemaV7: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        HACCPSchemaV6.models + [IntegritySeal.self]
    }
}

// MARK: - Plan de migration

/// Chaîne des versions successives du schéma.
///
/// `schemas` est dans l'ordre chronologique, `stages` contient une étape par
/// passage d'une version à la suivante.
enum HACCPMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [HACCPSchemaV1.self, HACCPSchemaV2.self, HACCPSchemaV3.self, HACCPSchemaV4.self, HACCPSchemaV5.self, HACCPSchemaV6.self, HACCPSchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7]
    }

    /// V1 → V2 : uniquement des ajouts munis de valeurs par défaut, donc
    /// SwiftData sait s'en charger seul. Les registres existants sont
    /// conservés tels quels, avec une liste d'allergènes vide.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV1.self,
        toVersion: HACCPSchemaV2.self
    )

    /// V2 → V3 : quatre modèles ajoutés, rien de modifié.
    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV2.self,
        toVersion: HACCPSchemaV3.self
    )

    /// V3 → V4 : trois modèles ajoutés, et une propriété optionnelle de plus
    /// sur `CleaningRecord`.
    static let v3ToV4 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV3.self,
        toVersion: HACCPSchemaV4.self
    )

    /// V4 → V5 : trois modèles ajoutés, rien de modifié.
    static let v4ToV5 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV4.self,
        toVersion: HACCPSchemaV5.self
    )

    /// V5 → V6 : trois modèles ajoutés, rien de modifié.
    static let v5ToV6 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV5.self,
        toVersion: HACCPSchemaV6.self
    )

    /// V6 → V7 : un modèle ajouté, rien de modifié.
    static let v6ToV7 = MigrationStage.lightweight(
        fromVersion: HACCPSchemaV6.self,
        toVersion: HACCPSchemaV7.self
    )
}

// MARK: - Garde-fou de développement

#if DEBUG
extension HACCPMigrationPlan {

    /// Vérifie que deux versions ne décrivent pas le même schéma.
    ///
    /// Sans ce contrôle, l'erreur ne se manifeste qu'au lancement, sous la
    /// forme d'une `NSException` « Duplicate version checksums detected » que
    /// le `try` de `makeContainer` ne peut pas attraper : l'application
    /// s'arrête, sans indiquer quelle version est en cause.
    ///
    /// Appelé uniquement en développement — en production le schéma est déjà
    /// figé, et le coût du contrôle n'aurait plus de contrepartie.
    static func assertVersionsAreDistinct() {
        var seen: [String: String] = [:]

        for version in schemas {
            let entities = version.models
                .map { String(describing: $0) }
                .sorted()
                .joined(separator: ",")

            let name = String(describing: version)

            if let previous = seen[entities] {
                assertionFailure(
                    """
                    Deux versions du schéma décrivent les mêmes modèles : \(previous) et \(name).
                    SwiftData leur calculera la même somme de contrôle et refusera d'ouvrir la base.
                    Une version ne s'ajoute que lorsque la liste des modèles change — l'ajout d'une
                    propriété munie d'une valeur par défaut n'en demande aucune.
                    """
                )
                return
            }

            seen[entities] = name
        }
    }
}
#endif
