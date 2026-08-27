//
//  PDFReportService.swift
//  HACCPPocket
//
//  Génération du registre mensuel au format PDF : le document que le
//  restaurateur présente lors d'un contrôle. Rendu entièrement sur l'appareil
//  avec UIGraphicsPDFRenderer, aucun service distant.
//

import Foundation
import UIKit

// MARK: - Données du rapport

/// Regroupe tout ce qui doit figurer sur le registre d'un mois donné et calcule
/// les statistiques de synthèse. Séparé du rendu pour rester testable.
struct MonthlyReport {

    let month: Date
    let establishment: Establishment?
    let equipments: [Equipment]
    let products: [TrackedProduct]
    let deliveries: [DeliveryCheck]
    let cleaningTasks: [CleaningTask]
    let thermalRecords: [ThermalProcessRecord]
    let oilChecks: [OilCheckRecord]
    let pestVisits: [PestControlVisit]
    let trainings: [StaffTraining]
    let dishes: [Dish]
    let medicalRecords: [MedicalFitnessRecord]
    let calendar: Calendar

    init(
        month: Date,
        establishment: Establishment?,
        equipments: [Equipment],
        products: [TrackedProduct],
        deliveries: [DeliveryCheck],
        cleaningTasks: [CleaningTask],
        thermalRecords: [ThermalProcessRecord] = [],
        oilChecks: [OilCheckRecord] = [],
        pestVisits: [PestControlVisit] = [],
        trainings: [StaffTraining] = [],
        dishes: [Dish] = [],
        medicalRecords: [MedicalFitnessRecord] = [],
        calendar: Calendar = .current
    ) {
        self.month = month
        self.establishment = establishment
        self.equipments = equipments
        self.products = products
        self.deliveries = deliveries
        self.cleaningTasks = cleaningTasks
        self.thermalRecords = thermalRecords
        self.oilChecks = oilChecks
        self.pestVisits = pestVisits
        self.trainings = trainings
        self.dishes = dishes
        self.medicalRecords = medicalRecords
        self.calendar = calendar
    }

    /// La carte, dans l'ordre où elle se lit : entrées, plats, desserts.
    var dishesInMenuOrder: [Dish] {
        dishes.sorted { left, right in
            if left.category.sortWeight != right.category.sortWeight {
                return left.category.sortWeight < right.category.sortWeight
            }
            if left.sortIndex != right.sortIndex {
                return left.sortIndex < right.sortIndex
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    /// Bornes du mois, du 1er à 00:00 au dernier jour à 23:59.
    var interval: DateInterval {
        calendar.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 0)
    }

    var title: String {
        AppFormatters.sentenceCased(AppFormatters.monthTitle(month))
    }

    private func isInPeriod(_ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    // MARK: Températures

    /// Relevés du mois, groupés par équipement et triés chronologiquement.
    var readingsByEquipment: [(equipment: Equipment, readings: [TemperatureReading])] {
        equipments.compactMap { equipment in
            let readings = equipment.readings
                .filter { isInPeriod($0.recordedAt) }
                .sorted { $0.recordedAt < $1.recordedAt }
            return readings.isEmpty ? nil : (equipment, readings)
        }
    }

    var allReadings: [TemperatureReading] {
        readingsByEquipment.flatMap(\.readings)
    }

    var nonCompliantReadings: [TemperatureReading] {
        allReadings.filter { !$0.isCompliant }.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// `nil` si aucun relevé sur la période.
    var complianceRate: Double? {
        guard !allReadings.isEmpty else { return nil }
        return Double(allReadings.filter(\.isCompliant).count) / Double(allReadings.count)
    }

    // MARK: Suivi médical

    /// L'état du suivi médical, personne par personne.
    ///
    /// ⚠️ Ce que cette structure porte est volontairement pauvre : un prénom,
    /// et une visite faite ou non. L'avis d'aptitude, les restrictions et le
    /// document du service de santé n'y figurent pas et ne doivent pas y
    /// figurer — ils relèvent du suivi médical du salarié, pas du registre
    /// sanitaire de l'établissement.
    struct MedicalMention {
        let firstName: String
        let done: Bool
        let mention: String
    }

    var medicalMentions: [MedicalMention] {
        var grouped: [String: [MedicalFitnessRecord]] = [:]

        for record in medicalRecords {
            grouped[record.personKey, default: []].append(record)
        }

        var mentions: [MedicalMention] = []

        for (_, visits) in grouped {
            let sorted = visits.sorted { $0.examinedAt > $1.examinedAt }
            guard let reference = sorted.first else { continue }

            let inPeriod = sorted.first { isInPeriod($0.examinedAt) }

            mentions.append(
                MedicalMention(
                    firstName: reference.firstName,
                    done: inPeriod != nil,
                    mention: inPeriod.map { "Visite effectuée le \(AppFormatters.shortDate($0.examinedAt))" }
                        ?? "Aucune visite sur la période"
                )
            )
        }

        return mentions.sorted {
            $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending
        }
    }

    // MARK: Autres registres

    var productsInPeriod: [TrackedProduct] {
        products
            .filter { isInPeriod($0.openedAt) || $0.closedAt.map { isInPeriod($0) } == true }
            .sorted { $0.openedAt < $1.openedAt }
    }

    var deliveriesInPeriod: [DeliveryCheck] {
        deliveries
            .filter { isInPeriod($0.receivedAt) }
            .sorted { $0.receivedAt < $1.receivedAt }
    }

    var cleaningRecordsByTask: [(task: CleaningTask, records: [CleaningRecord])] {
        cleaningTasks.compactMap { task in
            let records = task.records(from: interval.start, to: interval.end)
            return records.isEmpty ? nil : (task, records.sorted { $0.completedAt < $1.completedAt })
        }
    }

    /// Écarts non documentés : le point le plus scruté lors d'un contrôle.
    var undocumentedDeviations: [TemperatureReading] {
        nonCompliantReadings.filter(\.needsCorrectiveAction)
    }

    // MARK: Registres périodiques

    var thermalInPeriod: [ThermalProcessRecord] {
        thermalRecords
            .filter { isInPeriod($0.startedAt) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var oilChecksInPeriod: [OilCheckRecord] {
        oilChecks
            .filter { isInPeriod($0.checkedAt) }
            .sorted { $0.checkedAt < $1.checkedAt }
    }

    var pestVisitsInPeriod: [PestControlVisit] {
        pestVisits
            .filter { isInPeriod($0.visitedAt) }
            .sorted { $0.visitedAt < $1.visitedAt }
    }

    /// Les formations ne sont pas des événements du mois mais un état : on
    /// joint l'ensemble des attestations valides, c'est ce que l'inspecteur
    /// demande à voir.
    var validTrainings: [StaffTraining] {
        trainings
            .filter { !$0.isExpired(at: interval.end) }
            .sorted { $0.completedAt > $1.completedAt }
    }

    var isEmpty: Bool {
        allReadings.isEmpty
            && productsInPeriod.isEmpty
            && deliveriesInPeriod.isEmpty
            && cleaningRecordsByTask.isEmpty
            && thermalInPeriod.isEmpty
            && oilChecksInPeriod.isEmpty
            && pestVisitsInPeriod.isEmpty
    }
}

// MARK: - Rendu

enum PDFReportService {

    private enum Layout {
        static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4
        static let margin: CGFloat = 40
        static var contentWidth: CGFloat { page.width - margin * 2 }
        static let footerHeight: CGFloat = 30
    }

    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 12, weight: .regular)
        static let section = UIFont.systemFont(ofSize: 14, weight: .semibold)
        static let tableHeader = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 9, weight: .regular)
        static let caption = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    /// Produit le PDF. `watermark` imprime un bandeau diagonal sur chaque page :
    /// c'est ce qui distingue l'export gratuit de l'export payant.
    static func generate(report: MonthlyReport, watermark: String? = nil) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)

        return renderer.pdfData { context in
            var y: CGFloat = 0
            var pageNumber = 0

            func startPage() {
                context.beginPage()
                pageNumber += 1
                y = Layout.margin
                if let watermark {
                    drawWatermark(watermark, in: context.cgContext)
                }
                drawFooter(page: pageNumber, in: context.cgContext)
            }

            /// Passe à la page suivante si le bloc à venir ne tient plus.
            func ensureSpace(_ height: CGFloat) {
                if y + height > Layout.page.height - Layout.margin - Layout.footerHeight {
                    startPage()
                }
            }

            func text(
                _ string: String,
                font: UIFont = Fonts.body,
                color: UIColor = .black,
                x: CGFloat = Layout.margin,
                width: CGFloat = Layout.contentWidth,
                spacingAfter: CGFloat = 4
            ) {
                let height = measure(string, font: font, width: width)
                ensureSpace(height)
                draw(string, font: font, color: color, rect: CGRect(x: x, y: y, width: width, height: height))
                y += height + spacingAfter
            }

            func sectionTitle(_ string: String) {
                ensureSpace(40)
                y += 8
                text(string, font: Fonts.section, spacingAfter: 2)
                context.cgContext.setStrokeColor(UIColor.darkGray.cgColor)
                context.cgContext.setLineWidth(0.7)
                context.cgContext.move(to: CGPoint(x: Layout.margin, y: y))
                context.cgContext.addLine(to: CGPoint(x: Layout.page.width - Layout.margin, y: y))
                context.cgContext.strokePath()
                y += 8
            }

            func row(_ cells: [String], widths: [CGFloat], font: UIFont = Fonts.body, color: UIColor = .black) {
                let height = zip(cells, widths)
                    .map { measure($0.0, font: font, width: $0.1) }
                    .max() ?? 12
                ensureSpace(height + 4)

                var x = Layout.margin
                for (cell, width) in zip(cells, widths) {
                    draw(cell, font: font, color: color, rect: CGRect(x: x, y: y, width: width, height: height))
                    x += width
                }
                y += height + 4
            }

            // ---- Page 1 : en-tête ----
            startPage()

            // Le logo occupe le coin supérieur droit ; l'en-tête textuel se
            // rétrécit d'autant pour ne pas passer dessous.
            let logoHeight = drawLogo(report.establishment?.logoData)
            let headerWidth = logoHeight > 0 ? Layout.contentWidth - 140 : Layout.contentWidth

            text("Registre sanitaire mensuel", font: Fonts.title, width: headerWidth, spacingAfter: 2)
            text(report.title, font: Fonts.subtitle, color: .darkGray, width: headerWidth, spacingAfter: 12)

            if let establishment = report.establishment {
                text(establishment.displayName, font: Fonts.section, width: headerWidth, spacingAfter: 2)
                if !establishment.address.isEmpty {
                    text(establishment.address, font: Fonts.body, color: .darkGray, width: headerWidth, spacingAfter: 2)
                }
                var identity: [String] = []
                if !establishment.siret.isEmpty { identity.append("SIRET \(establishment.siret)") }
                if !establishment.approvalNumber.isEmpty { identity.append("Agrément \(establishment.approvalNumber)") }
                if !establishment.managerName.isEmpty { identity.append("Responsable PMS : \(establishment.managerName)") }
                if !identity.isEmpty {
                    text(identity.joined(separator: " · "), font: Fonts.caption, color: .darkGray, width: headerWidth, spacingAfter: 4)
                }
            }

            // Ne jamais démarrer le corps du document au-dessus du logo.
            y = max(y, Layout.margin + logoHeight + 8)

            // ---- Synthèse ----
            sectionTitle("Synthèse de la période")

            let rate = report.complianceRate
            row(["Relevés de température", "\(report.allReadings.count)"], widths: [300, 200], font: Fonts.body)
            row(["Relevés non conformes", "\(report.nonCompliantReadings.count)"], widths: [300, 200])
            row([
                "Taux de conformité",
                rate.map { $0.formatted(.percent.precision(.fractionLength(1)).locale(AppFormatters.locale)) } ?? "—"
            ], widths: [300, 200])
            row(["Écarts sans action corrective", "\(report.undocumentedDeviations.count)"],
                widths: [300, 200],
                color: report.undocumentedDeviations.isEmpty ? .black : .systemRed)
            row(["Produits tracés", "\(report.productsInPeriod.count)"], widths: [300, 200])
            row(["Contrôles à réception", "\(report.deliveriesInPeriod.count)"], widths: [300, 200])
            row(["Opérations de nettoyage enregistrées",
                 "\(report.cleaningRecordsByTask.reduce(0) { $0 + $1.records.count })"],
                widths: [300, 200])
            row(["Refroidissements et remises en température",
                 "\(report.thermalInPeriod.count)"], widths: [300, 200])
            row(["Contrôles de bains de friture",
                 "\(report.oilChecksInPeriod.count)"], widths: [300, 200])
            row(["Visites de lutte contre les nuisibles",
                 "\(report.pestVisitsInPeriod.count)"], widths: [300, 200])
            row(["Attestations de formation valides",
                 "\(report.validTrainings.count)"],
                widths: [300, 200],
                color: report.validTrainings.isEmpty ? .systemRed : .black)

            // ---- Températures ----
            if report.readingsByEquipment.isEmpty {
                sectionTitle("Relevés de température")
                text("Aucun relevé enregistré sur la période.", color: .darkGray)
            } else {
                for entry in report.readingsByEquipment {
                    sectionTitle("Températures — \(entry.equipment.name)")
                    text("\(entry.equipment.type.label) · plage acceptée \(entry.equipment.formattedRange)",
                         font: Fonts.caption, color: .darkGray, spacingAfter: 6)

                    let widths: [CGFloat] = [70, 50, 55, 70, 270]
                    row(["Date", "Heure", "Moment", "Température", "Observation / action corrective"],
                        widths: widths, font: Fonts.tableHeader, color: .darkGray)

                    for reading in entry.readings {
                        let note = reading.isCompliant
                            ? reading.comment
                            : (reading.correctiveAction.isEmpty
                               ? "⚠ Écart non documenté"
                               : reading.correctiveAction)
                        row([
                            AppFormatters.shortDate(reading.recordedAt),
                            AppFormatters.time(reading.recordedAt),
                            reading.moment.label,
                            reading.formattedValue,
                            note
                        ], widths: widths, color: reading.isCompliant ? .black : .systemRed)
                    }
                }
            }

            // ---- Produits ----
            sectionTitle("Produits entamés")
            if report.productsInPeriod.isEmpty {
                text("Aucun produit tracé sur la période.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [140, 70, 65, 65, 175]
                row(["Produit", "Lot", "Ouvert le", "À retirer le", "Statut"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)
                for product in report.productsInPeriod {
                    var status = product.status.label
                    if product.status == .discarded, !product.discardReason.isEmpty {
                        status += " — \(product.discardReason)"
                    }
                    row([
                        product.name,
                        product.batchNumber.isEmpty ? "—" : product.batchNumber,
                        AppFormatters.shortDate(product.openedAt),
                        AppFormatters.shortDate(product.effectiveLimitDate),
                        status
                    ], widths: widths)
                }
            }

            // ---- Réception ----
            sectionTitle("Contrôles à réception")
            if report.deliveriesInPeriod.isEmpty {
                text("Aucun contrôle enregistré sur la période.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [65, 110, 110, 60, 170]
                row(["Date", "Fournisseur", "Marchandise", "Temp.", "Décision / motif"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)
                for delivery in report.deliveriesInPeriod {
                    var decision = delivery.decision.label
                    if !delivery.reason.isEmpty { decision += " — \(delivery.reason)" }
                    row([
                        AppFormatters.shortDate(delivery.receivedAt),
                        delivery.supplierName,
                        delivery.productLabel.isEmpty ? "—" : delivery.productLabel,
                        delivery.formattedTemperature,
                        decision
                    ], widths: widths, color: delivery.isFullyCompliant ? .black : .systemRed)
                }
            }

            // ---- Nettoyage ----
            sectionTitle("Plan de nettoyage et de désinfection")
            if report.cleaningRecordsByTask.isEmpty {
                text("Aucune opération enregistrée sur la période.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [190, 70, 90, 165]
                row(["Opération", "Fréquence", "Réalisations", "Dates"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)
                for entry in report.cleaningRecordsByTask {
                    let dates = entry.records
                        .map { AppFormatters.shortDate($0.completedAt) }
                        .joined(separator: ", ")
                    row([
                        entry.task.title,
                        entry.task.frequency.label,
                        "\(entry.records.count)",
                        dates
                    ], widths: widths)
                }
            }

            // ---- Process thermiques ----
            sectionTitle("Refroidissements et remises en température")
            if report.thermalInPeriod.isEmpty {
                text("Aucune opération enregistrée sur la période.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [130, 80, 60, 55, 55, 135]
                row(["Produit", "Opération", "Date", "Durée", "Départ → fin", "Action corrective"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)

                for record in report.thermalInPeriod {
                    let arrival = record.endTemperature.map { AppFormatters.temperature($0) } ?? "en cours"
                    row([
                        record.productName,
                        record.kind.shortLabel,
                        AppFormatters.shortDate(record.startedAt),
                        record.formattedDuration(),
                        "\(AppFormatters.temperature(record.startTemperature)) → \(arrival)",
                        record.isCompliant ? record.comment : (record.correctiveAction.isEmpty ? "⚠ Écart non documenté" : record.correctiveAction)
                    ], widths: widths, color: record.isCompliant ? .black : .systemRed)
                }
            }

            // ---- Huiles ----
            sectionTitle("Bains de friture")
            if report.oilChecksInPeriod.isEmpty {
                text("Aucun contrôle enregistré sur la période.", color: .darkGray)
            } else {
                // La colonne dit « Résultat » et non « Composés polaires » :
                // une bandelette ne produit pas de pourcentage, et afficher
                // « Non mesuré » en face d'un contrôle réellement fait serait
                // faux devant un contrôleur.
                let widths: [CGFloat] = [66, 108, 96, 84, 66, 95]
                row(["Date", "Friteuse", "Résultat", "Méthode", "Aspect", "Suite donnée"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)

                for check in report.oilChecksInPeriod {
                    row([
                        AppFormatters.shortDate(check.checkedAt),
                        check.fryerName,
                        check.measurementLabel,
                        check.method.label,
                        check.appearance.label,
                        check.action.label
                    ], widths: widths, color: check.isCompliant ? .black : .systemRed)
                }
            }

            // ---- Suivi médical ----
            //
            // Une seule colonne au-delà du prénom, et c'est délibéré. Le
            // registre atteste que le suivi existe ; ce que le médecin a écrit
            // ne le regarde pas, et l'imprimer ici le rendrait consultable par
            // quiconque tient le document.
            sectionTitle("Suivi médical")
            if report.medicalMentions.isEmpty {
                text("Aucun suivi enregistré.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [150, 365]
                row(["Personne", "Visite médicale"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)

                for mention in report.medicalMentions {
                    row([
                        mention.firstName,
                        mention.mention
                    ], widths: widths, color: mention.done ? .black : .darkGray)
                }

                text(
                    "Le contenu des avis d'aptitude relève du suivi médical des personnes et ne figure pas dans ce registre. Il est communiqué sur demande explicite.",
                    color: .darkGray
                )
            }

            // ---- Nuisibles ----
            sectionTitle("Lutte contre les nuisibles")
            if report.pestVisitsInPeriod.isEmpty {
                text("Aucune visite enregistrée sur la période.", color: .darkGray)
            } else {
                let widths: [CGFloat] = [70, 120, 90, 235]
                row(["Date", "Prestataire", "Constat", "Mesures prises"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)

                for visit in report.pestVisitsInPeriod {
                    row([
                        AppFormatters.shortDate(visit.visitedAt),
                        visit.company,
                        visit.statusLabel,
                        visit.actionsTaken.isEmpty ? visit.findings : visit.actionsTaken
                    ], widths: widths, color: visit.hasInfestation ? .systemRed : .black)
                }
            }

            // ---- Formations ----
            sectionTitle("Formations à l'hygiène alimentaire")
            if report.validTrainings.isEmpty {
                text("Aucune attestation enregistrée.", color: .systemRed)
            } else {
                let widths: [CGFloat] = [140, 150, 110, 115]
                row(["Personne", "Formation", "Organisme", "Suivie le"],
                    widths: widths, font: Fonts.tableHeader, color: .darkGray)

                for training in report.validTrainings {
                    row([
                        training.personName,
                        training.title,
                        training.organisation,
                        AppFormatters.shortDate(training.completedAt)
                    ], widths: widths)
                }
            }

            // ---- Attestation ----
            sectionTitle("Attestation")
            text(
                "Je soussigné(e) \(report.establishment?.managerName ?? "……………………"), responsable du plan de maîtrise sanitaire, certifie l'exactitude des enregistrements figurant dans le présent registre.",
                color: .darkGray,
                spacingAfter: 24
            )
            row(["Date : ……………………", "Signature :"], widths: [200, 300], color: .darkGray)
        }
    }

    /// Écrit le PDF dans un fichier temporaire et renvoie son URL, prête pour
    /// `ShareLink`. Le nom du fichier est celui que verra l'inspecteur.
    static func writeToTemporaryFile(data: Data, report: MonthlyReport) throws -> URL {
        let slug = report.title
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let name = "registre-sanitaire-\(slug).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Primitives de dessin

    private static func measure(_ string: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !string.isEmpty else { return font.lineHeight }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let bounds = attributed.boundingRect(
            with: CGSize(width: width - 6, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }

    private static func draw(_ string: String, font: UIFont, color: UIColor, rect: CGRect) {
        guard !string.isEmpty else { return }
        let attributed = NSAttributedString(
            string: string,
            attributes: [.font: font, .foregroundColor: color]
        )
        attributed.draw(
            with: CGRect(x: rect.minX, y: rect.minY, width: rect.width - 6, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }

    /// Dessine le logo en haut à droite et renvoie la hauteur occupée
    /// (0 s'il n'y a pas de logo).
    @discardableResult
    private static func drawLogo(_ data: Data?) -> CGFloat {
        guard let data, let image = UIImage(data: data) else { return 0 }

        let maxSize = CGSize(width: 130, height: 60)
        let ratio = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        image.draw(in: CGRect(
            x: Layout.page.width - Layout.margin - size.width,
            y: Layout.margin,
            width: size.width,
            height: size.height
        ))
        return size.height
    }

    private static func drawFooter(page: Int, in context: CGContext) {
        let baseline = Layout.page.height - Layout.margin
        var textOrigin = Layout.margin

        // Le logo de l'application signe le document : il identifie l'outil qui
        // l'a produit, là où le logo en en-tête identifie l'établissement.
        let logoSide: CGFloat = 12
        if let logo = BrandAssets.tintedLogo(.gray, size: CGSize(width: logoSide, height: logoSide)) {
            logo.draw(in: CGRect(x: Layout.margin, y: baseline, width: logoSide, height: logoSide))
            textOrigin += logoSide + 5
        }

        let footer = "\(BrandAssets.productName) · document généré le \(AppFormatters.dateAndTime(.now)) · page \(page)"
        let attributed = NSAttributedString(
            string: footer,
            attributes: [.font: Fonts.caption, .foregroundColor: UIColor.gray]
        )
        attributed.draw(
            in: CGRect(
                x: textOrigin,
                y: baseline + 1,
                width: Layout.page.width - textOrigin - Layout.margin,
                height: 14
            )
        )
    }

    private static func drawWatermark(_ text: String, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: Layout.page.width / 2, y: Layout.page.height / 2)
        context.rotate(by: -.pi / 5)

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 46, weight: .heavy),
                .foregroundColor: UIColor.systemRed.withAlphaComponent(0.14)
            ]
        )
        let size = attributed.size()
        attributed.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))

        context.restoreGState()
    }
}
