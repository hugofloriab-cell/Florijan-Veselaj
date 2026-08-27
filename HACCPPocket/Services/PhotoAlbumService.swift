//
//  PhotoAlbumService.swift
//  HACCPPocket
//
//  Impression de l'album photo.
//
//  Le registre mensuel est un tableau : il se lit vite, et c'est ce qu'on
//  tend d'abord à un contrôleur. Ce document-ci est son annexe : les preuves
//  visuelles, sorties seulement si on les demande.
//
//  Format : A4 portrait, quatre photos par page. Deux photos par page
//  gaspillerait le papier d'un restaurateur qui en a deux cents ; six les
//  rendrait illisibles. Chaque vignette porte sa date, son origine et son
//  intitulé, faute de quoi une photo imprimée ne prouve rien.
//

import Foundation
import UIKit

// MARK: - Contenu

struct PhotoAlbum {

    let entries: [PhotoEntry]
    let establishment: Establishment?
    let generatedAt: Date

    init(entries: [PhotoEntry], establishment: Establishment?, generatedAt: Date = .now) {
        self.entries = entries
        self.establishment = establishment
        self.generatedAt = generatedAt
    }

    /// De la plus ancienne à la plus récente : un album se parcourt dans le
    /// sens du temps, contrairement à l'écran qui montre d'abord le dernier.
    var orderedEntries: [PhotoEntry] {
        entries.sorted { $0.capturedAt < $1.capturedAt }
    }

    var establishmentName: String {
        let name = establishment?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Entreprise non renseignée" : name
    }

    /// Bornes réelles de l'album, affichées en en-tête.
    var period: (start: Date, end: Date)? {
        guard let first = orderedEntries.first, let last = orderedEntries.last else { return nil }
        return (first.capturedAt, last.capturedAt)
    }
}

// MARK: - Rendu

enum PhotoAlbumService {

    private enum Layout {
        static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        static let margin: CGFloat = 40
        static let gutter: CGFloat = 16
        static let captionHeight: CGFloat = 34
        static let footerHeight: CGFloat = 26
        static let headerHeight: CGFloat = 74

        static var contentWidth: CGFloat { page.width - margin * 2 }
        static var cellWidth: CGFloat { (contentWidth - gutter) / 2 }

        /// Deux rangées par page, sous l'en-tête et au-dessus du pied.
        static var cellHeight: CGFloat {
            let usable = page.height - margin * 2 - headerHeight - footerHeight - gutter
            return usable / 2
        }

        static var imageHeight: CGFloat { cellHeight - captionHeight }
    }

    private enum Fonts {
        static let title = UIFont.systemFont(ofSize: 19, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 10, weight: .regular)
        static let caption = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let detail = UIFont.systemFont(ofSize: 8, weight: .regular)
        static let footer = UIFont.systemFont(ofSize: 7.5, weight: .regular)
    }

    private static let brandColor = UIColor(red: 23 / 255, green: 80 / 255, blue: 127 / 255, alpha: 1)

    // MARK: Point d'entrée

    static func render(_ album: PhotoAlbum) throws -> URL {
        let data = makePDF(album)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: album))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileName(for album: PhotoAlbum) -> String {
        let slug = album.establishmentName
            .folding(options: .diacriticInsensitive, locale: AppFormatters.locale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        var parts = ["photos"]
        if !slug.isEmpty { parts.append(slug) }
        parts.append(AppFormatters.fileStamp(album.generatedAt))
        return parts.joined(separator: "-") + ".pdf"
    }

    // MARK: Dessin

    private static func makePDF(_ album: PhotoAlbum) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)
        let entries = album.orderedEntries

        return renderer.pdfData { context in
            var pageNumber = 0

            if entries.isEmpty {
                context.beginPage()
                pageNumber += 1
                drawHeader(album, pageNumber: pageNumber)
                drawEmptyNotice()
                drawFooter(album, pageNumber: pageNumber)
                return
            }

            // Quatre vignettes par page, dans l'ordre chronologique.
            for start in stride(from: 0, to: entries.count, by: 4) {
                context.beginPage()
                pageNumber += 1
                drawHeader(album, pageNumber: pageNumber)

                let end = min(start + 4, entries.count)
                for index in start..<end {
                    let slot = index - start
                    drawCell(entries[index], slot: slot)
                }

                drawFooter(album, pageNumber: pageNumber)
            }
        }
    }

    // MARK: En-tête

    private static func drawHeader(_ album: PhotoAlbum, pageNumber: Int) {
        var textOrigin = Layout.margin
        let logoSide: CGFloat = 34
        let y = Layout.margin

        if let logo = BrandAssets.tintedLogo(brandColor, size: CGSize(width: logoSide, height: logoSide)) {
            logo.draw(in: CGRect(x: Layout.margin, y: y, width: logoSide, height: logoSide))
            textOrigin += logoSide + 10
        }

        "Album photo — pièces justificatives".draw(
            at: CGPoint(x: textOrigin, y: y + 1),
            withAttributes: [.font: Fonts.title]
        )

        var subtitle = album.establishmentName
        if let period = album.period {
            let from = AppFormatters.shortDate(period.start)
            let to = AppFormatters.shortDate(period.end)
            subtitle += from == to ? " · \(from)" : " · du \(from) au \(to)"
        }

        subtitle.draw(
            in: CGRect(
                x: textOrigin,
                y: y + 24,
                width: Layout.page.width - textOrigin - Layout.margin,
                height: 26
            ),
            withAttributes: [.font: Fonts.subtitle, .foregroundColor: UIColor.darkGray]
        )

        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: Layout.margin, y: y + Layout.headerHeight - 12))
        rule.addLine(to: CGPoint(x: Layout.page.width - Layout.margin, y: y + Layout.headerHeight - 12))
        UIColor.systemGray4.setStroke()
        rule.lineWidth = 0.6
        rule.stroke()
    }

    // MARK: Une vignette

    /// `slot` vaut 0 à 3 : deux colonnes, deux rangées.
    private static func drawCell(_ entry: PhotoEntry, slot: Int) {
        let column = slot % 2
        let row = slot / 2

        let x = Layout.margin + CGFloat(column) * (Layout.cellWidth + Layout.gutter)
        let y = Layout.margin + Layout.headerHeight
            + CGFloat(row) * (Layout.cellHeight + Layout.gutter)

        let imageFrame = CGRect(x: x, y: y, width: Layout.cellWidth, height: Layout.imageHeight)

        // Fond gris : une photo sombre garde un cadre visible à l'impression.
        let background = UIBezierPath(roundedRect: imageFrame, cornerRadius: 6)
        UIColor.systemGray6.setFill()
        background.fill()

        if let image = UIImage(data: entry.data) {
            drawAspectFit(image, in: imageFrame.insetBy(dx: 3, dy: 3))
        }

        UIColor.systemGray4.setStroke()
        background.lineWidth = 0.6
        background.stroke()

        // Bandeau : origine, intitulé, date.
        entry.source.printLabel.uppercased().draw(
            at: CGPoint(x: x, y: imageFrame.maxY + 5),
            withAttributes: [.font: Fonts.detail, .foregroundColor: brandColor]
        )

        entry.title.draw(
            in: CGRect(x: x, y: imageFrame.maxY + 14, width: Layout.cellWidth, height: 12),
            withAttributes: [.font: Fonts.caption]
        )

        var detail = AppFormatters.dateAndTime(entry.capturedAt)
        let subtitle = entry.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty { detail += " · \(subtitle)" }

        detail.draw(
            in: CGRect(x: x, y: imageFrame.maxY + 24, width: Layout.cellWidth, height: 11),
            withAttributes: [.font: Fonts.detail, .foregroundColor: UIColor.darkGray]
        )
    }

    /// Dessine l'image entière dans le cadre, sans la déformer ni la rogner.
    ///
    /// Une photo de bon de livraison rognée peut perdre le numéro de lot,
    /// c'est-à-dire précisément ce qu'on cherchait à conserver.
    private static func drawAspectFit(_ image: UIImage, in frame: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        let scale = min(frame.width / size.width, frame.height / size.height)
        let width = size.width * scale
        let height = size.height * scale

        let target = CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
        image.draw(in: target)
    }

    private static func drawEmptyNotice() {
        "Aucune photo à imprimer pour la sélection en cours.".draw(
            at: CGPoint(x: Layout.margin, y: Layout.margin + Layout.headerHeight),
            withAttributes: [.font: Fonts.subtitle, .foregroundColor: UIColor.systemRed]
        )
    }

    // MARK: Pied de page

    private static func drawFooter(_ album: PhotoAlbum, pageNumber: Int) {
        let y = Layout.page.height - Layout.margin - 10

        "\(BrandAssets.productName) · album généré le \(AppFormatters.dateAndTime(album.generatedAt)) · annexe au registre, non incluse dans le registre mensuel"
            .draw(
                at: CGPoint(x: Layout.margin, y: y),
                withAttributes: [.font: Fonts.footer, .foregroundColor: UIColor.gray]
            )

        let number = "Page \(pageNumber)"
        let width = number.size(withAttributes: [.font: Fonts.footer]).width
        number.draw(
            at: CGPoint(x: Layout.page.width - Layout.margin - width, y: y),
            withAttributes: [.font: Fonts.footer, .foregroundColor: UIColor.gray]
        )
    }
}

// MARK: - Intitulé imprimé

extension PhotoEntry.Source {

    /// Libellé au singulier : sous une vignette, « Réceptions » sonne faux.
    var printLabel: String {
        switch self {
        case .delivery:        return "Réception"
        case .cleaning:        return "Nettoyage"
        case .product:         return "Étiquette produit"
        case .cleaningProduct: return "Produit d'entretien"
        case .pest:            return "Nuisibles"
        }
    }
}
