//
//  LabelRenderer.swift
//  HACCPPocket
//
//  Rendu des étiquettes d'étiquetage alimentaire en PDF, aux dimensions
//  exactes du consommable. Le PDF est ensuite envoyé à AirPrint ou partagé.
//

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Contenu encodé dans le QR

/// Charge utile du QR code d'une étiquette. Volontairement courte : plus la
/// chaîne est brève, plus le QR reste gros et lisible sur une petite étiquette.
enum LabelPayload {

    private static let prefix = "HACCP:P:"

    static func encode(_ product: TrackedProduct) -> String {
        prefix + product.identifier.uuidString
    }

    /// Extrait l'identifiant produit d'un QR scanné, `nil` si ce n'est pas
    /// une étiquette HACCP Pocket.
    static func decode(_ scanned: String) -> UUID? {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(prefix.count)))
    }
}

// MARK: - Rendu

enum LabelRenderer {

    /// Produit le PDF des étiquettes. `copies` répète chaque produit.
    static func render(
        products: [TrackedProduct],
        format: LabelFormat,
        establishment: Establishment? = nil,
        copies: Int = 1
    ) -> Data {
        let queue = products.flatMap { product in
            Array(repeating: product, count: max(1, copies))
        }

        return format.isSheet
            ? renderSheet(queue, format: format, establishment: establishment)
            : renderRoll(queue, format: format, establishment: establishment)
    }

    // MARK: Rouleau — une étiquette par page

    private static func renderRoll(
        _ products: [TrackedProduct],
        format: LabelFormat,
        establishment: Establishment?
    ) -> Data {
        let page = CGRect(origin: .zero, size: format.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        return renderer.pdfData { context in
            for product in products {
                context.beginPage()
                draw(product, in: page.insetBy(dx: 4, dy: 4), format: format, establishment: establishment)
            }
        }
    }

    // MARK: Planche A4 — grille d'étiquettes

    private static func renderSheet(
        _ products: [TrackedProduct],
        format: LabelFormat,
        establishment: Establishment?
    ) -> Data {
        guard let layout = format.sheetLayout else {
            return renderRoll(products, format: format, establishment: establishment)
        }

        let page = CGRect(origin: .zero, size: format.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let labelSize = format.labelSizePoints

        return renderer.pdfData { context in
            var index = 0

            while index < products.count {
                context.beginPage()

                for slot in 0..<layout.labelsPerSheet {
                    guard index < products.count else { break }

                    let column = slot % layout.columns
                    let row = slot / layout.columns

                    let origin = CGPoint(
                        x: LabelFormat.points(layout.leftMarginMM + Double(column) * layout.horizontalPitchMM),
                        y: LabelFormat.points(layout.topMarginMM + Double(row) * layout.verticalPitchMM)
                    )

                    let frame = CGRect(origin: origin, size: labelSize).insetBy(dx: 4, dy: 4)
                    draw(products[index], in: frame, format: format, establishment: establishment)
                    index += 1
                }
            }
        }
    }

    // MARK: Une étiquette

    private static func draw(
        _ product: TrackedProduct,
        in rect: CGRect,
        format: LabelFormat,
        establishment: Establishment?
    ) {
        // Les tailles suivent la hauteur de l'étiquette : le même code produit
        // une 40 × 30 lisible et une 62 × 29 aérée.
        let height = rect.height
        let nameFont = UIFont.systemFont(ofSize: height * 0.16, weight: .bold)
        let captionFont = UIFont.systemFont(ofSize: height * 0.095, weight: .semibold)
        let dateFont = UIFont.systemFont(ofSize: height * 0.24, weight: .heavy)
        let detailFont = UIFont.systemFont(ofSize: height * 0.095, weight: .regular)

        // Le QR occupe la colonne de droite quand l'étiquette est assez haute.
        var textWidth = rect.width
        if format.supportsQRCode {
            let side = min(height * 0.62, rect.width * 0.3)
            if let qr = qrImage(for: LabelPayload.encode(product), side: side) {
                qr.draw(in: CGRect(
                    x: rect.maxX - side,
                    y: rect.minY + (height - side) / 2,
                    width: side,
                    height: side
                ))
                textWidth = rect.width - side - 6
            }
        }

        var y = rect.minY

        y += drawText(
            product.name.uppercased(with: AppFormatters.locale),
            font: nameFont,
            color: .black,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.22),
            lines: 1
        )

        y += drawText(
            "À CONSOMMER AVANT LE",
            font: captionFont,
            color: .darkGray,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.13),
            lines: 1
        )

        y += drawText(
            AppFormatters.shortDate(product.effectiveLimitDate),
            font: dateFont,
            color: .black,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.3),
            lines: 1
        )

        var details = ["Ouvert le \(AppFormatters.shortDate(product.openedAt))"]
        if !product.batchNumber.isEmpty { details.append("Lot \(product.batchNumber)") }
        if !product.supplier.isEmpty { details.append(product.supplier) }

        _ = drawText(
            details.joined(separator: " · "),
            font: detailFont,
            color: .darkGray,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.13),
            lines: 1
        )
    }

    /// Dessine une ligne en la rétrécissant si besoin pour qu'elle tienne,
    /// et renvoie la hauteur consommée.
    @discardableResult
    private static func drawText(
        _ string: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        lines: Int
    ) -> CGFloat {
        guard !string.isEmpty else { return rect.height }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let attributed = NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        return rect.height
    }

    // MARK: QR code

    /// Génère le QR à la taille demandée. `CIQRCodeGenerator` produit une image
    /// minuscule : on l'agrandit sans interpolation pour garder des bords nets.
    static func qrImage(for string: String, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Écrit le PDF dans un fichier temporaire, prêt pour `ShareLink`.
    static func writeToTemporaryFile(data: Data, name: String = "etiquettes") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
