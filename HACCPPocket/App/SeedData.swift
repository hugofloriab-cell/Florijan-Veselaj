//
//  SeedData.swift
//  HACCPPocket
//
//  Jeu de données initial. Au premier lancement, l'utilisateur trouve un plan
//  de nettoyage et des équipements déjà prêts : il n'a plus qu'à les ajuster.
//

import Foundation
import SwiftData

enum SeedData {

    /// Clé mémorisant que l'amorçage a déjà eu lieu, pour ne pas réinjecter les
    /// valeurs par défaut si l'utilisateur les a volontairement supprimées.
    private static let seedFlagKey = "haccp.didSeedDefaultData.v1"

    // MARK: - Amorçage

    @MainActor
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seedFlagKey) else { return }
        populate(context: context, includeSampleActivity: false)
        defaults.set(true, forKey: seedFlagKey)
    }

    /// Insère la configuration par défaut. `includeSampleActivity` ajoute en plus
    /// un historique fictif, réservé aux prévisualisations Xcode.
    @MainActor
    static func populate(context: ModelContext, includeSampleActivity: Bool) {
        let establishment = Establishment(name: "", address: "", managerName: "")
        context.insert(establishment)

        let equipments = defaultEquipments()
        equipments.forEach { context.insert($0) }

        defaultCleaningTasks().forEach { context.insert($0) }

        if includeSampleActivity {
            insertSampleActivity(context: context, equipments: equipments)
        }

        try? context.save()
    }

    // MARK: - Configuration par défaut

    static func defaultEquipments() -> [Equipment] {
        [
            Equipment(name: "Frigo cuisine", type: .positiveCold, location: "Cuisine", sortIndex: 0),
            Equipment(name: "Congélateur", type: .negativeCold, location: "Réserve", sortIndex: 1),
            Equipment(name: "Chambre froide", type: .coldRoom, location: "Réserve", sortIndex: 2)
        ]
    }

    static func defaultCleaningTasks() -> [CleaningTask] {
        [
            CleaningTask(
                title: "Désinfection des plans de travail",
                frequency: .daily,
                zone: "Cuisine",
                productUsed: "Dégraissant désinfectant contact alimentaire",
                procedure: "Nettoyer, rincer, désinfecter, laisser agir 5 min, rincer à l'eau potable.",
                sortIndex: 0
            ),
            CleaningTask(
                title: "Nettoyage du sol de la cuisine",
                frequency: .daily,
                zone: "Cuisine",
                productUsed: "Détergent sol alimentaire",
                procedure: "Balayage humide puis lavage à la monobrosse ou au balai plat.",
                sortIndex: 1
            ),
            CleaningTask(
                title: "Vidage et désinfection des poubelles",
                frequency: .daily,
                zone: "Cuisine",
                productUsed: "Désinfectant surfaces",
                procedure: "Vider, laver le conteneur, désinfecter, remettre un sac propre.",
                sortIndex: 2
            ),
            CleaningTask(
                title: "Nettoyage intérieur des enceintes froides",
                frequency: .weekly,
                zone: "Cuisine / Réserve",
                productUsed: "Désinfectant contact alimentaire",
                procedure: "Vider, retirer les clayettes, laver, désinfecter, sécher avant remise en service.",
                sortIndex: 3
            ),
            CleaningTask(
                title: "Nettoyage de la hotte et des filtres",
                frequency: .monthly,
                zone: "Cuisine",
                productUsed: "Dégraissant alcalin",
                procedure: "Démonter les filtres, tremper, rincer, sécher, remonter.",
                sortIndex: 4
            ),
            CleaningTask(
                title: "Dégivrage complet des congélateurs",
                frequency: .quarterly,
                zone: "Réserve",
                productUsed: "Désinfectant contact alimentaire",
                procedure: "Transférer les denrées, dégivrer, nettoyer, désinfecter, redescendre en température avant recharge.",
                sortIndex: 5
            )
        ]
    }

    // MARK: - Données de démonstration (previews uniquement)

    @MainActor
    private static func insertSampleActivity(context: ModelContext, equipments: [Equipment]) {
        let calendar = Calendar.current

        // Sept jours de relevés matin/soir, avec une non-conformité volontaire.
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: .now) else { continue }

            for equipment in equipments {
                for moment in ReadingMoment.dailyRoutine {
                    let hour = moment == .morning ? 8 : 19
                    guard let stamp = calendar.date(
                        bySettingHour: hour, minute: 30, second: 0, of: day
                    ) else { continue }

                    let range = equipment.acceptedRange
                    let middle = (range.lowerBound + range.upperBound) / 2
                    let isAnomaly = (dayOffset == 2 && moment == .evening && equipment.type == .positiveCold)
                    let value = isAnomaly ? range.upperBound + 3.5 : middle

                    let reading = TemperatureReading(
                        value: value,
                        equipment: equipment,
                        moment: moment,
                        operatorName: "Camille",
                        correctiveAction: isAnomaly
                            ? "Porte mal fermée : refermée, denrées contrôlées, retour en température vérifié."
                            : "",
                        recordedAt: stamp
                    )
                    context.insert(reading)
                }
            }
        }

        // Produits entamés à différents stades de leur DLC secondaire.
        let products: [(String, Int, StorageZone)] = [
            ("Crème fraîche 35 %", 0, .positiveCold),
            ("Saumon fumé", -1, .positiveCold),
            ("Fond de veau", 2, .positiveCold),
            ("Purée de tomate", 1, .coldRoom)
        ]
        for (name, offset, zone) in products {
            let openedAt = calendar.date(byAdding: .day, value: offset - 3, to: .now) ?? .now
            let product = TrackedProduct(
                name: name,
                openedAt: openedAt,
                storage: zone,
                batchNumber: "L\(Int.random(in: 10_000...99_999))",
                supplier: "Metro"
            )
            context.insert(product)
        }

        // Un contrôle à réception conforme et un refus documenté.
        context.insert(
            DeliveryCheck(
                supplierName: "Transgourmet",
                productLabel: "Volaille fraîche",
                receivedAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                temperature: 3.0,
                temperatureLimit: 4.0,
                operatorName: "Camille"
            )
        )
        context.insert(
            DeliveryCheck(
                supplierName: "Pomona",
                productLabel: "Filets de cabillaud",
                receivedAt: calendar.date(byAdding: .day, value: -4, to: .now) ?? .now,
                temperature: 7.5,
                temperatureLimit: 2.0,
                decision: .refused,
                reason: "Température à réception non conforme, lot refusé et repris par le chauffeur.",
                operatorName: "Camille"
            )
        )

        try? context.save()
    }
}
