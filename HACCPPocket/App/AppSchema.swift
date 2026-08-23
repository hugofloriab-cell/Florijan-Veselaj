//
//  AppSchema.swift
//  HACCPPocket
//
//  Point unique de déclaration du schéma SwiftData et de construction du
//  `ModelContainer`. Tout est strictement local : aucune configuration CloudKit,
//  aucun réseau, donc aucun coût d'infrastructure.
//

import Foundation
import SwiftData

enum AppSchema {

    /// Toutes les entités persistées. Ajouter un modèle ici et nulle part ailleurs.
    static let models: [any PersistentModel.Type] = [
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

    static var schema: Schema {
        Schema(models)
    }

    /// Conteneur de production, stocké sur l'appareil.
    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "HACCPPocket",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        SeedData.seedIfNeeded(in: container.mainContext)
        return container
    }

    /// Conteneur volatil utilisé par les `#Preview` : jeu de données complet,
    /// jamais écrit sur disque.
    @MainActor
    static let preview: ModelContainer = {
        do {
            let configuration = ModelConfiguration(
                "HACCPPocketPreview",
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
