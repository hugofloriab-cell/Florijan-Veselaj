//
//  NotificationService.swift
//  HACCPPocket
//
//  Rappels locaux : relevé du matin, relevé du soir, contrôle des DLC.
//  100 % local, aucune notification push distante, donc aucun serveur.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationService {

    static let shared = NotificationService()

    /// Les trois rappels quotidiens de l'application.
    enum Reminder: String, CaseIterable, Sendable {
        case morningReading = "haccp.reminder.morning"
        case eveningReading = "haccp.reminder.evening"
        case expiryDigest   = "haccp.reminder.expiry"

        var title: String {
            switch self {
            case .morningReading: "Relevé du matin"
            case .eveningReading: "Relevé du soir"
            case .expiryDigest:   "Contrôle des DLC"
            }
        }

        var body: String {
            switch self {
            case .morningReading:
                "Relevez les températures de vos enceintes avant le service."
            case .eveningReading:
                "Dernier relevé de la journée : n'oubliez pas vos enceintes froides."
            case .expiryDigest:
                "Vérifiez les produits entamés qui arrivent en fin de DLC secondaire."
            }
        }
    }

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Les rappels ne partent que si l'utilisateur a accepté, ou si iOS les a
    /// autorisés de façon provisoire.
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Autorisation

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    // MARK: - Programmation

    /// Applique les préférences de l'utilisateur : reprogramme tout depuis zéro.
    /// Appelée au lancement et à chaque modification d'un réglage de rappel.
    func applySchedule(from preferences: UserPreferences) async {
        cancelAll()

        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        if preferences.remindersEnabled {
            await schedule(.morningReading, at: preferences.morningComponents)
            await schedule(.eveningReading, at: preferences.eveningComponents)
        }

        if preferences.expiryDigestEnabled {
            await schedule(.expiryDigest, at: preferences.expiryDigestComponents)
        }
    }

    /// Programme un rappel quotidien répétitif à l'heure demandée.
    private func schedule(_ reminder: Reminder, at time: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminder.rawValue,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    /// Retire les trois rappels. Ne touche à rien d'autre dans le centre de
    /// notifications, au cas où l'app en programmerait d'autres plus tard.
    func cancelAll() {
        center.removePendingNotificationRequests(
            withIdentifiers: Reminder.allCases.map(\.rawValue)
        )
    }

    /// Liste des rappels réellement programmés — utile pour l'écran Réglages
    /// et pour diagnostiquer un rappel qui ne part pas.
    func pendingReminders() async -> [Reminder] {
        let requests = await center.pendingNotificationRequests()
        let identifiers = Set(requests.map(\.identifier))
        return Reminder.allCases.filter { identifiers.contains($0.rawValue) }
    }
}
