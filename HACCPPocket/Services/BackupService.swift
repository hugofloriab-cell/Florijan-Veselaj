//
//  BackupService.swift
//  HACCPPocket
//
//  Sauvegarde et restauration de la totalité des données.
//
//  L'application ne dépend d'aucun serveur : la base SwiftData vit dans le
//  téléphone et disparaît avec lui. Une archive exportable est donc la seule
//  vraie protection contre la perte de l'appareil, et c'est aussi ce que
//  l'utilisateur transmet à son comptable ou à un nouveau téléphone.
//
//  Format : un simple fichier JSON (extension .json pour rester lisible par
//  n'importe quel outil et importable sans déclarer de type de document).
//

import Foundation
import SwiftData

// MARK: - Enveloppe

/// Archive complète. `formatVersion` permet de refuser proprement un fichier
/// écrit par une version future de l'application.
struct BackupArchive: Codable {

    static let currentFormatVersion = 1

    var formatVersion: Int = BackupArchive.currentFormatVersion
    var exportedAt: Date = .now
    var appVersion: String = ""
    var includesPhotos: Bool = true

    var establishments: [EstablishmentDTO] = []
    var equipments: [EquipmentDTO] = []
    var products: [ProductDTO] = []
    var deliveries: [DeliveryDTO] = []
    var cleaningTasks: [CleaningTaskDTO] = []
    var thermalRecords: [ThermalDTO] = []
    var oilChecks: [OilDTO] = []
    var pestVisits: [PestDTO] = []
    var trainings: [TrainingDTO] = []
    var dishes: [DishDTO] = []

    /// Nombre total d'enregistrements, tous registres confondus. Sert à
    /// afficher un résumé avant d'écraser la base.
    var totalRecords: Int {
        // Additionné pas à pas, en Int explicite. Une chaîne de douze termes
        // mêlant `count` et `reduce` oblige le compilateur à essayer toutes
        // les surcharges de `+` : c'est exactement ce qu'il n'arrive plus à
        // faire en un temps raisonnable.
        var total: Int = 0

        total += establishments.count
        total += equipments.count
        total += products.count
        total += deliveries.count
        total += cleaningTasks.count
        total += thermalRecords.count
        total += oilChecks.count
        total += pestVisits.count
        total += trainings.count
        total += dishes.count

        for equipment in equipments {
            total += equipment.readings.count
        }
        for task in cleaningTasks {
            total += task.records.count
        }

        return total
    }
}

// MARK: - Objets de transfert

/// Chaque DTO reprend les propriétés stockées du modèle, y compris les
/// `rawValue` des énumérations : on veut une copie fidèle, pas une
/// interprétation.

struct EstablishmentDTO: Codable {
    var name: String
    var address: String
    var siret: String
    var managerName: String
    var approvalNumber: String
    var logoData: Data?
    var createdAt: Date
    var updatedAt: Date
}

struct ReadingDTO: Codable {
    var recordedAt: Date
    var value: Double
    var momentRawValue: String
    var operatorName: String
    var comment: String
    var correctiveAction: String
    var thresholdMin: Double
    var thresholdMax: Double
    var isCompliant: Bool
}

struct EquipmentDTO: Codable {
    var name: String
    var typeRawValue: String
    var location: String
    var minTemperature: Double
    var maxTemperature: Double
    var sortIndex: Int
    var isActive: Bool
    var createdAt: Date
    var readings: [ReadingDTO]
}

struct ProductDTO: Codable {
    var identifier: UUID
    var name: String
    var batchNumber: String
    var barcode: String
    var supplier: String
    var supplierExpiryDate: Date?
    var openedAt: Date
    var secondaryLimitDate: Date
    var storageRawValue: String
    var statusRawValue: String
    var labelPhotoData: Data?
    var closedAt: Date?
    var discardReason: String
    var notes: String
    var allergenRawValues: [String]
    var createdAt: Date
}

struct DeliveryDTO: Codable {
    var receivedAt: Date
    var supplierName: String
    var productLabel: String
    var batchNumber: String
    var temperature: Double?
    var temperatureLimit: Double?
    var packagingIntact: Bool
    var labellingCompliant: Bool
    var decisionRawValue: String
    var reason: String
    var operatorName: String
    var photoData: Data?
    var notes: String
    var createdAt: Date
}

struct CleaningRecordDTO: Codable {
    var completedAt: Date
    var operatorName: String
    var productUsed: String
    var comment: String
    var photoData: Data?
}

struct CleaningTaskDTO: Codable {
    var title: String
    var zone: String
    var productUsed: String
    var procedure: String
    var frequencyRawValue: String
    var isActive: Bool
    var sortIndex: Int
    var createdAt: Date
    var records: [CleaningRecordDTO]
}

struct CheckpointDTO: Codable {
    var recordedAt: Date
    var temperature: Double
}

struct ThermalDTO: Codable {
    var kindRawValue: String
    var productName: String
    var batchNumber: String
    var startedAt: Date
    var startTemperature: Double
    var finishedAt: Date?
    var endTemperature: Double?
    var targetTemperature: Double
    var maximumDurationSeconds: Double
    var operatorName: String
    var comment: String
    var correctiveAction: String
    var isCompliant: Bool
    var createdAt: Date
    var checkpoints: [CheckpointDTO]
}

struct OilDTO: Codable {
    var checkedAt: Date
    var fryerName: String
    var polarCompounds: Double?
    var polarCompoundsLimit: Double
    var appearanceRawValue: String
    var actionRawValue: String
    var operatorName: String
    var comment: String
    var isCompliant: Bool
    var createdAt: Date
}

struct PestDTO: Codable {
    var visitedAt: Date
    var company: String
    var technician: String
    var findings: String
    var baitsReplaced: Bool
    var deviceCount: Int
    var actionsTaken: String
    var nextVisitDate: Date?
    var reportPhotoData: Data?
    var hasInfestation: Bool
    var createdAt: Date
}

struct TrainingDTO: Codable {
    var personName: String
    var title: String
    var organisation: String
    var completedAt: Date
    var expiresAt: Date?
    var certificateData: Data?
    var notes: String
    var createdAt: Date
}

struct DishDTO: Codable {
    var name: String
    var categoryRawValue: String
    var summary: String
    var composition: String
    var allergenRawValues: [String]
    var isAvailable: Bool
    var isHomemade: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Erreurs

enum BackupError: LocalizedError {
    case unreadableFile
    case invalidFormat
    case futureFormat(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "Le fichier n'a pas pu être ouvert. Vérifiez qu'il est bien accessible sur cet appareil."
        case .invalidFormat:
            "Ce fichier n'est pas une sauvegarde HACCP Pocket."
        case .futureFormat(let version):
            "Cette sauvegarde a été créée par une version plus récente de l'application (format \(version)). Mettez à jour HACCP Pocket avant de la restaurer."
        }
    }
}

// MARK: - Service

@MainActor
enum BackupService {

    // MARK: Codage

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Export

    /// Lit toute la base et construit l'archive.
    ///
    /// - Parameter includePhotos: les photos représentent l'essentiel du poids
    ///   du fichier. On peut les exclure pour obtenir une sauvegarde légère,
    ///   partageable par e-mail.
    static func makeArchive(
        context: ModelContext,
        includePhotos: Bool = true,
        appVersion: String = ""
    ) throws -> BackupArchive {

        var archive = BackupArchive()
        archive.appVersion = appVersion
        archive.includesPhotos = includePhotos

        // Chaque conversion vit dans sa propre fonction, au type de retour
        // explicite. Regroupées, elles formaient une seule expression que le
        // compilateur Swift n'arrivait plus à vérifier en un temps raisonnable.
        archive.establishments = try context.fetch(FetchDescriptor<Establishment>())
            .map { establishmentDTO(for: $0, includePhotos: includePhotos) }
        archive.equipments = try context.fetch(FetchDescriptor<Equipment>())
            .map { equipmentDTO(for: $0) }
        archive.products = try context.fetch(FetchDescriptor<TrackedProduct>())
            .map { productDTO(for: $0, includePhotos: includePhotos) }
        archive.deliveries = try context.fetch(FetchDescriptor<DeliveryCheck>())
            .map { deliveryDTO(for: $0, includePhotos: includePhotos) }
        archive.cleaningTasks = try context.fetch(FetchDescriptor<CleaningTask>())
            .map { cleaningTaskDTO(for: $0, includePhotos: includePhotos) }
        archive.thermalRecords = try context.fetch(FetchDescriptor<ThermalProcessRecord>())
            .map { thermalDTO(for: $0) }
        archive.oilChecks = try context.fetch(FetchDescriptor<OilCheckRecord>())
            .map { oilDTO(for: $0) }
        archive.pestVisits = try context.fetch(FetchDescriptor<PestControlVisit>())
            .map { pestDTO(for: $0, includePhotos: includePhotos) }
        archive.trainings = try context.fetch(FetchDescriptor<StaffTraining>())
            .map { trainingDTO(for: $0, includePhotos: includePhotos) }
        archive.dishes = try context.fetch(FetchDescriptor<Dish>())
            .map { dishDTO(for: $0) }

        return archive
    }

    // MARK: Conversions modèle → archive
    //
    // Une fonction par modèle, au nom distinct et au type de retour explicite.
    // Treize surcharges du même nom obligeraient le compilateur à trancher à
    // chaque appel, et c'est précisément ce qu'il n'arrivait plus à faire.

    /// `includePhotos` à `false` produit une sauvegarde légère : les photos
    /// représentent l'essentiel du poids du fichier.
    private static func photo(_ data: Data?, includePhotos: Bool) -> Data? {
        includePhotos ? data : nil
    }

    private static func establishmentDTO(for establishment: Establishment, includePhotos: Bool) -> EstablishmentDTO {
        EstablishmentDTO(
            name: establishment.name,
            address: establishment.address,
            siret: establishment.siret,
            managerName: establishment.managerName,
            approvalNumber: establishment.approvalNumber,
            logoData: photo(establishment.logoData, includePhotos: includePhotos),
            createdAt: establishment.createdAt,
            updatedAt: establishment.updatedAt
        )
    }

    private static func readingDTO(for reading: TemperatureReading) -> ReadingDTO {
        ReadingDTO(
            recordedAt: reading.recordedAt,
            value: reading.value,
            momentRawValue: reading.momentRawValue,
            operatorName: reading.operatorName,
            comment: reading.comment,
            correctiveAction: reading.correctiveAction,
            thresholdMin: reading.thresholdMin,
            thresholdMax: reading.thresholdMax,
            isCompliant: reading.isCompliant
        )
    }

    private static func equipmentDTO(for equipment: Equipment) -> EquipmentDTO {
        EquipmentDTO(
            name: equipment.name,
            typeRawValue: equipment.typeRawValue,
            location: equipment.location,
            minTemperature: equipment.minTemperature,
            maxTemperature: equipment.maxTemperature,
            sortIndex: equipment.sortIndex,
            isActive: equipment.isActive,
            createdAt: equipment.createdAt,
            readings: equipment.readings.map { readingDTO(for: $0) }
        )
    }

    private static func productDTO(for product: TrackedProduct, includePhotos: Bool) -> ProductDTO {
        ProductDTO(
            identifier: product.identifier,
            name: product.name,
            batchNumber: product.batchNumber,
            barcode: product.barcode,
            supplier: product.supplier,
            supplierExpiryDate: product.supplierExpiryDate,
            openedAt: product.openedAt,
            secondaryLimitDate: product.secondaryLimitDate,
            storageRawValue: product.storageRawValue,
            statusRawValue: product.statusRawValue,
            labelPhotoData: photo(product.labelPhotoData, includePhotos: includePhotos),
            closedAt: product.closedAt,
            discardReason: product.discardReason,
            notes: product.notes,
            allergenRawValues: product.allergenRawValues,
            createdAt: product.createdAt
        )
    }

    private static func deliveryDTO(for delivery: DeliveryCheck, includePhotos: Bool) -> DeliveryDTO {
        DeliveryDTO(
            receivedAt: delivery.receivedAt,
            supplierName: delivery.supplierName,
            productLabel: delivery.productLabel,
            batchNumber: delivery.batchNumber,
            temperature: delivery.temperature,
            temperatureLimit: delivery.temperatureLimit,
            packagingIntact: delivery.packagingIntact,
            labellingCompliant: delivery.labellingCompliant,
            decisionRawValue: delivery.decisionRawValue,
            reason: delivery.reason,
            operatorName: delivery.operatorName,
            photoData: photo(delivery.photoData, includePhotos: includePhotos),
            notes: delivery.notes,
            createdAt: delivery.createdAt
        )
    }

    private static func cleaningRecordDTO(for record: CleaningRecord, includePhotos: Bool) -> CleaningRecordDTO {
        CleaningRecordDTO(
            completedAt: record.completedAt,
            operatorName: record.operatorName,
            productUsed: record.productUsed,
            comment: record.comment,
            photoData: photo(record.photoData, includePhotos: includePhotos)
        )
    }

    private static func cleaningTaskDTO(for task: CleaningTask, includePhotos: Bool) -> CleaningTaskDTO {
        CleaningTaskDTO(
            title: task.title,
            zone: task.zone,
            productUsed: task.productUsed,
            procedure: task.procedure,
            frequencyRawValue: task.frequencyRawValue,
            isActive: task.isActive,
            sortIndex: task.sortIndex,
            createdAt: task.createdAt,
            records: task.records.map { cleaningRecordDTO(for: $0, includePhotos: includePhotos) }
        )
    }

    private static func checkpointDTO(for checkpoint: ThermalCheckpoint) -> CheckpointDTO {
        CheckpointDTO(recordedAt: checkpoint.recordedAt, temperature: checkpoint.temperature)
    }

    private static func thermalDTO(for record: ThermalProcessRecord) -> ThermalDTO {
        ThermalDTO(
            kindRawValue: record.kindRawValue,
            productName: record.productName,
            batchNumber: record.batchNumber,
            startedAt: record.startedAt,
            startTemperature: record.startTemperature,
            finishedAt: record.finishedAt,
            endTemperature: record.endTemperature,
            targetTemperature: record.targetTemperature,
            maximumDurationSeconds: record.maximumDurationSeconds,
            operatorName: record.operatorName,
            comment: record.comment,
            correctiveAction: record.correctiveAction,
            isCompliant: record.isCompliant,
            createdAt: record.createdAt,
            checkpoints: record.checkpoints.map { checkpointDTO(for: $0) }
        )
    }

    private static func oilDTO(for check: OilCheckRecord) -> OilDTO {
        OilDTO(
            checkedAt: check.checkedAt,
            fryerName: check.fryerName,
            polarCompounds: check.polarCompounds,
            polarCompoundsLimit: check.polarCompoundsLimit,
            appearanceRawValue: check.appearanceRawValue,
            actionRawValue: check.actionRawValue,
            operatorName: check.operatorName,
            comment: check.comment,
            isCompliant: check.isCompliant,
            createdAt: check.createdAt
        )
    }

    private static func pestDTO(for visit: PestControlVisit, includePhotos: Bool) -> PestDTO {
        PestDTO(
            visitedAt: visit.visitedAt,
            company: visit.company,
            technician: visit.technician,
            findings: visit.findings,
            baitsReplaced: visit.baitsReplaced,
            deviceCount: visit.deviceCount,
            actionsTaken: visit.actionsTaken,
            nextVisitDate: visit.nextVisitDate,
            reportPhotoData: photo(visit.reportPhotoData, includePhotos: includePhotos),
            hasInfestation: visit.hasInfestation,
            createdAt: visit.createdAt
        )
    }

    private static func trainingDTO(for training: StaffTraining, includePhotos: Bool) -> TrainingDTO {
        TrainingDTO(
            personName: training.personName,
            title: training.title,
            organisation: training.organisation,
            completedAt: training.completedAt,
            expiresAt: training.expiresAt,
            certificateData: photo(training.certificateData, includePhotos: includePhotos),
            notes: training.notes,
            createdAt: training.createdAt
        )
    }

    private static func dishDTO(for dish: Dish) -> DishDTO {
        DishDTO(
            name: dish.name,
            categoryRawValue: dish.categoryRawValue,
            summary: dish.summary,
            composition: dish.composition,
            allergenRawValues: dish.allergenRawValues,
            isAvailable: dish.isAvailable,
            isHomemade: dish.isHomemade,
            sortIndex: dish.sortIndex,
            createdAt: dish.createdAt,
            updatedAt: dish.updatedAt
        )
    }

    /// Écrit l'archive dans un fichier temporaire prêt à être partagé.
    static func writeToTemporaryFile(_ archive: BackupArchive) throws -> URL {
        let data = try encoder.encode(archive)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: archive))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileName(for archive: BackupArchive) -> String {
        let stamp = AppFormatters.fileStamp(archive.exportedAt)
        let suffix = archive.includesPhotos ? "" : "-sans-photos"
        return "HACCP-Pocket-Sauvegarde-\(stamp)\(suffix).json"
    }

    // MARK: Lecture d'un fichier

    /// Décode une archive sans rien modifier : l'utilisateur doit pouvoir
    /// vérifier ce que contient le fichier avant d'écraser sa base.
    static func readArchive(at url: URL) throws -> BackupArchive {

        // Un fichier choisi dans l'app Fichiers appartient à un autre
        // processus : il faut demander l'accès puis le relâcher.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw BackupError.unreadableFile
        }

        guard let archive = try? decoder.decode(BackupArchive.self, from: data) else {
            throw BackupError.invalidFormat
        }

        guard archive.formatVersion <= BackupArchive.currentFormatVersion else {
            throw BackupError.futureFormat(archive.formatVersion)
        }

        return archive
    }

    // MARK: Restauration

    /// Remplace intégralement le contenu de la base par celui de l'archive.
    ///
    /// La restauration écrase : c'est volontaire. Fusionner deux bases
    /// obligerait à deviner quels enregistrements sont « les mêmes », et un
    /// registre sanitaire en double vaut moins qu'un registre juste.
    @discardableResult
    static func restore(_ archive: BackupArchive, into context: ModelContext) throws -> Int {

        try eraseEverything(in: context)

        // Une fonction par modèle : chacune reste courte, et le compilateur
        // n'a jamais à vérifier une fonction de deux cents lignes.
        restoreEstablishments(archive.establishments, into: context)
        restoreEquipments(archive.equipments, into: context)
        restoreProducts(archive.products, into: context)
        restoreDeliveries(archive.deliveries, into: context)
        restoreCleaningTasks(archive.cleaningTasks, into: context)
        restoreThermalRecords(archive.thermalRecords, into: context)
        restoreOilChecks(archive.oilChecks, into: context)
        restorePestVisits(archive.pestVisits, into: context)
        restoreTrainings(archive.trainings, into: context)
        restoreDishes(archive.dishes, into: context)

        try context.save()
        return archive.totalRecords
    }

    // MARK: Restauration, modèle par modèle

    private static func restoreEstablishments(_ items: [EstablishmentDTO], into context: ModelContext) {
        for dto in items {
            let establishment = Establishment(
                name: dto.name,
                address: dto.address,
                siret: dto.siret,
                managerName: dto.managerName,
                approvalNumber: dto.approvalNumber,
                logoData: dto.logoData,
                createdAt: dto.createdAt
            )
            establishment.updatedAt = dto.updatedAt
            context.insert(establishment)
        }
    }

    private static func restoreEquipments(_ items: [EquipmentDTO], into context: ModelContext) {
        for dto in items {
            let type = EquipmentType(rawValue: dto.typeRawValue) ?? .positiveCold
            let equipment = Equipment(
                name: dto.name,
                type: type,
                location: dto.location,
                minTemperature: dto.minTemperature,
                maxTemperature: dto.maxTemperature,
                sortIndex: dto.sortIndex,
                isActive: dto.isActive,
                createdAt: dto.createdAt
            )
            // On recopie la valeur brute : un type inconnu, écrit par une
            // version plus récente, doit survivre à l'aller-retour.
            equipment.typeRawValue = dto.typeRawValue
            context.insert(equipment)

            restoreReadings(dto.readings, of: equipment, into: context)
        }
    }

    private static func restoreReadings(
        _ items: [ReadingDTO],
        of equipment: Equipment,
        into context: ModelContext
    ) {
        for dto in items {
            let moment = ReadingMoment(rawValue: dto.momentRawValue) ?? .other
            let reading = TemperatureReading(
                value: dto.value,
                equipment: equipment,
                moment: moment,
                operatorName: dto.operatorName,
                comment: dto.comment,
                correctiveAction: dto.correctiveAction,
                recordedAt: dto.recordedAt
            )
            // Les seuils sont figés au moment du relevé : on restaure ceux de
            // l'archive, pas ceux de l'enceinte d'aujourd'hui.
            reading.thresholdMin = dto.thresholdMin
            reading.thresholdMax = dto.thresholdMax
            reading.isCompliant = dto.isCompliant
            context.insert(reading)
        }
    }

    private static func restoreProducts(_ items: [ProductDTO], into context: ModelContext) {
        for dto in items {
            let storage = StorageZone(rawValue: dto.storageRawValue) ?? .positiveCold
            let status = ProductStatus(rawValue: dto.statusRawValue) ?? .inUse

            let product = TrackedProduct(
                name: dto.name,
                openedAt: dto.openedAt,
                secondaryLimitDate: dto.secondaryLimitDate,
                storage: storage,
                status: status,
                batchNumber: dto.batchNumber,
                barcode: dto.barcode,
                supplier: dto.supplier,
                supplierExpiryDate: dto.supplierExpiryDate,
                labelPhotoData: dto.labelPhotoData,
                notes: dto.notes,
                createdAt: dto.createdAt,
                identifier: dto.identifier
            )
            product.closedAt = dto.closedAt
            product.discardReason = dto.discardReason
            product.allergenRawValues = dto.allergenRawValues
            context.insert(product)
        }
    }

    private static func restoreDeliveries(_ items: [DeliveryDTO], into context: ModelContext) {
        for dto in items {
            let decision = DeliveryDecision(rawValue: dto.decisionRawValue) ?? .accepted
            let delivery = DeliveryCheck(
                supplierName: dto.supplierName,
                productLabel: dto.productLabel,
                receivedAt: dto.receivedAt,
                temperature: dto.temperature,
                temperatureLimit: dto.temperatureLimit,
                packagingIntact: dto.packagingIntact,
                labellingCompliant: dto.labellingCompliant,
                decision: decision,
                reason: dto.reason,
                batchNumber: dto.batchNumber,
                operatorName: dto.operatorName,
                photoData: dto.photoData,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(delivery)
        }
    }

    private static func restoreCleaningTasks(_ items: [CleaningTaskDTO], into context: ModelContext) {
        for dto in items {
            let frequency = CleaningFrequency(rawValue: dto.frequencyRawValue) ?? .daily
            let task = CleaningTask(
                title: dto.title,
                frequency: frequency,
                zone: dto.zone,
                productUsed: dto.productUsed,
                procedure: dto.procedure,
                isActive: dto.isActive,
                sortIndex: dto.sortIndex,
                createdAt: dto.createdAt
            )
            context.insert(task)

            restoreCleaningRecords(dto.records, of: task, into: context)
        }
    }

    private static func restoreCleaningRecords(
        _ items: [CleaningRecordDTO],
        of task: CleaningTask,
        into context: ModelContext
    ) {
        for dto in items {
            let record = CleaningRecord(
                task: task,
                completedAt: dto.completedAt,
                operatorName: dto.operatorName,
                productUsed: dto.productUsed,
                comment: dto.comment,
                photoData: dto.photoData
            )
            context.insert(record)
        }
    }

    private static func restoreThermalRecords(_ items: [ThermalDTO], into context: ModelContext) {
        for dto in items {
            let kind = ThermalProcessKind(rawValue: dto.kindRawValue) ?? .cooling
            let record = ThermalProcessRecord(
                kind: kind,
                productName: dto.productName,
                startTemperature: dto.startTemperature,
                batchNumber: dto.batchNumber,
                operatorName: dto.operatorName,
                startedAt: dto.startedAt,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            // Les seuils sont figés à l'ouverture de l'opération : ils
            // viennent de l'archive, pas des règles d'aujourd'hui.
            record.finishedAt = dto.finishedAt
            record.endTemperature = dto.endTemperature
            record.targetTemperature = dto.targetTemperature
            record.maximumDurationSeconds = dto.maximumDurationSeconds
            record.correctiveAction = dto.correctiveAction
            record.isCompliant = dto.isCompliant
            context.insert(record)

            for pointDTO in dto.checkpoints {
                let point = ThermalCheckpoint(
                    temperature: pointDTO.temperature,
                    recordedAt: pointDTO.recordedAt,
                    record: record
                )
                context.insert(point)
            }
        }
    }

    private static func restoreOilChecks(_ items: [OilDTO], into context: ModelContext) {
        for dto in items {
            let appearance = OilAppearance(rawValue: dto.appearanceRawValue) ?? .clear
            let action = OilAction(rawValue: dto.actionRawValue) ?? .kept

            let check = OilCheckRecord(
                fryerName: dto.fryerName,
                checkedAt: dto.checkedAt,
                polarCompounds: dto.polarCompounds,
                appearance: appearance,
                action: action,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            check.polarCompoundsLimit = dto.polarCompoundsLimit
            check.isCompliant = dto.isCompliant
            context.insert(check)
        }
    }

    private static func restorePestVisits(_ items: [PestDTO], into context: ModelContext) {
        for dto in items {
            let visit = PestControlVisit(
                company: dto.company,
                visitedAt: dto.visitedAt,
                technician: dto.technician,
                findings: dto.findings,
                baitsReplaced: dto.baitsReplaced,
                deviceCount: dto.deviceCount,
                actionsTaken: dto.actionsTaken,
                nextVisitDate: dto.nextVisitDate,
                hasInfestation: dto.hasInfestation,
                reportPhotoData: dto.reportPhotoData,
                createdAt: dto.createdAt
            )
            context.insert(visit)
        }
    }

    private static func restoreTrainings(_ items: [TrainingDTO], into context: ModelContext) {
        for dto in items {
            let training = StaffTraining(
                personName: dto.personName,
                title: dto.title,
                organisation: dto.organisation,
                completedAt: dto.completedAt,
                expiresAt: dto.expiresAt,
                certificateData: dto.certificateData,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(training)
        }
    }

    private static func restoreDishes(_ items: [DishDTO], into context: ModelContext) {
        for dto in items {
            let category = DishCategory(rawValue: dto.categoryRawValue) ?? .main
            let dish = Dish(
                name: dto.name,
                category: category,
                summary: dto.summary,
                composition: dto.composition,
                isAvailable: dto.isAvailable,
                isHomemade: dto.isHomemade,
                sortIndex: dto.sortIndex,
                createdAt: dto.createdAt
            )
            // Valeurs brutes recopiées telles quelles : une archive doit se
            // restaurer à l'identique, même écrite par une version différente.
            dish.allergenRawValues = dto.allergenRawValues
            dish.updatedAt = dto.updatedAt
            context.insert(dish)
        }
    }

    /// Vide la base. Les objets enfants (relevés, enregistrements de nettoyage,
    /// points de contrôle) partent par cascade, mais on les supprime aussi
    /// explicitement pour ne rien laisser derrière en cas d'orphelin.
    static func eraseEverything(in context: ModelContext) throws {
        try delete(TemperatureReading.self, in: context)
        try delete(CleaningRecord.self, in: context)
        try delete(ThermalCheckpoint.self, in: context)

        try delete(Equipment.self, in: context)
        try delete(CleaningTask.self, in: context)
        try delete(ThermalProcessRecord.self, in: context)
        try delete(TrackedProduct.self, in: context)
        try delete(DeliveryCheck.self, in: context)
        try delete(OilCheckRecord.self, in: context)
        try delete(PestControlVisit.self, in: context)
        try delete(StaffTraining.self, in: context)
        try delete(Dish.self, in: context)
        try delete(Establishment.self, in: context)

        try context.save()
    }

    private static func delete<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}
