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
    var thawings: [ThawingDTO] = []
    var foodSamples: [FoodSampleDTO] = []
    var sanitizingFreezes: [SanitizingDTO] = []
    var beefOrigins: [BeefOriginDTO] = []
    var hygieneChecks: [HygieneCheckDTO] = []
    var medicalRecords: [MedicalFitnessDTO] = []
    var cleaningProducts: [CleaningProductDTO] = []
    var documents: [RegulatoryDocumentDTO] = []
    var maintenance: [MaintenanceDTO] = []
    var recalls: [ProductRecallDTO] = []
    var analyses: [LabAnalysisDTO] = []
    var waterControls: [WaterControlDTO] = []
    var oilCollections: [WasteOilDTO] = []
    var seals: [IntegritySealDTO] = []

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
        total += thawings.count
        total += foodSamples.count
        total += sanitizingFreezes.count
        total += beefOrigins.count
        total += hygieneChecks.count
        total += medicalRecords.count
        total += cleaningProducts.count
        total += documents.count
        total += maintenance.count
        total += recalls.count
        total += analyses.count
        total += waterControls.count
        total += oilCollections.count
        total += seals.count

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
    var signatureData: Data?
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

struct ThawingDTO: Codable {
    var productName: String
    var batchNumber: String
    var location: String
    var methodRawValue: String
    var startedAt: Date
    var finishedAt: Date?
    var originalExpiryDate: Date?
    var shelfLifeDays: Int
    var quantity: String
    var operatorName: String
    var comment: String
    var createdAt: Date
}

struct FoodSampleDTO: Codable {
    var dishName: String
    var serviceLabel: String
    var collectedAt: Date
    var lastServedAt: Date
    var quantityGrams: Int
    var coverCount: Int
    var storageLocation: String
    var operatorName: String
    var comment: String
    var discardedAt: Date?
    var createdAt: Date
}

struct SanitizingDTO: Codable {
    var productName: String
    var batchNumber: String
    var supplier: String
    var intendedUse: String
    var scheduleRawValue: String
    var startedAt: Date
    var finishedAt: Date?
    var coreTemperature: Double?
    var equipmentName: String
    var quantity: String
    var operatorName: String
    var comment: String
    var isCompliant: Bool
    var createdAt: Date
}

struct BeefOriginDTO: Codable {
    var cutName: String
    var batchNumber: String
    var supplier: String
    var birthCountry: String
    var rearingCountry: String
    var slaughterCountry: String
    var slaughterhouseApproval: String
    var cuttingPlantApproval: String
    var receivedAt: Date
    var quantity: String
    var labelPhotoData: Data?
    var operatorName: String
    var comment: String
    var createdAt: Date
}

struct HygieneCheckDTO: Codable {
    var personName: String
    var shiftLabel: String
    var checkedAt: Date
    var passedRawValues: [String]
    var failedRawValues: [String]
    var correctiveAction: String
    var signatureData: Data?
    var checkedBy: String
    var comment: String
    var createdAt: Date
}

struct MedicalFitnessDTO: Codable {
    var personName: String
    var jobTitle: String
    var occupationalHealthService: String
    var examinedAt: Date
    var nextVisitDate: Date?
    var verdictRawValue: String
    var restrictions: String
    var documentData: Data?
    var comment: String
    var createdAt: Date
}

struct CleaningProductDTO: Codable {
    var name: String
    var supplier: String
    var kindRawValue: String
    var dilution: String
    var contactTimeSeconds: Int
    var requiresRinsing: Bool
    var usage: String
    var hazards: String
    var standard: String
    var safetyDataSheet: Data?
    var isActive: Bool
    var comment: String
    var createdAt: Date
    var updatedAt: Date
}

struct RegulatoryDocumentDTO: Codable {
    var title: String
    var categoryRawValue: String
    var issuer: String
    var issuedAt: Date
    var expiresAt: Date?
    var reference: String
    var fileData: Data?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

struct MaintenanceDTO: Codable {
    var equipmentName: String
    var kindRawValue: String
    var occurredAt: Date
    var provider: String
    var observation: String
    var actionTaken: String
    var calibrationReference: String
    var expectedValue: Double?
    var measuredValue: Double?
    var nextDueDate: Date?
    var isResolved: Bool
    var documentData: Data?
    var operatorName: String
    var notes: String
    var createdAt: Date
}

struct ProductRecallDTO: Codable {
    var productName: String
    var brand: String
    var affectedBatches: String
    var supplier: String
    var noticeReference: String
    var reason: String
    var scopeRawValue: String
    var noticedAt: Date
    var isolatedAt: Date?
    var quantityHeld: String
    var outcomeRawValue: String
    var proofData: Data?
    var wasServed: Bool
    var customersInformed: Bool
    var authorityInformed: Bool
    var authorityInformedAt: Date?
    var operatorName: String
    var notes: String
    var closedAt: Date?
    var createdAt: Date
}

struct LabAnalysisDTO: Codable {
    var sampleName: String
    var kindRawValue: String
    var location: String
    var sampledAt: Date
    var laboratory: String
    var reportReference: String
    var resultRawValue: String
    var resultReceivedAt: Date?
    var findings: String
    var correctiveAction: String
    var reportData: Data?
    var nextDueDate: Date?
    var operatorName: String
    var notes: String
    var createdAt: Date
}

struct WaterControlDTO: Codable {
    var kindRawValue: String
    var location: String
    var performedAt: Date
    var measuredValue: Double?
    var isPrivateSupply: Bool
    var isCompliant: Bool
    var correctiveAction: String
    var nextDueDate: Date?
    var documentData: Data?
    var operatorName: String
    var notes: String
    var createdAt: Date
}

struct WasteOilDTO: Codable {
    var collectedAt: Date
    var collector: String
    var collectorApproval: String
    var documentReference: String
    var quantity: Double
    var unitRawValue: String
    var containerCount: Int
    var documentData: Data?
    var operatorName: String
    var notes: String
    var createdAt: Date
}

struct IntegritySealDTO: Codable {
    var periodStart: Date
    var sealedAt: Date
    var digest: String
    var previousDigest: String
    var recordCount: Int
    var sequence: Int
    var sealedBy: String
    var createdAt: Date
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
        archive.thawings = try context.fetch(FetchDescriptor<ThawingRecord>())
            .map { thawingDTO(for: $0) }
        archive.foodSamples = try context.fetch(FetchDescriptor<FoodSample>())
            .map { foodSampleDTO(for: $0) }
        archive.sanitizingFreezes = try context.fetch(FetchDescriptor<SanitizingFreezeRecord>())
            .map { sanitizingDTO(for: $0) }
        archive.beefOrigins = try context.fetch(FetchDescriptor<BeefOriginRecord>())
            .map { beefOriginDTO(for: $0, includePhotos: includePhotos) }
        archive.hygieneChecks = try context.fetch(FetchDescriptor<ShiftHygieneCheck>())
            .map { hygieneCheckDTO(for: $0, includePhotos: includePhotos) }
        archive.medicalRecords = try context.fetch(FetchDescriptor<MedicalFitnessRecord>())
            .map { medicalDTO(for: $0, includePhotos: includePhotos) }
        archive.cleaningProducts = try context.fetch(FetchDescriptor<CleaningProduct>())
            .map { cleaningProductDTO(for: $0, includePhotos: includePhotos) }
        archive.documents = try context.fetch(FetchDescriptor<RegulatoryDocument>())
            .map { documentDTO(for: $0, includePhotos: includePhotos) }
        archive.maintenance = try context.fetch(FetchDescriptor<EquipmentMaintenance>())
            .map { maintenanceDTO(for: $0, includePhotos: includePhotos) }
        archive.recalls = try context.fetch(FetchDescriptor<ProductRecall>())
            .map { recallDTO(for: $0, includePhotos: includePhotos) }
        archive.analyses = try context.fetch(FetchDescriptor<LabAnalysis>())
            .map { analysisDTO(for: $0, includePhotos: includePhotos) }
        archive.waterControls = try context.fetch(FetchDescriptor<WaterControl>())
            .map { waterDTO(for: $0, includePhotos: includePhotos) }
        archive.oilCollections = try context.fetch(FetchDescriptor<WasteOilCollection>())
            .map { wasteOilDTO(for: $0, includePhotos: includePhotos) }
        archive.seals = try context.fetch(FetchDescriptor<IntegritySeal>())
            .map { sealDTO(for: $0) }

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
            photoData: photo(record.photoData, includePhotos: includePhotos),
            signatureData: photo(record.signatureData, includePhotos: includePhotos)
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

    private static func thawingDTO(for record: ThawingRecord) -> ThawingDTO {
        ThawingDTO(
            productName: record.productName,
            batchNumber: record.batchNumber,
            location: record.location,
            methodRawValue: record.methodRawValue,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            originalExpiryDate: record.originalExpiryDate,
            shelfLifeDays: record.shelfLifeDays,
            quantity: record.quantity,
            operatorName: record.operatorName,
            comment: record.comment,
            createdAt: record.createdAt
        )
    }

    private static func foodSampleDTO(for sample: FoodSample) -> FoodSampleDTO {
        FoodSampleDTO(
            dishName: sample.dishName,
            serviceLabel: sample.serviceLabel,
            collectedAt: sample.collectedAt,
            lastServedAt: sample.lastServedAt,
            quantityGrams: sample.quantityGrams,
            coverCount: sample.coverCount,
            storageLocation: sample.storageLocation,
            operatorName: sample.operatorName,
            comment: sample.comment,
            discardedAt: sample.discardedAt,
            createdAt: sample.createdAt
        )
    }

    private static func sanitizingDTO(for record: SanitizingFreezeRecord) -> SanitizingDTO {
        SanitizingDTO(
            productName: record.productName,
            batchNumber: record.batchNumber,
            supplier: record.supplier,
            intendedUse: record.intendedUse,
            scheduleRawValue: record.scheduleRawValue,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            coreTemperature: record.coreTemperature,
            equipmentName: record.equipmentName,
            quantity: record.quantity,
            operatorName: record.operatorName,
            comment: record.comment,
            isCompliant: record.isCompliant,
            createdAt: record.createdAt
        )
    }

    private static func beefOriginDTO(for record: BeefOriginRecord, includePhotos: Bool) -> BeefOriginDTO {
        BeefOriginDTO(
            cutName: record.cutName,
            batchNumber: record.batchNumber,
            supplier: record.supplier,
            birthCountry: record.birthCountry,
            rearingCountry: record.rearingCountry,
            slaughterCountry: record.slaughterCountry,
            slaughterhouseApproval: record.slaughterhouseApproval,
            cuttingPlantApproval: record.cuttingPlantApproval,
            receivedAt: record.receivedAt,
            quantity: record.quantity,
            labelPhotoData: photo(record.labelPhotoData, includePhotos: includePhotos),
            operatorName: record.operatorName,
            comment: record.comment,
            createdAt: record.createdAt
        )
    }

    private static func hygieneCheckDTO(for check: ShiftHygieneCheck, includePhotos: Bool) -> HygieneCheckDTO {
        HygieneCheckDTO(
            personName: check.personName,
            shiftLabel: check.shiftLabel,
            checkedAt: check.checkedAt,
            passedRawValues: check.passedRawValues,
            failedRawValues: check.failedRawValues,
            correctiveAction: check.correctiveAction,
            signatureData: photo(check.signatureData, includePhotos: includePhotos),
            checkedBy: check.checkedBy,
            comment: check.comment,
            createdAt: check.createdAt
        )
    }

    private static func medicalDTO(for record: MedicalFitnessRecord, includePhotos: Bool) -> MedicalFitnessDTO {
        MedicalFitnessDTO(
            personName: record.personName,
            jobTitle: record.jobTitle,
            occupationalHealthService: record.occupationalHealthService,
            examinedAt: record.examinedAt,
            nextVisitDate: record.nextVisitDate,
            verdictRawValue: record.verdictRawValue,
            restrictions: record.restrictions,
            documentData: photo(record.documentData, includePhotos: includePhotos),
            comment: record.comment,
            createdAt: record.createdAt
        )
    }

    private static func cleaningProductDTO(for product: CleaningProduct, includePhotos: Bool) -> CleaningProductDTO {
        CleaningProductDTO(
            name: product.name,
            supplier: product.supplier,
            kindRawValue: product.kindRawValue,
            dilution: product.dilution,
            contactTimeSeconds: product.contactTimeSeconds,
            requiresRinsing: product.requiresRinsing,
            usage: product.usage,
            hazards: product.hazards,
            standard: product.standard,
            safetyDataSheet: photo(product.safetyDataSheet, includePhotos: includePhotos),
            isActive: product.isActive,
            comment: product.comment,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt
        )
    }

    private static func documentDTO(for document: RegulatoryDocument, includePhotos: Bool) -> RegulatoryDocumentDTO {
        RegulatoryDocumentDTO(
            title: document.title,
            categoryRawValue: document.categoryRawValue,
            issuer: document.issuer,
            issuedAt: document.issuedAt,
            expiresAt: document.expiresAt,
            reference: document.reference,
            fileData: photo(document.fileData, includePhotos: includePhotos),
            notes: document.notes,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt
        )
    }

    private static func maintenanceDTO(for record: EquipmentMaintenance, includePhotos: Bool) -> MaintenanceDTO {
        MaintenanceDTO(
            equipmentName: record.equipmentName,
            kindRawValue: record.kindRawValue,
            occurredAt: record.occurredAt,
            provider: record.provider,
            observation: record.observation,
            actionTaken: record.actionTaken,
            calibrationReference: record.calibrationReference,
            expectedValue: record.expectedValue,
            measuredValue: record.measuredValue,
            nextDueDate: record.nextDueDate,
            isResolved: record.isResolved,
            documentData: photo(record.documentData, includePhotos: includePhotos),
            operatorName: record.operatorName,
            notes: record.notes,
            createdAt: record.createdAt
        )
    }

    private static func recallDTO(for recall: ProductRecall, includePhotos: Bool) -> ProductRecallDTO {
        ProductRecallDTO(
            productName: recall.productName,
            brand: recall.brand,
            affectedBatches: recall.affectedBatches,
            supplier: recall.supplier,
            noticeReference: recall.noticeReference,
            reason: recall.reason,
            scopeRawValue: recall.scopeRawValue,
            noticedAt: recall.noticedAt,
            isolatedAt: recall.isolatedAt,
            quantityHeld: recall.quantityHeld,
            outcomeRawValue: recall.outcomeRawValue,
            proofData: photo(recall.proofData, includePhotos: includePhotos),
            wasServed: recall.wasServed,
            customersInformed: recall.customersInformed,
            authorityInformed: recall.authorityInformed,
            authorityInformedAt: recall.authorityInformedAt,
            operatorName: recall.operatorName,
            notes: recall.notes,
            closedAt: recall.closedAt,
            createdAt: recall.createdAt
        )
    }

    private static func analysisDTO(for analysis: LabAnalysis, includePhotos: Bool) -> LabAnalysisDTO {
        LabAnalysisDTO(
            sampleName: analysis.sampleName,
            kindRawValue: analysis.kindRawValue,
            location: analysis.location,
            sampledAt: analysis.sampledAt,
            laboratory: analysis.laboratory,
            reportReference: analysis.reportReference,
            resultRawValue: analysis.resultRawValue,
            resultReceivedAt: analysis.resultReceivedAt,
            findings: analysis.findings,
            correctiveAction: analysis.correctiveAction,
            reportData: photo(analysis.reportData, includePhotos: includePhotos),
            nextDueDate: analysis.nextDueDate,
            operatorName: analysis.operatorName,
            notes: analysis.notes,
            createdAt: analysis.createdAt
        )
    }

    private static func waterDTO(for control: WaterControl, includePhotos: Bool) -> WaterControlDTO {
        WaterControlDTO(
            kindRawValue: control.kindRawValue,
            location: control.location,
            performedAt: control.performedAt,
            measuredValue: control.measuredValue,
            isPrivateSupply: control.isPrivateSupply,
            isCompliant: control.isCompliant,
            correctiveAction: control.correctiveAction,
            nextDueDate: control.nextDueDate,
            documentData: photo(control.documentData, includePhotos: includePhotos),
            operatorName: control.operatorName,
            notes: control.notes,
            createdAt: control.createdAt
        )
    }

    private static func wasteOilDTO(for collection: WasteOilCollection, includePhotos: Bool) -> WasteOilDTO {
        WasteOilDTO(
            collectedAt: collection.collectedAt,
            collector: collection.collector,
            collectorApproval: collection.collectorApproval,
            documentReference: collection.documentReference,
            quantity: collection.quantity,
            unitRawValue: collection.unitRawValue,
            containerCount: collection.containerCount,
            documentData: photo(collection.documentData, includePhotos: includePhotos),
            operatorName: collection.operatorName,
            notes: collection.notes,
            createdAt: collection.createdAt
        )
    }

    private static func sealDTO(for seal: IntegritySeal) -> IntegritySealDTO {
        IntegritySealDTO(
            periodStart: seal.periodStart,
            sealedAt: seal.sealedAt,
            digest: seal.digest,
            previousDigest: seal.previousDigest,
            recordCount: seal.recordCount,
            sequence: seal.sequence,
            sealedBy: seal.sealedBy,
            createdAt: seal.createdAt
        )
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
        restoreThawings(archive.thawings, into: context)
        restoreFoodSamples(archive.foodSamples, into: context)
        restoreSanitizingFreezes(archive.sanitizingFreezes, into: context)
        restoreBeefOrigins(archive.beefOrigins, into: context)
        restoreHygieneChecks(archive.hygieneChecks, into: context)
        restoreMedicalRecords(archive.medicalRecords, into: context)
        restoreCleaningProducts(archive.cleaningProducts, into: context)
        restoreDocuments(archive.documents, into: context)
        restoreMaintenance(archive.maintenance, into: context)
        restoreRecalls(archive.recalls, into: context)
        restoreAnalyses(archive.analyses, into: context)
        restoreWaterControls(archive.waterControls, into: context)
        restoreOilCollections(archive.oilCollections, into: context)
        restoreSeals(archive.seals, into: context)

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
            record.signatureData = dto.signatureData
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

    private static func restoreThawings(_ items: [ThawingDTO], into context: ModelContext) {
        for dto in items {
            let record = ThawingRecord(
                productName: dto.productName,
                batchNumber: dto.batchNumber,
                location: dto.location,
                method: ThawingMethod(rawValue: dto.methodRawValue) ?? .coldRoom,
                startedAt: dto.startedAt,
                originalExpiryDate: dto.originalExpiryDate,
                shelfLifeDays: dto.shelfLifeDays,
                quantity: dto.quantity,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            record.finishedAt = dto.finishedAt
            context.insert(record)
        }
    }

    private static func restoreFoodSamples(_ items: [FoodSampleDTO], into context: ModelContext) {
        for dto in items {
            let sample = FoodSample(
                dishName: dto.dishName,
                serviceLabel: dto.serviceLabel,
                collectedAt: dto.collectedAt,
                lastServedAt: dto.lastServedAt,
                quantityGrams: dto.quantityGrams,
                coverCount: dto.coverCount,
                storageLocation: dto.storageLocation,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            sample.discardedAt = dto.discardedAt
            context.insert(sample)
        }
    }

    private static func restoreSanitizingFreezes(_ items: [SanitizingDTO], into context: ModelContext) {
        for dto in items {
            let record = SanitizingFreezeRecord(
                productName: dto.productName,
                batchNumber: dto.batchNumber,
                supplier: dto.supplier,
                intendedUse: dto.intendedUse,
                schedule: SanitizingSchedule(rawValue: dto.scheduleRawValue) ?? .minus20,
                startedAt: dto.startedAt,
                equipmentName: dto.equipmentName,
                quantity: dto.quantity,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            record.finishedAt = dto.finishedAt
            record.coreTemperature = dto.coreTemperature
            record.isCompliant = dto.isCompliant
            context.insert(record)
        }
    }

    private static func restoreBeefOrigins(_ items: [BeefOriginDTO], into context: ModelContext) {
        for dto in items {
            let record = BeefOriginRecord(
                cutName: dto.cutName,
                batchNumber: dto.batchNumber,
                supplier: dto.supplier,
                birthCountry: dto.birthCountry,
                rearingCountry: dto.rearingCountry,
                slaughterCountry: dto.slaughterCountry,
                slaughterhouseApproval: dto.slaughterhouseApproval,
                cuttingPlantApproval: dto.cuttingPlantApproval,
                receivedAt: dto.receivedAt,
                quantity: dto.quantity,
                labelPhotoData: dto.labelPhotoData,
                operatorName: dto.operatorName,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            context.insert(record)
        }
    }

    private static func restoreHygieneChecks(_ items: [HygieneCheckDTO], into context: ModelContext) {
        for dto in items {
            let check = ShiftHygieneCheck(
                personName: dto.personName,
                shiftLabel: dto.shiftLabel,
                checkedAt: dto.checkedAt,
                correctiveAction: dto.correctiveAction,
                signatureData: dto.signatureData,
                checkedBy: dto.checkedBy,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            // Valeurs brutes recopiées telles quelles.
            check.passedRawValues = dto.passedRawValues
            check.failedRawValues = dto.failedRawValues
            context.insert(check)
        }
    }

    private static func restoreMedicalRecords(_ items: [MedicalFitnessDTO], into context: ModelContext) {
        for dto in items {
            let record = MedicalFitnessRecord(
                personName: dto.personName,
                jobTitle: dto.jobTitle,
                occupationalHealthService: dto.occupationalHealthService,
                examinedAt: dto.examinedAt,
                nextVisitDate: dto.nextVisitDate,
                verdict: FitnessVerdict(rawValue: dto.verdictRawValue) ?? .fit,
                restrictions: dto.restrictions,
                documentData: dto.documentData,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            context.insert(record)
        }
    }

    private static func restoreCleaningProducts(_ items: [CleaningProductDTO], into context: ModelContext) {
        for dto in items {
            let product = CleaningProduct(
                name: dto.name,
                supplier: dto.supplier,
                kind: CleaningProductKind(rawValue: dto.kindRawValue) ?? .detergent,
                dilution: dto.dilution,
                contactTimeSeconds: dto.contactTimeSeconds,
                requiresRinsing: dto.requiresRinsing,
                usage: dto.usage,
                hazards: dto.hazards,
                standard: dto.standard,
                safetyDataSheet: dto.safetyDataSheet,
                isActive: dto.isActive,
                comment: dto.comment,
                createdAt: dto.createdAt
            )
            product.updatedAt = dto.updatedAt
            context.insert(product)
        }
    }

    private static func restoreDocuments(_ items: [RegulatoryDocumentDTO], into context: ModelContext) {
        for dto in items {
            let document = RegulatoryDocument(
                title: dto.title,
                category: DocumentCategory(rawValue: dto.categoryRawValue) ?? .other,
                issuer: dto.issuer,
                issuedAt: dto.issuedAt,
                expiresAt: dto.expiresAt,
                reference: dto.reference,
                fileData: dto.fileData,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            document.updatedAt = dto.updatedAt
            context.insert(document)
        }
    }

    private static func restoreMaintenance(_ items: [MaintenanceDTO], into context: ModelContext) {
        for dto in items {
            let record = EquipmentMaintenance(
                equipmentName: dto.equipmentName,
                kind: MaintenanceKind(rawValue: dto.kindRawValue) ?? .preventive,
                occurredAt: dto.occurredAt,
                provider: dto.provider,
                observation: dto.observation,
                actionTaken: dto.actionTaken,
                calibrationReference: dto.calibrationReference,
                expectedValue: dto.expectedValue,
                measuredValue: dto.measuredValue,
                nextDueDate: dto.nextDueDate,
                isResolved: dto.isResolved,
                documentData: dto.documentData,
                operatorName: dto.operatorName,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(record)
        }
    }

    private static func restoreRecalls(_ items: [ProductRecallDTO], into context: ModelContext) {
        for dto in items {
            let recall = ProductRecall(
                productName: dto.productName,
                brand: dto.brand,
                affectedBatches: dto.affectedBatches,
                supplier: dto.supplier,
                noticeReference: dto.noticeReference,
                reason: dto.reason,
                scope: RecallScope(rawValue: dto.scopeRawValue) ?? .withdrawal,
                noticedAt: dto.noticedAt,
                quantityHeld: dto.quantityHeld,
                outcome: RecallOutcome(rawValue: dto.outcomeRawValue) ?? .pending,
                wasServed: dto.wasServed,
                operatorName: dto.operatorName,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            recall.isolatedAt = dto.isolatedAt
            recall.proofData = dto.proofData
            recall.customersInformed = dto.customersInformed
            recall.authorityInformed = dto.authorityInformed
            recall.authorityInformedAt = dto.authorityInformedAt
            recall.closedAt = dto.closedAt
            context.insert(recall)
        }
    }

    private static func restoreAnalyses(_ items: [LabAnalysisDTO], into context: ModelContext) {
        for dto in items {
            let analysis = LabAnalysis(
                sampleName: dto.sampleName,
                kind: AnalysisKind(rawValue: dto.kindRawValue) ?? .other,
                location: dto.location,
                sampledAt: dto.sampledAt,
                laboratory: dto.laboratory,
                reportReference: dto.reportReference,
                result: AnalysisResult(rawValue: dto.resultRawValue) ?? .pending,
                resultReceivedAt: dto.resultReceivedAt,
                findings: dto.findings,
                correctiveAction: dto.correctiveAction,
                reportData: dto.reportData,
                nextDueDate: dto.nextDueDate,
                operatorName: dto.operatorName,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(analysis)
        }
    }

    private static func restoreWaterControls(_ items: [WaterControlDTO], into context: ModelContext) {
        for dto in items {
            let control = WaterControl(
                kind: WaterCheckKind(rawValue: dto.kindRawValue) ?? .other,
                location: dto.location,
                performedAt: dto.performedAt,
                measuredValue: dto.measuredValue,
                isPrivateSupply: dto.isPrivateSupply,
                isCompliant: dto.isCompliant,
                correctiveAction: dto.correctiveAction,
                nextDueDate: dto.nextDueDate,
                documentData: dto.documentData,
                operatorName: dto.operatorName,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(control)
        }
    }

    private static func restoreOilCollections(_ items: [WasteOilDTO], into context: ModelContext) {
        for dto in items {
            let collection = WasteOilCollection(
                collectedAt: dto.collectedAt,
                collector: dto.collector,
                collectorApproval: dto.collectorApproval,
                documentReference: dto.documentReference,
                quantity: dto.quantity,
                unit: WasteOilUnit(rawValue: dto.unitRawValue) ?? .litres,
                containerCount: dto.containerCount,
                documentData: dto.documentData,
                operatorName: dto.operatorName,
                notes: dto.notes,
                createdAt: dto.createdAt
            )
            context.insert(collection)
        }
    }

    private static func restoreSeals(_ items: [IntegritySealDTO], into context: ModelContext) {
        for dto in items {
            let seal = IntegritySeal(
                periodStart: dto.periodStart,
                sealedAt: dto.sealedAt,
                digest: dto.digest,
                previousDigest: dto.previousDigest,
                recordCount: dto.recordCount,
                sequence: dto.sequence,
                sealedBy: dto.sealedBy,
                createdAt: dto.createdAt
            )
            context.insert(seal)
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
        try delete(ThawingRecord.self, in: context)
        try delete(FoodSample.self, in: context)
        try delete(SanitizingFreezeRecord.self, in: context)
        try delete(BeefOriginRecord.self, in: context)
        try delete(ShiftHygieneCheck.self, in: context)
        try delete(MedicalFitnessRecord.self, in: context)
        try delete(CleaningProduct.self, in: context)
        try delete(RegulatoryDocument.self, in: context)
        try delete(EquipmentMaintenance.self, in: context)
        try delete(ProductRecall.self, in: context)
        try delete(LabAnalysis.self, in: context)
        try delete(WaterControl.self, in: context)
        try delete(WasteOilCollection.self, in: context)
        try delete(IntegritySeal.self, in: context)
        try delete(Establishment.self, in: context)

        try context.save()
    }

    private static func delete<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}
