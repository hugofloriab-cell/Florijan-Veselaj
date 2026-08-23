//
//  AllergenSheetService.swift
//  HACCPPocket
//
//  Fiche allergènes A4, au format tableau croisé.
//
//  C'est le document que le restaurateur affiche en salle ou garde près du
//  passe : les plats en lignes, les quatorze allergènes en colonnes, un point
//  à l'intersection. Format paysage, parce que quatorze colonnes ne tiennent
//  pas en portrait sans devenir illisibles.
//

import Foundation
import PDFKit
import UIKit

// MARK: - Contenu

struct AllergenSheet {

    let dishes: [Dish]
    let establishment: Establishment?
    /// Filigrane appliqué tant que l'abonnement n'est pas actif.
    let watermark: String?
    let generatedAt: Date

    init(
        dishes: [Dish],
        establishment: Establishment?,
        watermark: String? = nil,
        generatedAt: Date = .now
    ) {
        self.dishes = dishes
        self.establishment = establishment
        self.watermark = watermark
        self.generatedAt = generatedAt
    }

    /// Plats présentés, groupés par catégorie et dans l'ordre de la carte.
    var orderedDishes: [Dish] {
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

    var title: String {
        "Fiche allergènes"
    }

    /// Plats dont la fiche n'a jamais été remplie : ils sont signalés en bas
    /// du document plutôt que présentés comme exempts d'allergènes.
    var incompleteDishes: [Dish] {
        orderedDishes.filter(\.needsAllergenReview)
    }
}

// MARK: - Rendu

/// Volontairement sans isolation d'acteur, comme `PDFReportService` : le
/// rendu se fait dans une fermeture de `UIGraphicsPDFRenderer`, qui n'est pas
/// isolée. Marquer le service `@MainActor` empêcherait ses propres fonctions
/// de dessin de s'y appeler.
enum AllergenSheetService {

    private enum Layout {
        /// A4 paysage.
        static let page = CGRect(x: 0, y: 0, width: 841.8, height: 595.2)
        static let margin: CGFloat = 32
        static let nameColumnWidth: CGFloat = 210
        static let headerHeight: CGFloat = 74
        static let rowHeight: CGFloat = 22
        static let footerHeight: CGFloat = 34

        static var tableWidth: CGFloat { page.width - margin * 2 }
        static var allergenColumnWidth: CGFloat {
            (tableWidth - nameColumnWidth) / CGFloat(Allergen.allCases.count)
        }

        /// La couleur de marque, en UIColor : le rendu PDF travaille en UIKit.
        static let brandColor = UIColor(red: 23 / 255, green: 80 / 255, blue: 127 / 255, alpha: 1)
    }

    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 20, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 11, weight: .regular)
        static let category = UIFont.systemFont(ofSize: 10, weight: .bold)
        static let columnHeader = UIFont.systemFont(ofSize: 8, weight: .semibold)
        static let dish = UIFont.systemFont(ofSize: 10, weight: .medium)
        static let caption = UIFont.systemFont(ofSize: 7.5, weight: .regular)
        static let mark = UIFont.systemFont(ofSize: 11, weight: .bold)
    }

    // MARK: Point d'entrée

    static func render(_ sheet: AllergenSheet) throws -> URL {
        let data = makePDF(sheet)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: sheet))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileName(for sheet: AllergenSheet) -> String {
        let establishment = sheet.establishment?.name
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        var parts = ["fiche-allergenes"]
        if let establishment, !establishment.isEmpty { parts.append(establishment) }
        parts.append(AppFormatters.fileStamp(sheet.generatedAt))
        return parts.joined(separator: "-") + ".pdf"
    }

    // MARK: Dessin

    private static func makePDF(_ sheet: AllergenSheet) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)

        return renderer.pdfData { context in

            let allergens = Allergen.allCases
            var currentCategory: DishCategory?
            var y: CGFloat = 0
            var pageNumber = 0

            /// Ouvre une page et y pose l'en-tête et le tableau vide.
            func startPage() {
                context.beginPage()
                pageNumber += 1
                // Filigrane d'abord : il doit passer derrière le tableau.
                drawPageFurniture(sheet, pageNumber: pageNumber, in: context)
                drawHeader(sheet, in: context)
                y = Layout.margin + Layout.headerHeight
                drawColumnHeaders(allergens, at: &y, in: context)
                // La catégorie doit être rappelée en haut de chaque page.
                if let currentCategory {
                    drawCategory(currentCategory, at: &y, in: context, repeated: true)
                }
            }

            func remainingHeight() -> CGFloat {
                Layout.page.height - Layout.margin - Layout.footerHeight - y
            }

            startPage()

            for dish in sheet.orderedDishes {
                if dish.category != currentCategory {
                    if remainingHeight() < Layout.rowHeight * 3 { startPage() }
                    currentCategory = dish.category
                    drawCategory(dish.category, at: &y, in: context, repeated: false)
                }

                if remainingHeight() < Layout.rowHeight {
                    startPage()
                }

                drawRow(dish, allergens: allergens, at: &y, in: context)
            }

            drawLegend(sheet, at: &y, in: context)
        }
    }

    // MARK: En-tête

    private static func drawHeader(_ sheet: AllergenSheet, in context: UIGraphicsPDFRendererContext) {
        var textOrigin = Layout.margin

        let logoSide: CGFloat = 44
        if let logo = BrandAssets.tintedLogo(Layout.brandColor, size: CGSize(width: logoSide, height: logoSide)) {
            logo.draw(in: CGRect(x: Layout.margin, y: Layout.margin, width: logoSide, height: logoSide))
            textOrigin += logoSide + 12
        }

        sheet.title.draw(
            at: CGPoint(x: textOrigin, y: Layout.margin),
            withAttributes: [.font: Fonts.title]
        )

        var subtitle: [String] = []
        if let name = sheet.establishment?.name, !name.isEmpty { subtitle.append(name) }
        subtitle.append("Mise à jour le \(AppFormatters.shortDate(sheet.generatedAt))")

        subtitle.joined(separator: " · ").draw(
            at: CGPoint(x: textOrigin, y: Layout.margin + 26),
            withAttributes: [.font: Fonts.subtitle, .foregroundColor: UIColor.darkGray]
        )

        "Règlement (UE) n° 1169/2011, annexe II — quatorze substances à déclaration obligatoire."
            .draw(
                at: CGPoint(x: textOrigin, y: Layout.margin + 42),
                withAttributes: [.font: Fonts.caption, .foregroundColor: UIColor.gray]
            )
    }

    // MARK: En-têtes de colonnes

    /// Les libellés d'allergènes sont écrits à la verticale : quarante points
    /// de large ne laissent pas la place à « Anhydride sulfureux ».
    private static func drawColumnHeaders(
        _ allergens: [Allergen],
        at y: inout CGFloat,
        in context: UIGraphicsPDFRendererContext
    ) {
        let cg = context.cgContext
        let height: CGFloat = 68
        let top = y

        cg.setFillColor(UIColor.systemGray6.cgColor)
        cg.fill(CGRect(x: Layout.margin, y: top, width: Layout.tableWidth, height: height))

        "Plat".draw(
            at: CGPoint(x: Layout.margin + 6, y: top + height - 14),
            withAttributes: [.font: Fonts.category]
        )

        var x = Layout.margin + Layout.nameColumnWidth

        for allergen in allergens {
            cg.saveGState()
            // On place l'origine en bas de la colonne, puis on pivote d'un
            // quart de tour : le texte monte au lieu de déborder.
            cg.translateBy(x: x + Layout.allergenColumnWidth / 2 + 3, y: top + height - 4)
            cg.rotate(by: -.pi / 2)
            allergen.shortLabel.draw(
                at: .zero,
                withAttributes: [.font: Fonts.columnHeader]
            )
            cg.restoreGState()

            x += Layout.allergenColumnWidth
        }

        drawGrid(top: top, height: height, in: cg)
        y = top + height
    }

    // MARK: Catégorie

    private static func drawCategory(
        _ category: DishCategory,
        at y: inout CGFloat,
        in context: UIGraphicsPDFRendererContext,
        repeated: Bool
    ) {
        let cg = context.cgContext
        let height: CGFloat = 18

        cg.setFillColor(Layout.brandColor.withAlphaComponent(0.10).cgColor)
        cg.fill(CGRect(x: Layout.margin, y: y, width: Layout.tableWidth, height: height))

        let label = repeated ? "\(category.label) (suite)" : category.label
        label.draw(
            at: CGPoint(x: Layout.margin + 6, y: y + 4),
            withAttributes: [.font: Fonts.category]
        )

        drawGrid(top: y, height: height, in: cg)
        y += height
    }

    // MARK: Ligne

    private static func drawRow(
        _ dish: Dish,
        allergens: [Allergen],
        at y: inout CGFloat,
        in context: UIGraphicsPDFRendererContext
    ) {
        let cg = context.cgContext
        let height = Layout.rowHeight
        let present = dish.allergens

        var name = dish.displayName
        if !dish.isAvailable { name += " (retiré de la carte)" }

        name.draw(
            in: CGRect(
                x: Layout.margin + 6,
                y: y + 5,
                width: Layout.nameColumnWidth - 12,
                height: height - 6
            ),
            withAttributes: [
                .font: Fonts.dish,
                .foregroundColor: dish.isAvailable ? UIColor.label : UIColor.gray
            ]
        )

        var x = Layout.margin + Layout.nameColumnWidth

        for allergen in allergens {
            if present.contains(allergen) {
                let mark = "●"
                let size = mark.size(withAttributes: [.font: Fonts.mark])
                mark.draw(
                    at: CGPoint(
                        x: x + (Layout.allergenColumnWidth - size.width) / 2,
                        y: y + (height - size.height) / 2
                    ),
                    withAttributes: [.font: Fonts.mark, .foregroundColor: UIColor.label]
                )
            } else if dish.needsAllergenReview {
                // Une fiche non remplie n'est pas une absence d'allergène :
                // on marque le doute plutôt que de laisser une case vide.
                let mark = "?"
                let size = mark.size(withAttributes: [.font: Fonts.columnHeader])
                mark.draw(
                    at: CGPoint(
                        x: x + (Layout.allergenColumnWidth - size.width) / 2,
                        y: y + (height - size.height) / 2
                    ),
                    withAttributes: [.font: Fonts.columnHeader, .foregroundColor: UIColor.systemOrange]
                )
            }

            x += Layout.allergenColumnWidth
        }

        drawGrid(top: y, height: height, in: cg)
        y += height
    }

    // MARK: Quadrillage

    private static func drawGrid(top: CGFloat, height: CGFloat, in cg: CGContext) {
        cg.setStrokeColor(UIColor.systemGray3.cgColor)
        cg.setLineWidth(0.4)

        // Bordure de la bande.
        cg.stroke(CGRect(x: Layout.margin, y: top, width: Layout.tableWidth, height: height))

        // Séparateurs verticaux.
        var x = Layout.margin + Layout.nameColumnWidth
        for _ in 0...Allergen.allCases.count {
            cg.move(to: CGPoint(x: x, y: top))
            cg.addLine(to: CGPoint(x: x, y: top + height))
            x += Layout.allergenColumnWidth
        }
        cg.strokePath()
    }

    // MARK: Légende

    private static func drawLegend(
        _ sheet: AllergenSheet,
        at y: inout CGFloat,
        in context: UIGraphicsPDFRendererContext
    ) {
        y += 12

        var lines = ["● présent dans le plat"]

        if !sheet.incompleteDishes.isEmpty {
            lines.append("? fiche non renseignée — renseignez la composition avant d'afficher ce document")
            let names = sheet.incompleteDishes.map(\.displayName).joined(separator: ", ")
            lines.append("À compléter : \(names)")
        }

        lines.append("En cas de doute sur un plat, demandez au responsable de cuisine avant de servir.")

        for line in lines {
            guard y < Layout.page.height - Layout.margin - Layout.footerHeight else { return }
            line.draw(
                at: CGPoint(x: Layout.margin, y: y),
                withAttributes: [.font: Fonts.caption, .foregroundColor: UIColor.darkGray]
            )
            y += 11
        }
    }

    // MARK: Pied de page et filigrane

    private static func drawPageFurniture(
        _ sheet: AllergenSheet,
        pageNumber: Int,
        in context: UIGraphicsPDFRendererContext
    ) {
        if let watermark = sheet.watermark {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.systemRed.withAlphaComponent(0.12)
            ]
            let size = watermark.size(withAttributes: attributes)
            watermark.draw(
                at: CGPoint(
                    x: (Layout.page.width - size.width) / 2,
                    y: (Layout.page.height - size.height) / 2
                ),
                withAttributes: attributes
            )
        }

        let footer = "HACCP Pocket · document généré le \(AppFormatters.dateAndTime(sheet.generatedAt)) · page \(pageNumber)"
        footer.draw(
            at: CGPoint(x: Layout.margin, y: Layout.page.height - Layout.margin - 10),
            withAttributes: [.font: Fonts.caption, .foregroundColor: UIColor.gray]
        )
    }
}
