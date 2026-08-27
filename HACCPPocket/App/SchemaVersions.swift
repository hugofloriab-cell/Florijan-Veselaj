//
//  SchemaVersions.swift
//  HACCPPocket
//
//  Historique des versions du schéma SwiftData.
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
//  Ce fichier nomme la forme du schéma à chaque étape de son histoire, et
//  désigne celle qui a cours. Il sert de journal : savoir ce qui a été livré,
//  et à quelle version correspond une base rencontrée sur un appareil.
//
//  Il ne pilote plus la migration — la section suivante explique pourquoi, et
//  c'est à lire avant de modifier le moindre `@Model`.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI IL N'Y A PLUS DE PLAN DE MIGRATION — constaté le 27 août 2026
//  ─────────────────────────────────────────────────────────────────────────
//
//  Ce fichier a longtemps déclaré un `SchemaMigrationPlan` passé au
//  `ModelContainer`. Il a été retiré, et voici pourquoi — c'est important à
//  comprendre avant d'avoir la tentation de le remettre.
//
//  Les versions ci-dessous ne recopient pas leurs modèles : elles pointent
//  toutes sur les classes `@Model` courantes du projet. Ce choix était
//  délibéré (recopier partiellement fait échouer la migration, cf. le piège
//  du 24 août), mais il a une conséquence qui n'avait pas été tirée :
//
//      la somme de contrôle d'une version décrit toujours la forme
//      D'AUJOURD'HUI des modèles, jamais celle du jour où elle a été écrite.
//
//  Tant qu'on ne fait qu'AJOUTER des modèles, ça tient : la version déjà
//  livrée garde la même somme de contrôle d'un build à l'autre, SwiftData
//  reconnaît la base et applique l'étape suivante. C'est ce qui a fait
//  fonctionner les migrations V1 à V7.
//
//  Mais dès qu'on ajoute une PROPRIÉTÉ à un modèle existant, la somme de
//  contrôle de TOUTES les versions change d'un coup. La base enregistrée
//  porte celle de l'ancien build, plus aucune version déclarée ne lui
//  correspond, et SwiftData refuse :
//
//      Cannot use staged migration with an unknown coordinator model version
//
//  La base est alors mise de côté et l'utilisateur repart d'un registre
//  vierge. Autrement dit : ce plan cassait exactement les cas qu'il était
//  censé protéger, et l'ajout d'une propriété est de loin le changement le
//  plus courant.
//
//  Sans plan, SwiftData fait une migration légère implicite : il compare la
//  base à la forme actuelle des modèles et comble l'écart. Elle couvre tous
//  les changements additifs — modèle ajouté, propriété ajoutée avec valeur
//  par défaut ou optionnelle, propriété supprimée, index. C'est ce qu'il
//  fallait depuis le début.
//
//  ⚠️ La note qui figurait plus haut dans ce fichier prétendait qu'une
//  migration implicite « fait planter le lancement dès qu'un modèle change de
//  forme ». C'était faux sur les deux points : elle absorbe les changements
//  additifs, et quand elle échoue vraiment, `AppSchema.openStore()` attrape
//  l'erreur, met la base de côté sans la détruire et laisse l'application
//  s'ouvrir. Cette phrase a coûté deux incidents, elle est retirée.
//
//  ─────────────────────────────────────────────────────────────────────────
//  COMMENT MODIFIER UN @Model — à lire avant d'y toucher
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Changement ADDITIF — c'est le cas courant, et il n'y a RIEN à faire
//     dans ce fichier au-delà du point 2.
//
//     Sont additifs : ajouter un modèle, ajouter une propriété munie d'une
//     valeur par défaut ou optionnelle, supprimer une propriété, ajouter ou
//     retirer un index. Écrire le changement dans le modèle suffit : la
//     migration implicite s'en charge, les données existantes sont conservées
//     et les nouvelles propriétés prennent leur valeur par défaut.
//
//  2. Tenir l'historique à jour. Ajouter une version en dessous, avec la
//     liste complète des modèles, et pointer `AppSchema.currentVersion`
//     dessus. Ces versions ne pilotent plus la migration : elles servent de
//     journal de ce qui a été livré, et `versionIdentifier` alimente le
//     numéro affiché dans les réglages. Un ajout de propriété seul ne
//     justifie pas une version — la liste des modèles n'a pas changé.
//
//  3. Changement LOURD — renommer une propriété ou un modèle, changer un
//     type, rendre obligatoire une propriété optionnelle, découper ou
//     fusionner un modèle. La migration implicite ne sait pas le faire : les
//     valeurs concernées seraient perdues, ou la base refusée.
//
//     C'est le seul cas qui justifie de réintroduire un plan de migration —
//     et il devra alors être fait correctement, ce qui est un chantier à part
//     entière : CHAQUE version doit imbriquer SES PROPRES copies de TOUS ses
//     modèles, et la version courante être exposée par des `typealias`. Une
//     recopie partielle fait coexister deux classes portant le même nom
//     d'entité, et SwiftData ne sait plus laquelle correspond à la base.
//     À moitié fait, c'est pire que pas fait du tout.
//
//     Avant de s'y lancer, se demander si le changement est évitable. Garder
//     une propriété au nom devenu inexact coûte moins cher qu'une migration
//     personnalisée ratée sur les registres d'un client. C'est ce qui a été
//     décidé pour `BeefOriginRecord`, qui couvre les quatre espèces sans
//     avoir été renommé.
//
//  4. TESTER AVANT DE PUBLIER, et pas sur une base vide : installer la
//     version précédente depuis TestFlight ou l'App Store, saisir des données
//     dans chaque registre, puis lancer la nouvelle version par-dessus SANS
//     supprimer l'application. Les données doivent être là. C'est le seul
//     test qui compte.
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
/// Les modèles sont référencés directement, sans copie figée : cette version
/// décrit donc la forme qu'ils ont aujourd'hui, pas celle qu'ils avaient à sa
/// publication. C'est acceptable pour un journal, et c'est précisément ce qui
/// interdisait d'en faire un plan de migration — voir l'en-tête du fichier.
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

// MARK: - Version 8

/// Ajoute les pièces justificatives photographiées à la réception.
///
/// Un modèle nouveau, `DeliveryDocument`. Les propriétés ajoutées au même
/// moment — la photo du bidon sur `CleaningProduct`, la photo exigée sur
/// `CleaningTask` — n'auraient justifié aucune version à elles seules : elles
/// possèdent une valeur par défaut et la migration implicite les absorbe.
enum HACCPSchemaV8: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        HACCPSchemaV7.models + [DeliveryDocument.self]
    }
}
