//
//  MeatOriginSheetService.swift
//  HACCPPocket
//
//  Le document d'affichage de l'origine des viandes.
//
//  Il reprend la structure du formulaire papier que tiennent les
//  établissements — date, entreprise, liste des viandes avec leurs trois
//  pays, responsable, signature, mention réglementaire — mais il est rempli
//  par l'application au lieu d'être recopié à la main.
//
//  Deux différences assumées avec le formulaire d'origine :
//   • « Hôtel » devient « Entreprise », parce que l'application ne s'adresse
//     pas qu'à des hôtels ;
//   • le nombre de viandes n'est plus figé à quatre. Une carte qui en propose
//     dix doit pouvoir en afficher dix, et le document se pagine tout seul.
//
//  Les photos d'étiquettes ne figurent pas sur ce document : il est affiché
//  en salle, à la vue des clients. Elles restent dans le registre, où elles
//  servent de preuve.
//

import Foundation
import UIKit

// MARK: - Contenu

struct MeatOriginSheet {

    let entries: [BeefOriginRecord]
    let establishment: Establishment?
    /// Nom porté au bas du document, en face de la signature.
    let responsibleName: String
    let generatedAt: Date

    init(
        entries: [BeefOriginRecord],
        establishment: Establishment?,
        responsibleName: String = "",
        generatedAt: Date = .now
    ) {
        self.entries = entries
        self.establishment = establishment
        self.responsibleName = responsibleName
        self.generatedAt = generatedAt
    }

    /// Les viandes à afficher, groupées par espèce puis par désignation.
    var orderedEntries: [BeefOriginRecord] {
        entries
            .filter(\.isOnMenu)
            .sorted { left, right in
                if left.species.sortWeight != right.species.sortWeight {
                    return left.species.sortWeight < right.species.sortWeight
                }
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
    }

    /// Viandes dont les trois pays ne sont pas tous renseignés : elles
    /// figurent au document, mais signalées, parce qu'un affichage incomplet
    /// vaut mieux qu'un affichage faux — et qu'il faut le voir.
    var incompleteEntries: [BeefOriginRecord] {
        orderedEntries.filter { !$0.isComplete }
    }

    var establishmentName: String {
        let name = establishment?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Entreprise non renseignée" : name
    }
}

// MARK: - Rendu

enum MeatOriginSheetService {

    private enum Layout {
        /// A4 portrait, comme le formulaire d'origine.
        static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        static let margin: CGFloat = 44
        static var contentWidth: CGFloat { page.width - margin * 2 }
        static let footerHeight: CGFloat = 116
    }

    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 21, weight: .bold)
        static let intro = UIFont.systemFont(ofSize: 12, weight: .regular)
        static let fieldLabel = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        static let fieldValue = UIFont.systemFont(ofSize: 11, weight: .medium)
        static let meatName = UIFont.systemFont(ofSize: 13, weight: .bold)
        static let species = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let legal = UIFont.systemFont(ofSize: 7.5, weight: .regular)
        static let caption = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    private static let brandColor = UIColor(red: 23 / 255, green: 80 / 255, blue: 127 / 255, alpha: 1)

    // MARK: Point d'entrée

    static func render(_ sheet: MeatOriginSheet) throws -> URL {
        let data = makePDF(sheet)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: sheet))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileName(for sheet: MeatOriginSheet) -> String {
        let slug = sheet.establishmentName
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        var parts = ["origine-viandes"]
        if !slug.isEmpty { parts.append(slug) }
        parts.append(AppFormatters.fileStamp(sheet.generatedAt))
        return parts.joined(separator: "-") + ".pdf"
    }

    // MARK: Dessin

    private static func makePDF(_ sheet: MeatOriginSheet) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)

        return renderer.pdfData { context in
            var y: CGFloat = 0
            let entries = sheet.orderedEntries

            func startPage(showsHeader: Bool) {
                context.beginPage()
                y = Layout.margin
                if showsHeader {
                    drawHeader(sheet, at: &y)
                } else {
                    drawContinuation(at: &y)
                }
            }

            func remaining() -> CGFloat {
                Layout.page.height - Layout.margin - Layout.footerHeight - y
            }

            startPage(showsHeader: true)

            if entries.isEmpty {
                drawEmptyNotice(at: &y)
            }

            for entry in entries {
                let height = entryHeight(entry)
                if remaining() < height {
                    drawFooter(sheet, in: context)
                    startPage(showsHeader: false)
                }
                drawEntry(entry, at: &y)
            }

            drawFooter(sheet, in: context)
        }
    }

    // MARK: En-tête

    private static func drawHeader(_ sheet: MeatOriginSheet, at y: inout CGFloat) {
        var textOrigin = Layout.margin
        let logoSide: CGFloat = 40

        if let logo = BrandAssets.tintedLogo(brandColor, size: CGSize(width: logoSide, height: logoSide)) {
            logo.draw(in: CGRect(x: Layout.margin, y: y, width: logoSide, height: logoSide))
            textOrigin += logoSide + 12
        }

        "Enregistrement de la traçabilité des viandes".draw(
            in: CGRect(x: textOrigin, y: y, width: Layout.page.width - textOrigin - Layout.margin, height: 50),
            withAttributes: [.font: Fonts.title]
        )

        y += logoSide + 18

        // Deux champs côte à côte : la date, et l'entreprise.
        let columnWidth = (Layout.contentWidth - 16) / 2

        drawField(
            "Date",
            value: AppFormatters.shortDate(sheet.generatedAt),
            x: Layout.margin,
            y: y,
            width: columnWidth
        )

        drawField(
            "Entreprise",
            value: establishmentLine(sheet),
            x: Layout.margin + columnWidth + 16,
            y: y,
            width: columnWidth
        )

        y += 44

        "Voici l'origine des viandes de notre restaurant.".draw(
            at: CGPoint(x: Layout.margin, y: y),
            withAttributes: [.font: Fonts.intro]
        )

        y += 24
    }

    private static func establishmentLine(_ sheet: MeatOriginSheet) -> String {
        var parts = [sheet.establishmentName]

        if let address = sheet.establishment?.address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: ", "),
           !address.isEmpty {
            parts.append(address)
        }
        return parts.joined(separator: " — ")
    }

    private static func drawContinuation(at y: inout CGFloat) {
        "Traçabilité des viandes (suite)".draw(
            at: CGPoint(x: Layout.margin, y: y),
            withAttributes: [.font: Fonts.title]
        )
        y += 34
    }

    // MARK: Champs

    private static func drawField(
        _ label: String,
        value: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) {
        label.uppercased().draw(
            at: CGPoint(x: x, y: y),
            withAttributes: [.font: Fonts.fieldLabel, .foregroundColor: UIColor.gray]
        )

        value.draw(
            in: CGRect(x: x, y: y + 13, width: width, height: 26),
            withAttributes: [.font: Fonts.fieldValue]
        )
    }

    // MARK: Une viande

    private static func entryHeight(_ entry: BeefOriginRecord) -> CGFloat { 78 }

    private static func drawEntry(_ entry: BeefOriginRecord, at y: inout CGFloat) {
        let height = entryHeight(entry) - 10
        let box = CGRect(x: Layout.margin, y: y, width: Layout.contentWidth, height: height)

        let path = UIBezierPath(roundedRect: box, cornerRadius: 8)
        UIColor.systemGray6.setFill()
        path.fill()
        UIColor.systemGray4.setStroke()
        path.lineWidth = 0.6
        path.stroke()

        // Espèce, en petit au-dessus de la désignation.
        entry.species.label.uppercased().draw(
            at: CGPoint(x: box.minX + 12, y: box.minY + 9),
            withAttributes: [.font: Fonts.species, .foregroundColor: brandColor]
        )

        entry.displayName.draw(
            in: CGRect(x: box.minX + 12, y: box.minY + 21, width: box.width - 24, height: 18),
            withAttributes: [.font: Fonts.meatName]
        )

        // Les trois pays, en trois colonnes égales.
        let columnWidth = (box.width - 24) / 3
        let countries: [(String, String)] = [
            ("Naissance (pays)", entry.birthCountry),
            ("Élevage (pays)", entry.rearingCountry),
            ("Abattage (pays)", entry.slaughterCountry)
        ]

        for (index, country) in countries.enumerated() {
            let x = box.minX + 12 + CGFloat(index) * columnWidth
            let value = country.1.trimmingCharacters(in: .whitespacesAndNewlines)

            country.0.uppercased().draw(
                at: CGPoint(x: x, y: box.minY + 44),
                withAttributes: [.font: Fonts.fieldLabel, .foregroundColor: UIColor.gray]
            )

            (value.isEmpty ? "À renseigner" : value).draw(
                in: CGRect(x: x, y: box.minY + 55, width: columnWidth - 8, height: 16),
                withAttributes: [
                    .font: Fonts.fieldValue,
                    .foregroundColor: value.isEmpty ? UIColor.systemRed : UIColor.label
                ]
            )
        }

        y += entryHeight(entry)
    }

    private static func drawEmptyNotice(at y: inout CGFloat) {
        "Aucune viande déclarée à la carte. Renseignez le registre avant d'afficher ce document."
            .draw(
                in: CGRect(x: Layout.margin, y: y, width: Layout.contentWidth, height: 40),
                withAttributes: [.font: Fonts.intro, .foregroundColor: UIColor.systemRed]
            )
        y += 40
    }

    // MARK: Pied de page

    private static func drawFooter(_ sheet: MeatOriginSheet, in context: UIGraphicsPDFRendererContext) {
        let base = Layout.page.height - Layout.margin - Layout.footerHeight

        // Responsable et signature.
        drawField(
            "Responsable",
            value: sheet.responsibleName.isEmpty ? "—" : sheet.responsibleName,
            x: Layout.margin,
            y: base,
            width: Layout.contentWidth / 2 - 10
        )

        "SIGNATURE".draw(
            at: CGPoint(x: Layout.page.width / 2, y: base),
            withAttributes: [.font: Fonts.fieldLabel, .foregroundColor: UIColor.gray]
        )

        let line = UIBezierPath()
        line.move(to: CGPoint(x: Layout.page.width / 2, y: base + 34))
        line.addLine(to: CGPoint(x: Layout.page.width - Layout.margin, y: base + 34))
        UIColor.systemGray3.setStroke()
        line.lineWidth = 0.8
        line.stroke()

        // Mention réglementaire.
        let legal = """
        Décret n° 2022-65 du 26 janvier 2022 modifiant le décret n° 2002-1455 du 17 décembre 2002 relatif à l'étiquetage des viandes bovines dans les établissements de restauration, étendu aux viandes porcine, ovine et de volaille.

        « Ces mentions sont portées à la connaissance du consommateur, de façon lisible et visible, par affichage, indication sur les cartes et menus, ou sur tout autre support. »
        """

        legal.draw(
            in: CGRect(
                x: Layout.margin,
                y: base + 48,
                width: Layout.contentWidth,
                height: 52
            ),
            withAttributes: [.font: Fonts.legal, .foregroundColor: UIColor.darkGray]
        )

        "Archivage 30 jours · HACCP Pocket · document généré le \(AppFormatters.dateAndTime(sheet.generatedAt))"
            .draw(
                at: CGPoint(x: Layout.margin, y: Layout.page.height - Layout.margin - 10),
                withAttributes: [.font: Fonts.caption, .foregroundColor: UIColor.gray]
            )
    }
}
