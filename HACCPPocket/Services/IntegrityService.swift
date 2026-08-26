//
//  IntegrityService.swift
//  HACCPPocket
//
//  Calcul et vérification des empreintes de registres.
//
//  L'empreinte se calcule sur une représentation canonique : une ligne par
//  enregistrement, avec ses champs qui comptent, triées par ordre
//  alphabétique. Le tri est indispensable — SwiftData ne garantit pas l'ordre
//  de lecture, et une empreinte qui changerait selon l'ordre de récupération
//  ne vaudrait rien.
//

import Foundation
import CryptoKit
import SwiftData

// MARK: - Résultat d'un calcul

struct IntegrityDigest: Sendable, Equatable {
    let digest: String
    let recordCount: Int
}

// MARK: - Résultat d'une vérification

enum IntegrityVerdict: Sendable, Equatable {
    /// L'empreinte recalculée correspond au scellé.
    case intact
    /// Les enregistrements ont changé depuis le scellement.
    case altered(expectedCount: Int, actualCount: Int)
    /// La chaîne des scellés est rompue : un scellé manque, ou son
    /// prédécesseur a été supprimé.
    case brokenChain

    var title: String {
        switch self {
        case .intact:      "Conforme au scellé"
        case .altered:     "Enregistrements modifiés"
        case .brokenChain: "Chaîne rompue"
        }
    }

    var detail: String {
        switch self {
        case .intact:
            "Aucun enregistrement de cette période n'a été modifié depuis la clôture."
        case .altered(let expected, let actual):
            if expected == actual {
                return "Le nombre d'enregistrements n'a pas changé, mais leur contenu si. Une ou plusieurs valeurs ont été corrigées après la clôture."
            }
            return "Le scellé couvrait \(expected) enregistrement(s), il en reste \(actual). Des lignes ont été ajoutées ou supprimées après la clôture."
        case .brokenChain:
            "Le scellé du mois précédent est absent ou ne correspond pas. La suite des clôtures n'est plus continue."
        }
    }

    var isIntact: Bool { self == .intact }
}

// MARK: - Service

@MainActor
enum IntegrityService {

    // MARK: Empreinte

    /// Calcule l'empreinte des enregistrements d'un mois.
    static func digest(
        forMonthContaining date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> IntegrityDigest {

        let bounds = monthBounds(containing: date, calendar: calendar)
        var lines: [String] = []

        // Une ligne par enregistrement, préfixée par le registre d'origine.
        // Seuls les champs qui engagent l'établissement entrent dans le
        // calcul : un commentaire corrigé doit casser l'empreinte au même
        // titre qu'une température.

        for reading in try context.fetch(FetchDescriptor<TemperatureReading>())
        where bounds.contains(reading.recordedAt) {
            lines.append(join([
                "TEMP",
                stamp(reading.recordedAt),
                reading.equipment?.name ?? "",
                number(reading.value),
                reading.momentRawValue,
                reading.isCompliant ? "1" : "0",
                reading.correctiveAction,
                reading.comment,
                reading.operatorName
            ]))
        }

        for product in try context.fetch(FetchDescriptor<TrackedProduct>())
        where bounds.contains(product.openedAt) {
            lines.append(join([
                "PROD",
                stamp(product.openedAt),
                product.name,
                product.batchNumber,
                stamp(product.secondaryLimitDate),
                product.statusRawValue,
                product.discardReason
            ]))
        }

        for delivery in try context.fetch(FetchDescriptor<DeliveryCheck>())
        where bounds.contains(delivery.receivedAt) {
            lines.append(join([
                "RECEP",
                stamp(delivery.receivedAt),
                delivery.supplierName,
                delivery.productLabel,
                delivery.batchNumber,
                delivery.temperature.map { number($0) } ?? "",
                delivery.decisionRawValue,
                delivery.reason,
                delivery.operatorName
            ]))
        }

        for record in try context.fetch(FetchDescriptor<CleaningRecord>())
        where bounds.contains(record.completedAt) {
            lines.append(join([
                "NETT",
                stamp(record.completedAt),
                record.taskTitle,
                record.productUsed,
                record.comment,
                record.operatorName
            ]))
        }

        for record in try context.fetch(FetchDescriptor<ThermalProcessRecord>())
        where bounds.contains(record.startedAt) {
            lines.append(join([
                "THERM",
                stamp(record.startedAt),
                record.kindRawValue,
                record.productName,
                number(record.startTemperature),
                record.endTemperature.map { number($0) } ?? "",
                record.finishedAt.map { stamp($0) } ?? "",
                record.isCompliant ? "1" : "0",
                record.correctiveAction
            ]))
        }

        for check in try context.fetch(FetchDescriptor<OilCheckRecord>())
        where bounds.contains(check.checkedAt) {
            lines.append(join([
                "HUILE",
                stamp(check.checkedAt),
                check.fryerName,
                check.polarCompounds.map { number($0) } ?? "",
                check.actionRawValue,
                check.isCompliant ? "1" : "0"
            ]))
        }

        for record in try context.fetch(FetchDescriptor<ThawingRecord>())
        where bounds.contains(record.startedAt) {
            lines.append(join([
                "DECONG",
                stamp(record.startedAt),
                record.productName,
                record.batchNumber,
                record.methodRawValue,
                String(record.shelfLifeDays)
            ]))
        }

        for record in try context.fetch(FetchDescriptor<SanitizingFreezeRecord>())
        where bounds.contains(record.startedAt) {
            lines.append(join([
                "ASSAIN",
                stamp(record.startedAt),
                record.productName,
                record.batchNumber,
                record.scheduleRawValue,
                record.coreTemperature.map { number($0) } ?? "",
                record.isCompliant ? "1" : "0"
            ]))
        }

        for sample in try context.fetch(FetchDescriptor<FoodSample>())
        where bounds.contains(sample.collectedAt) {
            lines.append(join([
                "TEMOIN",
                stamp(sample.collectedAt),
                sample.dishName,
                String(sample.quantityGrams),
                sample.discardedAt.map { stamp($0) } ?? ""
            ]))
        }

        for check in try context.fetch(FetchDescriptor<ShiftHygieneCheck>())
        where bounds.contains(check.checkedAt) {
            lines.append(join([
                "POSTE",
                stamp(check.checkedAt),
                check.personName,
                check.passedRawValues.joined(separator: ","),
                check.failedRawValues.joined(separator: ","),
                check.correctiveAction
            ]))
        }

        for analysis in try context.fetch(FetchDescriptor<LabAnalysis>())
        where bounds.contains(analysis.sampledAt) {
            lines.append(join([
                "ANALYSE",
                stamp(analysis.sampledAt),
                analysis.sampleName,
                analysis.resultRawValue,
                analysis.findings,
                analysis.correctiveAction
            ]))
        }

        for recall in try context.fetch(FetchDescriptor<ProductRecall>())
        where bounds.contains(recall.noticedAt) {
            lines.append(join([
                "RAPPEL",
                stamp(recall.noticedAt),
                recall.productName,
                recall.affectedBatches,
                recall.scopeRawValue,
                recall.outcomeRawValue
            ]))
        }

        // Le tri rend l'empreinte indépendante de l'ordre de lecture.
        lines.sort()

        let canonical = lines.joined(separator: "\n")
        return IntegrityDigest(digest: sha256(canonical), recordCount: lines.count)
    }

    // MARK: Scellement

    /// Scelle le mois indiqué et renvoie le scellé créé.
    ///
    /// Un mois déjà scellé l'est de nouveau : le premier scellé n'est pas
    /// effacé, et la succession de deux scellés pour un même mois est en
    /// elle-même une information.
    @discardableResult
    static func seal(
        monthContaining date: Date,
        in context: ModelContext,
        sealedBy: String = "",
        calendar: Calendar = .current
    ) throws -> IntegritySeal {

        let computed = try digest(forMonthContaining: date, in: context, calendar: calendar)
        let existing = try context.fetch(FetchDescriptor<IntegritySeal>())
            .sorted { $0.sequence < $1.sequence }

        let seal = IntegritySeal(
            periodStart: monthBounds(containing: date, calendar: calendar).lowerBound,
            sealedAt: .now,
            digest: computed.digest,
            previousDigest: existing.last?.digest ?? "",
            recordCount: computed.recordCount,
            sequence: (existing.last?.sequence ?? 0) + 1,
            sealedBy: sealedBy
        )

        context.insert(seal)
        try context.save()
        return seal
    }

    // MARK: Vérification

    /// Recalcule l'empreinte du mois scellé et la compare.
    static func verify(
        _ seal: IntegritySeal,
        in context: ModelContext,
        allSeals: [IntegritySeal],
        calendar: Calendar = .current
    ) throws -> IntegrityVerdict {

        // La chaîne d'abord : un scellé dont le prédécesseur a disparu ne
        // peut plus être replacé dans une suite.
        if seal.sequence > 1 {
            let predecessor = allSeals.first { $0.sequence == seal.sequence - 1 }
            guard let predecessor, predecessor.digest == seal.previousDigest else {
                return .brokenChain
            }
        }

        let computed = try digest(
            forMonthContaining: seal.periodStart,
            in: context,
            calendar: calendar
        )

        guard computed.digest == seal.digest else {
            return .altered(expectedCount: seal.recordCount, actualCount: computed.recordCount)
        }

        return .intact
    }

    // MARK: - Outils

    private static func monthBounds(containing date: Date, calendar: Calendar) -> Range<Date> {
        let start = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return start..<end
    }

    /// Séparateur improbable dans une saisie de cuisine, pour qu'un champ
    /// contenant un point-virgule ne puisse pas imiter deux champs.
    private static func join(_ fields: [String]) -> String {
        fields.map { $0.replacingOccurrences(of: "\u{1F}", with: " ") }
            .joined(separator: "\u{1F}")
    }

    /// Horodatage à la seconde, en temps universel : indépendant du fuseau et
    /// des réglages de l'appareil.
    private static func stamp(_ date: Date) -> String {
        String(format: "%.0f", date.timeIntervalSince1970)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
