//
//  LabelFormat.swift
//  HACCPPocket
//
//  Formats d'étiquettes d'étiquetage alimentaire. Les dimensions sont
//  exprimées en millimètres, comme sur les emballages de consommables.
//

import Foundation
import CoreGraphics

/// Disposition d'une planche A4 : combien d'étiquettes, où, et espacées comment.
struct SheetLayout: Equatable {
    let columns: Int
    let rows: Int
    /// Marge depuis le bord de la feuille jusqu'à la première étiquette (mm).
    let topMarginMM: Double
    let leftMarginMM: Double
    /// Distance entre deux débuts d'étiquettes consécutives (mm).
    let horizontalPitchMM: Double
    let verticalPitchMM: Double

    var labelsPerSheet: Int { columns * rows }
}

enum LabelFormat: String, CaseIterable, Identifiable, Sendable {

    /// Rouleaux les plus répandus en cuisine.
    case roll62x29
    case roll57x32
    case roll50x30
    case roll40x30
    /// Planche autocollante de 24 étiquettes, type Avery L7159 / J8159.
    case sheetA4x24

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roll62x29:  "Rouleau 62 × 29 mm"
        case .roll57x32:  "Rouleau 57 × 32 mm"
        case .roll50x30:  "Rouleau 50 × 30 mm"
        case .roll40x30:  "Rouleau 40 × 30 mm"
        case .sheetA4x24: "Planche A4 — 24 étiquettes"
        }
    }

    var detail: String {
        switch self {
        case .roll62x29:  "Brother DK-11209 et équivalents"
        case .roll57x32:  "Rouleau thermique standard"
        case .roll50x30:  "Rouleau thermique compact"
        case .roll40x30:  "Petit rouleau thermique"
        case .sheetA4x24: "63,5 × 33,9 mm, type Avery L7159"
        }
    }

    var systemImage: String {
        isSheet ? "doc.on.doc" : "printer"
    }

    var isSheet: Bool { self == .sheetA4x24 }

    /// Dimensions d'une étiquette, en millimètres.
    var labelSizeMM: CGSize {
        switch self {
        case .roll62x29:  CGSize(width: 62, height: 29)
        case .roll57x32:  CGSize(width: 57, height: 32)
        case .roll50x30:  CGSize(width: 50, height: 30)
        case .roll40x30:  CGSize(width: 40, height: 30)
        case .sheetA4x24: CGSize(width: 63.5, height: 33.9)
        }
    }

    /// Disposition de la planche, `nil` pour les rouleaux.
    var sheetLayout: SheetLayout? {
        switch self {
        case .sheetA4x24:
            SheetLayout(
                columns: 3,
                rows: 8,
                topMarginMM: 13,
                leftMarginMM: 7,
                horizontalPitchMM: 66.04,
                verticalPitchMM: 33.9
            )
        default:
            nil
        }
    }

    /// Taille de la page envoyée à l'imprimante, en points PDF.
    var pageSize: CGSize {
        isSheet
            ? CGSize(width: 595.28, height: 841.89)              // A4
            : CGSize(
                width: LabelFormat.points(labelSizeMM.width),
                height: LabelFormat.points(labelSizeMM.height)
              )
    }

    var labelSizePoints: CGSize {
        CGSize(
            width: LabelFormat.points(labelSizeMM.width),
            height: LabelFormat.points(labelSizeMM.height)
        )
    }

    /// Un millimètre vaut 72/25,4 points PostScript.
    static func points(_ millimeters: Double) -> CGFloat {
        CGFloat(millimeters * 72.0 / 25.4)
    }

    /// Le QR n'a de sens que si l'étiquette est assez grande pour le rendre
    /// scannable : en dessous, on privilégie le texte.
    var supportsQRCode: Bool {
        labelSizeMM.height >= 29
    }
}
