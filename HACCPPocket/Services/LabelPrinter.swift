//
//  LabelPrinter.swift
//  HACCPPocket
//
//  Sortie des étiquettes vers une imprimante.
//
//  Le protocole existe pour préparer l'avenir : AirPrint couvre aujourd'hui le
//  Wi-Fi (Brother QL récentes, imprimantes de bureau pour les planches A4).
//  Un pilote Bluetooth BLE pour les petites thermiques ESC/POS viendra s'y
//  brancher sans toucher aux écrans.
//

import Foundation
import UIKit

// MARK: - Interface commune

@MainActor
protocol LabelPrinter {
    /// Nom affiché dans l'interface.
    var displayName: String { get }
    /// Faux si le matériel ou le service n'est pas disponible sur l'appareil.
    var isAvailable: Bool { get }
    /// Envoie un PDF déjà mis en page à l'imprimante.
    func send(pdf: Data, jobName: String, pageSize: CGSize) throws
}

enum LabelPrinterError: LocalizedError {
    case unavailable
    case noPresentationContext

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "L'impression n'est pas disponible sur cet appareil."
        case .noPresentationContext:
            "Impossible d'ouvrir la fenêtre d'impression."
        }
    }
}

// MARK: - AirPrint

/// Passe par la feuille d'impression d'iOS : l'utilisateur y choisit son
/// imprimante, le nombre de copies et le format papier.
@MainActor
struct AirPrintLabelPrinter: LabelPrinter {

    let displayName = "AirPrint (Wi-Fi)"

    var isAvailable: Bool {
        UIPrintInteractionController.isPrintingAvailable
    }

    func send(pdf: Data, jobName: String, pageSize: CGSize) throws {
        guard isAvailable else { throw LabelPrinterError.unavailable }

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general
        // Les étiquettes sont plus larges que hautes sur la plupart des rouleaux.
        info.orientation = pageSize.width > pageSize.height ? .landscape : .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf

        guard let window = AirPrintLabelPrinter.keyWindow else {
            throw LabelPrinterError.noPresentationContext
        }

        // Sur iPad, la feuille d'impression exige une ancre : on l'ancre au
        // centre de la fenêtre plutôt que de laisser iOS lever une exception.
        let anchor = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
        controller.present(from: anchor, in: window, animated: true, completionHandler: nil)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
