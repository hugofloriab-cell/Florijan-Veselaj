//
//  NotificationService.swift
//  HACCPPocket
//
//  Rappels locaux, entièrement définis par l'utilisateur. Aucune notification
//  distante, donc aucun serveur.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationService {

    static let shared = NotificationService()

    /// Préfixe commun : permet de retirer nos rappels sans toucher au reste
    /// du centre de notifications.
    private static let identifierPrefix = "haccp.reminder."
    private static let testIdentifier = "haccp.reminder.test"

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount: Int = 0
    private(set) var lastError: String?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Les rappels ne partent que si l'utilisateur a accepté, ou si iOS les a
    /// autorisés de façon provisoire.
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    /// Message d'état affiché dans les réglages : c'est lui qui explique
    /// pourquoi un rappel ne part pas.
    var statusMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            "Les notifications ne sont pas encore autorisées : aucun rappel ne partira."
        case .denied:
            "Les notifications sont refusées. Ouvrez Réglages ▸ Notifications ▸ HACCP Pocket pour les réactiver."
        case .authorized, .provisional, .ephemeral:
            scheduledCount > 0
                ? "\(scheduledCount) rappel(s) programmé(s) sur cet appareil."
                : "Aucun rappel actif. Activez-en au moins un ci-dessous."
        @unknown default:
            "État des notifications inconnu."
        }
    }

    // MARK: - Autorisation

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        await refreshScheduledCount()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            lastError = error.localizedDescription
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Demande l'autorisation si elle n'a jamais été posée. Appelée quand
    /// l'utilisateur active son premier rappel : lui faire chercher un bouton
    /// séparé était le meilleur moyen qu'aucun rappel ne parte jamais.
    func requestAuthorizationIfNeeded() async {
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: - Programmation

    /// Reprogramme tous les rappels depuis les préférences.
    func applySchedule(from preferences: UserPreferences) async {
        await removeAllReminders()
        await refreshAuthorizationStatus()

        guard isAuthorized else {
            scheduledCount = 0
            return
        }

        for reminder in preferences.enabledReminders {
            await schedule(reminder)
        }

        await refreshScheduledCount()
    }

    private func schedule(_ reminder: ReminderSlot) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.label.isEmpty ? "Rappel" : reminder.label
        content.body = "Ouvrez HACCP Pocket pour enregistrer ce point de contrôle."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: reminder.components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func removeAllReminders() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationService.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func refreshScheduledCount() async {
        let pending = await center.pendingNotificationRequests()
        scheduledCount = pending
            .filter { $0.identifier.hasPrefix(NotificationService.identifierPrefix) }
            .filter { $0.identifier != NotificationService.testIdentifier }
            .count
    }

    // MARK: - Diagnostic

    /// Programme une notification dans quelques secondes. Sans ce bouton,
    /// vérifier que les rappels fonctionnent obligeait à attendre le lendemain.
    ///
    /// - Important : sur iPhone, une notification n'apparaît pas en bannière
    ///   si l'application est au premier plan. Verrouillez l'écran ou passez
    ///   sur l'écran d'accueil pendant le décompte.
    @discardableResult
    func sendTestNotification(afterSeconds seconds: TimeInterval = 10) async -> Bool {
        await refreshAuthorizationStatus()
        guard isAuthorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Test de rappel"
        content.body = "Si vous lisez ceci, les rappels de HACCP Pocket fonctionnent."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: NotificationService.testIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
