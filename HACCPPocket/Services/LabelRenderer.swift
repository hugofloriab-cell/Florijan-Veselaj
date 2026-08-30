//
//  LabelRenderer.swift
//  HACCPPocket
//
//  Rendu des étiquettes d'étiquetage alimentaire en PDF, aux dimensions
//  exactes du consommable. Le PDF est ensuite envoyé à AirPrint ou partagé.
//

import Foundation
import SwiftData
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Contenu encodé dans le QR

/// Charge utile du QR code d'une étiquette. Volontairement courte : plus la
/// chaîne est brève, plus le QR reste gros et lisible sur une petite étiquette.
enum LabelPayload {

    /// Forme actuelle, courte.
    private static let prefix = "HP:"

    /// Forme d'origine, conservée en lecture seule : les étiquettes déjà
    /// collées sur des contenants doivent continuer à se scanner. Elles
    /// vivront encore quelques semaines dans les frigos.
    private static let legacyPrefix = "HACCP:P:"

    /// Encode l'identifiant en 25 caractères au lieu de 44.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// POURQUOI LA LONGUEUR COMPTE AUTANT
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Un QR ne grandit pas quand la charge s'allonge : c'est le nombre de
    /// modules — les petits carrés — qui augmente, dans la même surface
    /// imprimée. Chaque module devient donc plus petit.
    ///
    /// « HACCP:P: » suivi d'un UUID avec ses tirets fait 44 caractères, ce qui
    /// demande 33 modules de côté. Sur une étiquette de 62 mm où le QR occupe
    /// 16 mm, cela donne 0,49 mm par module : sous le seuil de lecture d'un
    /// appareil photo de téléphone, et c'est exactement pourquoi le scan
    /// échouait.
    ///
    /// Le préfixe passe à trois caractères et l'UUID est encodé en base64url
    /// — 22 caractères au lieu de 36, sans perte. Total 25 caractères, soit
    /// 25 modules de côté, soit 0,74 mm par module au même endroit.
    static func encode(_ product: TrackedProduct) -> String {
        prefix + compact(product.identifier)
    }

    /// Extrait l'identifiant produit d'un QR scanné, `nil` si ce n'est pas
    /// une étiquette HACCP Pocket.
    static func decode(_ scanned: String) -> UUID? {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix(prefix) {
            return uuid(fromCompact: String(trimmed.dropFirst(prefix.count)))
        }

        if trimmed.hasPrefix(legacyPrefix) {
            return UUID(uuidString: String(trimmed.dropFirst(legacyPrefix.count)))
        }

        return nil
    }

    // MARK: Encodage compact

    /// Les seize octets de l'UUID en base64url, sans remplissage.
    private static func compact(_ identifier: UUID) -> String {
        var raw = identifier.uuid
        let data = withUnsafeBytes(of: &raw) { Data($0) }

        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func uuid(fromCompact string: String) -> UUID? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Le remplissage a été retiré à l'encodage pour gagner deux
        // caractères : il faut le remettre pour décoder.
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64), data.count == 16 else { return nil }
        return data.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}

// MARK: - Rendu

// MARK: - Contenu d'une étiquette

/// Ce qu'une étiquette porte, indépendamment de ce qui l'a produite.
///
/// Le moteur ne connaissait que les produits entamés. Les plats témoins ont
/// exactement les mêmes besoins — un nom, une date qui saute aux yeux, deux
/// ou trois précisions — et rien ne justifiait d'écrire un second moteur qui
/// aurait divergé du premier au premier ajustement de mise en page.
struct LabelContent: Identifiable, Sendable {

    let id: String

    /// Ligne du haut, en gras : le nom du produit ou du plat.
    let title: String

    /// Petite ligne au-dessus de la date, en capitales.
    let caption: String

    /// La date, en très gros : c'est elle qu'on lit à un mètre.
    let highlight: String

    /// Précisions, réunies sur une ligne : lot, fournisseur, opérateur.
    let details: [String]

    /// Allergènes, imprimés en gras sur une ligne à part quand la place le
    /// permet. Vide s'il n'y en a pas à signaler.
    let allergens: String

    /// Charge du QR code, si l'étiquette en porte un.
    let qrPayload: String?

    init(
        id: String,
        title: String,
        caption: String,
        highlight: String,
        details: [String] = [],
        allergens: String = "",
        qrPayload: String? = nil
    ) {
        self.id = id
        self.title = title
        self.caption = caption
        self.highlight = highlight
        self.details = details
        self.allergens = allergens
        self.qrPayload = qrPayload
    }
}

extension TrackedProduct {

    /// Étiquette à coller sur le contenant.
    ///
    /// L'ordre des précisions suit ce qu'on cherche dessus, dans une cuisine
    /// pressée : d'abord quand il a été ouvert, puis où il va, puis les
    /// allergènes — qui sont la seule information à porter une conséquence
    /// immédiate pour un client.
    var labelContent: LabelContent {
        // Volontairement court. Une étiquette de trois centimètres n'a pas la
        // place d'une phrase, et l'année d'ouverture n'apprend rien sur un
        // produit qui vivra trois jours. Le fournisseur reste sur la fiche,
        // où il sert à quelque chose.
        var details = ["Ouv. \(AppFormatters.dayAndMonth(openedAt))"]
        details.append(storage.label)
        if !batchNumber.isEmpty { details.append("Lot \(batchNumber)") }

        return LabelContent(
            id: "product-\(identifier.uuidString)",
            title: name,
            caption: "À CONSOMMER AVANT LE",
            highlight: AppFormatters.shortDate(effectiveLimitDate),
            details: details,
            allergens: allergens.isEmpty ? "" : Allergen.summary(of: allergens),
            qrPayload: LabelPayload.encode(self)
        )
    }
}

extension FoodSample {

    /// Étiquette du plat témoin.
    ///
    /// La date mise en avant est celle de l'élimination possible, pas celle
    /// du prélèvement : sur un bac au fond d'un frigo, la seule question
    /// utile est « est-ce que je peux le jeter ? ».
    var labelContent: LabelContent {
        var details = ["Prélevé le \(AppFormatters.dateAndTime(collectedAt))"]
        if !serviceLabel.isEmpty { details.append(serviceLabel) }
        details.append("\(quantityGrams) g")
        if !operatorName.isEmpty { details.append(operatorName) }

        return LabelContent(
            id: "sample-\(persistentModelID.hashValue)",
            title: displayName,
            caption: "PLAT TÉMOIN — À CONSERVER JUSQU'AU",
            highlight: AppFormatters.shortDate(disposalDate()),
            details: details,
            qrPayload: nil
        )
    }
}

// MARK: - Moteur

enum LabelRenderer {

    /// Produit le PDF des étiquettes. `copies` répète chaque étiquette.
    static func render(
        contents: [LabelContent],
        format: LabelFormat,
        establishment: Establishment? = nil,
        copies: Int = 1
    ) -> Data {
        let queue = contents.flatMap { content in
            Array(repeating: content, count: max(1, copies))
        }

        return format.isSheet
            ? renderSheet(queue, format: format, establishment: establishment)
            : renderRoll(queue, format: format, establishment: establishment)
    }

    /// Conservé pour les appels existants sur les produits entamés.
    static func render(
        products: [TrackedProduct],
        format: LabelFormat,
        establishment: Establishment? = nil,
        copies: Int = 1
    ) -> Data {
        render(
            contents: products.map(\.labelContent),
            format: format,
            establishment: establishment,
            copies: copies
        )
    }

    // MARK: Rouleau — une étiquette par page

    private static func renderRoll(
        _ contents: [LabelContent],
        format: LabelFormat,
        establishment: Establishment?
    ) -> Data {
        let page = CGRect(origin: .zero, size: format.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        return renderer.pdfData { context in
            for content in contents {
                context.beginPage()
                draw(content, in: page.insetBy(dx: 4, dy: 4), format: format, establishment: establishment)
            }
        }
    }

    // MARK: Planche A4 — grille d'étiquettes

    private static func renderSheet(
        _ contents: [LabelContent],
        format: LabelFormat,
        establishment: Establishment?
    ) -> Data {
        guard let layout = format.sheetLayout else {
            return renderRoll(contents, format: format, establishment: establishment)
        }

        let page = CGRect(origin: .zero, size: format.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let labelSize = format.labelSizePoints

        return renderer.pdfData { context in
            var index = 0

            while index < contents.count {
                context.beginPage()

                for slot in 0..<layout.labelsPerSheet {
                    guard index < contents.count else { break }

                    let column = slot % layout.columns
                    let row = slot / layout.columns

                    let origin = CGPoint(
                        x: LabelFormat.points(layout.leftMarginMM + Double(column) * layout.horizontalPitchMM),
                        y: LabelFormat.points(layout.topMarginMM + Double(row) * layout.verticalPitchMM)
                    )

                    let frame = CGRect(origin: origin, size: labelSize).insetBy(dx: 4, dy: 4)
                    draw(contents[index], in: frame, format: format, establishment: establishment)
                    index += 1
                }
            }
        }
    }

    // MARK: Une étiquette

    private static func draw(
        _ content: LabelContent,
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

        // ─────────────────────────────────────────────────────────────────
        // DEUX ZONES, ET NON UNE COLONNE UNIQUE
        // ─────────────────────────────────────────────────────────────────
        //
        // Le QR était centré sur toute la hauteur et amputait donc TOUTES les
        // lignes de trente pour cent de largeur, y compris celles du bas.
        // « Ouvert le 30/08/2026 · Frigo positif · Lot… » n'avait aucune
        // chance de tenir dans ce qu'il en restait.
        //
        // Il n'occupe plus que le bandeau supérieur, à côté de la
        // dénomination et de la date. Les précisions et les allergènes
        // courent sur toute la largeur, là où ils ont la place d'être lus.
        let topBandHeight = height * 0.60
        var textWidth = rect.width

        if format.supportsQRCode, let payload = content.qrPayload {
            // 30 % de la largeur, et non 26 : à 26 %, les modules tombaient à
            // un demi-millimètre sur une étiquette de 62 mm, c'est-à-dire
            // sous le seuil de lecture d'un appareil photo de téléphone.
            let side = min(topBandHeight * 0.95, rect.width * 0.30)
            if let qr = qrImage(for: payload, side: side) {
                drawQRCode(qr, in: CGRect(
                    x: rect.maxX - side,
                    y: rect.minY + (topBandHeight - side) / 2,
                    width: side,
                    height: side
                ))
                textWidth = rect.width - side - 6
            }
        }

        var y = rect.minY

        y += drawText(
            content.title.uppercased(with: AppFormatters.locale),
            font: nameFont,
            color: .black,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.20),
            lines: 1
        )

        y += drawText(
            content.caption,
            font: captionFont,
            color: .darkGray,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.11),
            lines: 1
        )

        y += drawText(
            content.highlight,
            font: dateFont,
            color: .black,
            rect: CGRect(x: rect.minX, y: y, width: textWidth, height: height * 0.29),
            lines: 1
        )

        // À partir d'ici, toute la largeur — et sur deux lignes si besoin.
        // Forcer les précisions sur une seule ligne les réduisait à quatre
        // points sur une 40 × 30, c'est-à-dire à rien.
        y += drawWrapped(
            content.details.joined(separator: " · "),
            font: detailFont,
            color: .darkGray,
            rect: CGRect(x: rect.minX, y: y, width: rect.width, height: height * 0.21),
            maxLines: 2
        )

        // Les allergènes ne passent que si le format a la largeur pour les
        // rendre lisibles — voir `fitsAllergenLine`. Sur une 40 × 30, la
        // ligne serait écrasée, et le format le dit lui-même plutôt que de
        // laisser un seuil chiffré vivre en double ici.
        guard !content.allergens.isEmpty, format.fitsAllergenLine else { return }

        _ = drawText(
            "ALLERGÈNES : " + content.allergens.uppercased(with: AppFormatters.locale),
            font: UIFont.systemFont(ofSize: height * 0.085, weight: .bold),
            color: .black,
            rect: CGRect(x: rect.minX, y: y, width: rect.width, height: height * 0.13),
            lines: 1
        )
    }

    /// Dessine un texte qui peut occuper plusieurs lignes, en réduisant la
    /// taille jusqu'à ce qu'il tienne dans le nombre de lignes accordé.
    ///
    /// Utile là où la ligne est longue par nature : « Ouv. 30/08 · Frigo
    /// positif · Lot L24-0917 » ne rentre pas sur une seule ligne d'une
    /// étiquette de quatre centimètres, et la forcer revenait à l'imprimer
    /// en corps quatre.
    @discardableResult
    private static func drawWrapped(
        _ string: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        maxLines: Int
    ) -> CGFloat {
        guard !string.isEmpty else { return rect.height }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let chosen = wrappedFont(
            for: string,
            font: font,
            width: rect.width,
            maxLines: maxLines,
            paragraph: paragraph
        )

        NSAttributedString(
            string: string,
            attributes: [
                .font: chosen,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        .draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)

        return rect.height
    }

    /// La plus grande taille à laquelle le texte tient dans `maxLines` lignes.
    private static func wrappedFont(
        for string: String,
        font: UIFont,
        width: CGFloat,
        maxLines: Int,
        paragraph: NSParagraphStyle,
        minimumSize: CGFloat = 5
    ) -> UIFont {
        guard width > 0 else { return font }

        var size = font.pointSize

        while size > minimumSize {
            let candidate = font.withSize(size)
            let bounding = (string as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: candidate, .paragraphStyle: paragraph],
                context: nil
            )

            // Une demi-ligne de tolérance : l'arrondi du calcul de hauteur
            // ferait sinon rejeter une taille qui tient parfaitement.
            if bounding.height <= candidate.lineHeight * (CGFloat(maxLines) + 0.5) {
                return candidate
            }
            size -= 0.5
        }

        return font.withSize(minimumSize)
    }

    /// Dessine une ligne en la rétrécissant jusqu'à ce qu'elle tienne.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// CE QUI A ÉTÉ CORRIGÉ LE 30 AOÛT 2026
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Le commentaire annonçait un rétrécissement, le code posait
    /// `.byTruncatingTail` et tronquait. Résultat imprimé sur une planche A4 :
    ///
    ///     À CONSOMMER AVANT LE
    ///     02/09/2…
    ///
    /// Une date de retrait coupée est pire qu'une étiquette absente : elle
    /// donne l'illusion d'une information, et personne ne peut savoir si le
    /// produit est bon jusqu'au 2 septembre ou jusqu'au 2 septembre de
    /// l'année suivante.
    ///
    /// La taille est donc réduite jusqu'à ce que la ligne entre, et la
    /// troncature n'intervient plus que si même la taille plancher ne suffit
    /// pas — cas qui ne se produit plus depuis que les lignes du bas occupent
    /// toute la largeur de l'étiquette.
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
                .font: fittedFont(for: string, font: font, width: rect.width),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        return rect.height
    }

    /// La plus grande taille à laquelle la ligne tient dans la largeur donnée.
    ///
    /// La descente se fait par demi-points : au point entier, une date passe
    /// de tout juste trop large à nettement trop petite, ce qui se voit sur
    /// une étiquette de trois centimètres.
    private static func fittedFont(
        for string: String,
        font: UIFont,
        width: CGFloat,
        minimumSize: CGFloat = 5
    ) -> UIFont {
        guard width > 0 else { return font }

        var size = font.pointSize

        while size > minimumSize {
            let candidate = font.withSize(size)
            let measured = (string as NSString)
                .size(withAttributes: [.font: candidate])
                .width

            if measured <= width { return candidate }
            size -= 0.5
        }

        return font.withSize(minimumSize)
    }

    // MARK: QR code

    /// Génère le QR à la taille demandée. `CIQRCodeGenerator` produit une image
    /// minuscule : on l'agrandit sans interpolation pour garder des bords nets.
    /// Produit l'image du QR, nette et prête à imprimer.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// LE PIÈGE DE L'AGRANDISSEMENT
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Le générateur rend un QR minuscule — un pixel par module. L'agrandir
    /// avec l'interpolation par défaut lisse les bords : chaque carré noir
    /// se fond dans le blanc voisin, et un lecteur ne distingue plus les
    /// modules. À l'œil l'image paraît correcte, simplement un peu douce ;
    /// pour un scanner elle est illisible.
    ///
    /// `samplingNearest()` conserve des bords francs. C'est la différence
    /// entre un QR décoratif et un QR qui fonctionne.
    static func qrImage(for string: String, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        // Marge de sécurité : on agrandit vers une taille supérieure à celle
        // demandée, puis on dessine dans le cadre voulu. Une image plus dense
        // que sa destination reste nette à l'impression, quelle que soit la
        // résolution de l'imprimante.
        let renderedSide = max(side * 4, 256)
        let scale = renderedSide / output.extent.width

        let scaled = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Dessine le QR avec la zone de silence que la norme exige.
    ///
    /// Un QR collé contre du texte ne se lit pas : le lecteur a besoin d'une
    /// bordure blanche pour repérer les trois carrés d'orientation. Le
    /// générateur en fournit une, mais trop mince dès que l'étiquette est
    /// dense — d'où ce fond blanc explicite.
    private static func drawQRCode(_ image: UIImage, in frame: CGRect) {
        UIColor.white.setFill()
        UIBezierPath(rect: frame).fill()

        let quietZone = frame.width * 0.08
        image.draw(in: frame.insetBy(dx: quietZone, dy: quietZone))
    }

    /// Écrit le PDF dans un fichier temporaire, prêt pour `ShareLink`.
    static func writeToTemporaryFile(data: Data, name: String = "etiquettes") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
