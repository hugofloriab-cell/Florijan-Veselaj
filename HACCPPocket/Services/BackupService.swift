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
        establishments.count
            + equipments.count
            + equipments.reduce(0) { $0 + $1.readings.count }
            + products.count
            + deliveries.count
            + cleaningTasks.count
            + cleaningTasks.reduce(0) { $0 + $1.records.count }
            + thermalRecords.count
            + oilChecks.count
            + pestVisits.count
            + trainings.count
            + dishes.count
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

        func photo(_ data: Data?) -> Data? { includePhotos ? data : nil }

        archive.establishments = try context.fetch(FetchDescriptor<Establishment>()).map {
            EstablishmentDTO(
                name: $0.name,
                address: $0.address,
                siret: $0.siret,
                managerName: $0.managerName,
                approvalNumber: $0.approvalNumber,
                logoData: photo($0.logoData),
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        archive.equipments = try context.fetch(FetchDescriptor<Equipment>()).map { equipment in
            EquipmentDTO(
                name: equipment.name,
                typeRawValue: equipment.typeRawValue,
                location: equipment.location,
                minTemperature: equipment.minTemperature,
                maxTemperature: equipment.maxTemperature,
                sortIndex: equipment.sortIndex,
                isActive: equipment.isActive,
                createdAt: equipment.createdAt,
                readings: equipment.readings.map { reading in
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
            )
        }

        archive.products = try context.fetch(FetchDescriptor<TrackedProduct>()).map {
            ProductDTO(
                identifier: $0.identifier,
                name: $0.name,
                batchNumber: $0.batchNumber,
                barcode: $0.barcode,
                supplier: $0.supplier,
                supplierExpiryDate: $0.supplierExpiryDate,
                openedAt: $0.openedAt,
                secondaryLimitDate: $0.secondaryLimitDate,
                storageRawValue: $0.storageRawValue,
                statusRawValue: $0.statusRawValue,
                labelPhotoData: photo($0.labelPhotoData),
                closedAt: $0.closedAt,
                discardReason: $0.discardReason,
                notes: $0.notes,
                allergenRawValues: $0.allergenRawValues,
                createdAt: $0.createdAt
            )
        }

        archive.deliveries = try context.fetch(FetchDescriptor<DeliveryCheck>()).map {
            DeliveryDTO(
                receivedAt: $0.receivedAt,
                supplierName: $0.supplierName,
                productLabel: $0.productLabel,
                batchNumber: $0.batchNumber,
                temperature: $0.temperature,
                temperatureLimit: $0.temperatureLimit,
                packagingIntact: $0.packagingIntact,
                labellingCompliant: $0.labellingCompliant,
                decisionRawValue: $0.decisionRawValue,
                reason: $0.reason,
                operatorName: $0.operatorName,
                photoData: photo($0.photoData),
                notes: $0.notes,
                createdAt: $0.createdAt
            )
        }

        archive.cleaningTasks = try context.fetch(FetchDescriptor<CleaningTask>()).map { task in
            CleaningTaskDTO(
                title: task.title,
                zone: task.zone,
                productUsed: task.productUsed,
                procedure: task.procedure,
                frequencyRawValue: task.frequencyRawValue,
                isActive: task.isActive,
                sortIndex: task.sortIndex,
                createdAt: task.createdAt,
                records: task.records.map { record in
                    CleaningRecordDTO(
                        completedAt: record.completedAt,
                        operatorName: record.operatorName,
                        productUsed: record.productUsed,
                        comment: record.comment,
                        photoData: photo(record.photoData)
                    )
                }
            )
        }

        archive.thermalRecords = try context.fetch(FetchDescriptor<ThermalProcessRecord>()).map { record in
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
                checkpoints: record.checkpoints.map { point in
                    CheckpointDTO(recordedAt: point.recordedAt, temperature: point.temperature)
                }
            )
        }

        archive.oilChecks = try context.fetch(FetchDescriptor<OilCheckRecord>()).map {
            OilDTO(
                checkedAt: $0.checkedAt,
                fryerName: $0.fryerName,
                polarCompounds: $0.polarCompounds,
                polarCompoundsLimit: $0.polarCompoundsLimit,
                appearanceRawValue: $0.appearanceRawValue,
                actionRawValue: $0.actionRawValue,
                operatorName: $0.operatorName,
                comment: $0.comment,
                isCompliant: $0.isCompliant,
                createdAt: $0.createdAt
            )
        }

        archive.pestVisits = try context.fetch(FetchDescriptor<PestControlVisit>()).map {
            PestDTO(
                visitedAt: $0.visitedAt,
                company: $0.company,
                technician: $0.technician,
                findings: $0.findings,
                baitsReplaced: $0.baitsReplaced,
                deviceCount: $0.deviceCount,
                actionsTaken: $0.actionsTaken,
                nextVisitDate: $0.nextVisitDate,
                reportPhotoData: photo($0.reportPhotoData),
                hasInfestation: $0.hasInfestation,
                createdAt: $0.createdAt
            )
        }

        archive.trainings = try context.fetch(FetchDescriptor<StaffTraining>()).map {
            TrainingDTO(
                personName: $0.personName,
                title: $0.title,
                organisation: $0.organisation,
                completedAt: $0.completedAt,
                expiresAt: $0.expiresAt,
                certificateData: photo($0.certificateData),
                notes: $0.notes,
                createdAt: $0.createdAt
            )
        }

        archive.dishes = try context.fetch(FetchDescriptor<Dish>()).map {
            DishDTO(
                name: $0.name,
                categoryRawValue: $0.categoryRawValue,
                summary: $0.summary,
                composition: $0.composition,
                allergenRawValues: $0.allergenRawValues,
                isAvailable: $0.isAvailable,
                isHomemade: $0.isHomemade,
                sortIndex: $0.sortIndex,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        return archive
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

        for dto in archive.establishments {
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

        for dto in archive.equipments {
            let equipment = Equipment(
                name: dto.name,
                type: EquipmentType(rawValue: dto.typeRawValue) ?? .positiveCold,
                location: dto.location,
                minTemperature: dto.minTemperature,
                maxTemperature: dto.maxTemperature,
                sortIndex: dto.sortIndex,
                isActive: dto.isActive,
                createdAt: dto.createdAt
            )
            equipment.typeRawValue = dto.typeRawValue
            context.insert(equipment)

            for readingDTO in dto.readings {
                let reading = TemperatureReading(
                    value: readingDTO.value,
                    equipment: equipment,
                    moment: ReadingMoment(rawValue: readingDTO.momentRawValue) ?? .other,
                    operatorName: readingDTO.operatorName,
                    comment: readingDTO.comment,
                    correctiveAction: readingDTO.correctiveAction,
                    recordedAt: readingDTO.recordedAt
                )
                // Les seuils sont figés au moment du relevé : on restaure ceux
                // de l'archive, pas ceux de l'enceinte d'aujourd'hui.
                reading.thresholdMin = readingDTO.thresholdMin
                reading.thresholdMax = readingDTO.thresholdMax
                reading.isCompliant = readingDTO.isCompliant
                context.insert(reading)
            }
        }

        for dto in archive.products {
            let product = TrackedProduct(
                name: dto.name,
                openedAt: dto.openedAt,
                secondaryLimitDate: dto.secondaryLimitDate,
                storage: StorageZone(rawValue: dto.storageRawValue) ?? .positiveCold,
                status: ProductStatus(rawValue: dto.statusRawValue) ?? .inUse,
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

        for dto in archive.deliveries {
            let delivery = DeliveryCheck(
                supplierName: dto.supplierName,
                productLabel: dto.productLabel,
                receivedAt: dto.receivedAt,
                temperature: dto.temperature,
                temperatureLimit: dto.temperatureLimit,
                packagingIntact: dto.packagingIntact,
                labellingCompliant: dto.labellingCompliant,
                decision: DeliveryDecision(rawValue: dto.decisionRawValue) ?? .accepted,
                reason: dto.reason,
                batchNumber: dto.batchNumber,
                operatorName: dto.operatorName,
                photoData: dto.photoData,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(delivery)
        }

        for dto in archive.cleaningTasks {
            let task = CleaningTask(
                title: dto.title,
                frequency: CleaningFrequency(rawValue: dto.frequencyRawValue) ?? .daily,
                zone: dto.zone,
                productUsed: dto.productUsed,
                procedure: dto.procedure,
                isActive: dto.isActive,
                sortIndex: dto.sortIndex,
                createdAt: dto.createdAt
            )
            context.insert(task)

            for recordDTO in dto.records {
                let record = CleaningRecord(
                    task: task,
                    completedAt: recordDTO.completedAt,
                    operatorName: recordDTO.operatorName,
                    productUsed: recordDTO.productUsed,
                    comment: recordDTO.comment,
                    photoData: recordDTO.photoData
                )
                context.insert(record)
            }
        }

        for dto in archive.thermalRecords {
            let record = ThermalProcessRecord(
                kind: ThermalProcessKind(rawValue: dto.kindRawValue) ?? .cooling,
                productName: dto.productName,
                startTemperature: dto.startTemperature,
                batchNumber: dto.batchNumber,
                operatorName: dto.operatorName,
                startedAt: dto.startedAt,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
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

        for dto in archive.oilChecks {
            let check = OilCheckRecord(
                fryerName: dto.fryerName,
                checkedAt: dto.checkedAt,
                polarCompounds: dto.polarCompounds,
                appearance: OilAppearance(rawValue: dto.appearanceRawValue) ?? .clear,
                action: OilAction(rawValue: dto.actionRawValue) ?? .kept,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            check.polarCompoundsLimit = dto.polarCompoundsLimit
            check.isCompliant = dto.isCompliant
            context.insert(check)
        }

        for dto in archive.pestVisits {
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

        for dto in archive.trainings {
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

        for dto in archive.dishes {
            let dish = Dish(
                name: dto.name,
                category: DishCategory(rawValue: dto.categoryRawValue) ?? .main,
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

        try context.save()
        return archive.totalRecords
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
