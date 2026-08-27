//
//  MailComposeView.swift
//  HACCPPocket
//
//  Fenêtre de courrier du système, enveloppée pour SwiftUI.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI PASSER PAR LE COURRIER DU TÉLÉPHONE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Envoyer un courriel depuis l'application supposerait un serveur d'envoi,
//  donc un abonnement mensuel et une adresse expéditrice qui ne serait pas
//  celle du restaurant. Les messages partiraient d'un domaine inconnu du
//  destinataire, avec toutes les chances de finir en indésirables.
//
//  En ouvrant la fenêtre du système, le message part de la boîte de
//  l'utilisateur, atterrit dans ses messages envoyés, et le destinataire peut
//  y répondre normalement. L'application reste sans serveur et sans coût.
//
//  Contrepartie assumée : c'est l'utilisateur qui appuie sur « Envoyer », et
//  l'application ne sait que ce que le système lui rapporte — envoyé, ou
//  annulé. Elle ne peut pas garantir la remise, et ne le prétend pas.
//

import SwiftUI

#if canImport(MessageUI)
import MessageUI
#endif

struct MailComposeView: UIViewControllerRepresentable {

    let recipients: [String]
    let subject: String
    let body: String

    /// Photo jointe, le cas échéant.
    var attachment: Data?

    /// Appelé à la fermeture : `true` si le système rapporte un envoi.
    let onFinish: (Bool) -> Void

    /// Un appareil sans compte de messagerie configuré ne peut pas composer.
    /// C'est le cas du simulateur, et de certains téléphones d'entreprise.
    static var canSendMail: Bool {
        #if canImport(MessageUI)
        MFMailComposeViewController.canSendMail()
        #else
        false
        #endif
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients.filter { !$0.isEmpty })
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)

        if let attachment {
            controller.addAttachmentData(
                attachment,
                mimeType: "image/jpeg",
                fileName: "incident.jpg"
            )
        }

        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {
        // Rien à rafraîchir : la fenêtre est configurée une fois, à l'ouverture.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {

        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            // `.saved` compte comme un envoi manqué : le brouillon est dans
            // la boîte, mais personne ne l'a reçu.
            let sent = (result == .sent)
            controller.dismiss(animated: true) { [onFinish] in
                onFinish(sent)
            }
        }
    }
}
