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
    case thermal
    case oil
    case pest
    case training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperatures: "Relevés de température"
        case .products:     "Produits entamés"
        case .deliveries:   "Contrôles à réception"
        case .cleaning:     "Plan de nettoyage"
        case .thermal:      "Refroidissement et remise en température"
        case .oil:          "Bains de friture"
        case .pest:         "Lutte contre les nuisibles"
        case .training:     "Formations"
        }
    }

    var systemImage: String {
        switch self {
        case .temperatures: "thermometer.medium"
        case .products:     "shippingbox"
        case .deliveries:   "truck.box"
        case .cleaning:     "sparkles"
        case .thermal:      "thermometer.variable"
        case .oil:          "drop.triangle"
        case .pest:         "ant"
        case .training:     "graduationcap"
        }
    }

    var fileName: String {
        switch self {
        case .temperatures: "temperatures"
        case .products:     "produits"
        case .deliveries:   "receptions"
        case .cleaning:     "nettoyage"
        case .thermal:      "process-thermiques"
        case .oil:          "huiles"
        case .pest:         "nuisibles"
        case .training:     "formations"
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
        case .thermal:      thermal(report)
        case .oil:          oil(report)
        case .pest:         pest(report)
        case .training:     training(report)
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
                product.supplierExpiryDate.map { AppFormatters.shortDate($0) } ?? "",
                AppFormatters.shortDate(product.effectiveLimitDate),
                product.status.label,
                product.closedAt.map { AppFormatters.shortDate($0) } ?? "",
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
                delivery.temperature.map { decimal($0) } ?? "",
                delivery.temperatureLimit.map { decimal($0) } ?? "",
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

    private static func thermal(_ report: MonthlyReport) -> String {
        var rows = [["Produit", "Lot", "Opération", "Départ", "Heure début",
                     "Température départ (°C)", "Heure fin", "Température fin (°C)",
                     "Durée (min)", "Limite (min)", "Conforme", "Action corrective",
                     "Opérateur"]]

        for record in report.thermalInPeriod {
            rows.append([
                record.productName,
                record.batchNumber,
                record.kind.label,
                AppFormatters.shortDate(record.startedAt),
                AppFormatters.time(record.startedAt),
                decimal(record.startTemperature),
                record.finishedAt.map { AppFormatters.time($0) } ?? "",
                record.endTemperature.map { decimal($0) } ?? "",
                record.isFinished ? "\(Int(record.duration() / 60))" : "",
                "\(Int(record.maximumDurationSeconds / 60))",
                record.isFinished ? (record.isCompliant ? "Oui" : "Non") : "En cours",
                record.correctiveAction,
                record.operatorName
            ])
        }
        return assemble(rows)
    }

    private static func oil(_ report: MonthlyReport) -> String {
        var rows = [["Date", "Friteuse", "Composés polaires (%)", "Seuil (%)",
                     "Aspect", "Suite donnée", "Conforme", "Opérateur", "Commentaire"]]

        for check in report.oilChecksInPeriod {
            rows.append([
                AppFormatters.shortDate(check.checkedAt),
                check.fryerName,
                check.polarCompounds.map { decimal($0) } ?? "",
                decimal(check.polarCompoundsLimit),
                check.appearance.label,
                check.action.label,
                check.isCompliant ? "Oui" : "Non",
                check.operatorName,
                check.comment
            ])
        }
        return assemble(rows)
    }

    private static func pest(_ report: MonthlyReport) -> String {
        var rows = [["Date", "Prestataire", "Technicien", "Présence constatée",
                     "Constat", "Appâts remplacés", "Postes", "Mesures prises",
                     "Prochaine visite"]]

        for visit in report.pestVisitsInPeriod {
            rows.append([
                AppFormatters.shortDate(visit.visitedAt),
                visit.company,
                visit.technician,
                visit.hasInfestation ? "Oui" : "Non",
                visit.findings,
                visit.baitsReplaced ? "Oui" : "Non",
                "\(visit.deviceCount)",
                visit.actionsTaken,
                visit.nextVisitDate.map { AppFormatters.shortDate($0) } ?? ""
            ])
        }
        return assemble(rows)
    }

    private static func training(_ report: MonthlyReport) -> String {
        var rows = [["Personne", "Formation", "Organisme", "Suivie le",
                     "Échéance", "Attestation jointe", "Notes"]]

        for training in report.validTrainings {
            rows.append([
                training.personName,
                training.title,
                training.organisation,
                AppFormatters.shortDate(training.completedAt),
                training.expiresAt.map { AppFormatters.shortDate($0) } ?? "",
                training.hasCertificate ? "Oui" : "Non",
                training.notes
            ])
        }
        return assemble(rows)
    }

    // MARK: - Fabrication du fichier

    private static func assemble(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { escape($0) }.joined(separator: separator)
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

        // Un CSV est un fichier texte : il ne peut pas contenir d'image. Son
        // identité passe donc par son nom de fichier.
        let establishment = report.establishment?.name
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        var components = [register.fileName]
        if let establishment, !establishment.isEmpty { components.append(establishment) }
        components.append(slug)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(components.joined(separator: "-") + ".csv")

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        try data.write(to: url, options: .atomic)
        return url
    }
}
