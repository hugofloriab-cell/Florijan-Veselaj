//
//  CSVExportService.swift
//  HACCPPocket
//
//  Export des registres en CSV, pour ouverture dans un tableur ou transmission
//  au comptable. Complète le PDF, qui lui sert de preuve à présenter.
//

import Foundation

enum CSVRegister: String, CaseIterable, Identifiable {
    case temperatures
    case products
    case deliveries
    case cleaning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperatures: "Relevés de température"
        case .products:     "Produits entamés"
        case .deliveries:   "Contrôles à réception"
        case .cleaning:     "Plan de nettoyage"
        }
    }

    var systemImage: String {
        switch self {
        case .temperatures: "thermometer.medium"
        case .products:     "shippingbox"
        case .deliveries:   "truck.box"
        case .cleaning:     "sparkles"
        }
    }

    var fileName: String {
        switch self {
        case .temperatures: "temperatures"
        case .products:     "produits"
        case .deliveries:   "receptions"
        case .cleaning:     "nettoyage"
        }
    }
}

enum CSVExportService {

    /// Point-virgule : c'est le séparateur qu'attend Excel en configuration
    /// française, où la virgule est déjà le séparateur décimal.
    private static let separator = ";"

    static func makeCSV(_ register: CSVRegister, report: MonthlyReport) -> String {
        switch register {
        case .temperatures: temperatures(report)
        case .products:     products(report)
        case .deliveries:   deliveries(report)
        case .cleaning:     cleaning(report)
        }
    }

    // MARK: - Registres

    private static func temperatures(_ report: MonthlyReport) -> String {
        var rows = [["Équipement", "Type", "Date", "Heure", "Moment", "Température (°C)",
                     "Seuil min", "Seuil max", "Conforme", "Action corrective",
                     "Commentaire", "Opérateur"]]

        for entry in report.readingsByEquipment {
            for reading in entry.readings {
                rows.append([
                    entry.equipment.name,
                    entry.equipment.type.label,
                    AppFormatters.shortDate(reading.recordedAt),
                    AppFormatters.time(reading.recordedAt),
                    reading.moment.label,
                    decimal(reading.value),
                    decimal(reading.appliedRange.lowerBound),
                    decimal(reading.appliedRange.upperBound),
                    reading.isCompliant ? "Oui" : "Non",
                    reading.correctiveAction,
                    reading.comment,
                    reading.operatorName
                ])
            }
        }
        return assemble(rows)
    }

    private static func products(_ report: MonthlyReport) -> String {
        var rows = [["Produit", "Lot", "Code-barres", "Fournisseur", "Zone",
                     "Ouvert le", "DLC fournisseur", "À retirer le", "Statut",
                     "Clôturé le", "Motif de rebut"]]

        for product in report.productsInPeriod {
            rows.append([
                product.name,
                product.batchNumber,
                product.barcode,
                product.supplier,
                product.storage.label,
                AppFormatters.shortDate(product.openedAt),
                product.supplierExpiryDate.map(AppFormatters.shortDate) ?? "",
                AppFormatters.shortDate(product.effectiveLimitDate),
                product.status.label,
                product.closedAt.map(AppFormatters.shortDate) ?? "",
                product.discardReason
            ])
        }
        return assemble(rows)
    }

    private static func deliveries(_ report: MonthlyReport) -> String {
        var rows = [["Date", "Fournisseur", "Marchandise", "Lot", "Température (°C)",
                     "Seuil (°C)", "Emballage intact", "Étiquetage conforme",
                     "Décision", "Motif", "Opérateur"]]

        for delivery in report.deliveriesInPeriod {
            rows.append([
                AppFormatters.shortDate(delivery.receivedAt),
                delivery.supplierName,
                delivery.productLabel,
                delivery.batchNumber,
                delivery.temperature.map(decimal) ?? "",
                delivery.temperatureLimit.map(decimal) ?? "",
                delivery.packagingIntact ? "Oui" : "Non",
                delivery.labellingCompliant ? "Oui" : "Non",
                delivery.decision.label,
                delivery.reason,
                delivery.operatorName
            ])
        }
        return assemble(rows)
    }

    private static func cleaning(_ report: MonthlyReport) -> String {
        var rows = [["Opération", "Zone", "Fréquence", "Produit utilisé",
                     "Date", "Heure", "Opérateur", "Commentaire"]]

        for entry in report.cleaningRecordsByTask {
            for record in entry.records {
                rows.append([
                    entry.task.title,
                    entry.task.zone,
                    entry.task.frequency.label,
                    record.productUsed,
                    AppFormatters.shortDate(record.completedAt),
                    AppFormatters.time(record.completedAt),
                    record.operatorName,
                    record.comment
                ])
            }
        }
        return assemble(rows)
    }

    // MARK: - Fabrication du fichier

    private static func assemble(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: separator)
        }
        .joined(separator: "\r\n")
    }

    /// Guillemets autour de toute valeur contenant un séparateur, un saut de
    /// ligne ou un guillemet, qui est alors doublé — la règle du RFC 4180.
    private static func escape(_ value: String) -> String {
        guard value.contains(separator)
                || value.contains("\"")
                || value.contains("\n")
                || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(AppFormatters.locale))
    }

    /// Écrit le fichier avec une marque d'ordre d'octets : sans elle, Excel
    /// affiche « Ã© » à la place des accents.
    static func writeToTemporaryFile(
        _ csv: String,
        register: CSVRegister,
        report: MonthlyReport
    ) throws -> URL {
        let slug = report.title
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(register.fileName)-\(slug).csv")

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        try data.write(to: url, options: .atomic)
        return url
    }
}
