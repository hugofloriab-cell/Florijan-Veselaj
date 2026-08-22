//
//  DashboardViewModel.swift
//  HACCPPocket
//
//  Synthèse de la journée : ce qu'il reste à faire, ce qui est en anomalie.
//
//  C'est une `struct` construite à partir des tableaux fournis par les `@Query`
//  de la vue, et non une classe qui referait ses propres requêtes. SwiftData
//  rafraîchit les `@Query` automatiquement : la synthèse est donc toujours à
//  jour, sans code d'observation à écrire.
//

import Foundation
import SwiftData

// MARK: - Relevé attendu

/// Un relevé prévu par la routine quotidienne et pas encore saisi.
struct PendingReading: Identifiable, Hashable {
    let equipment: Equipment
    let moment: ReadingMoment

    var id: String { "\(equipment.persistentModelID.hashValue)-\(moment.rawValue)" }

    // Égalité fondée sur l'identifiant seul : deux relevés attendus sont
    // interchangeables dès lors qu'ils visent le même équipement au même moment.
    static func == (lhs: PendingReading, rhs: PendingReading) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Alerte

struct DashboardAlert: Identifiable {

    enum Severity: Int, Comparable {
        case info = 0
        case warning = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let message: String
    let systemImage: String
}

// MARK: - ViewModel

struct DashboardViewModel {

    let referenceDate: Date
    let calendar: Calendar
    let equipments: [Equipment]
    let products: [TrackedProduct]
    let cleaningTasks: [CleaningTask]

    init(
        equipments: [Equipment],
        products: [TrackedProduct],
        cleaningTasks: [CleaningTask],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) {
        self.equipments = equipments
        self.products = products
        self.cleaningTasks = cleaningTasks
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    // MARK: - Relevés de température

    private var activeEquipments: [Equipment] {
        equipments.filter(\.isActive)
    }

    /// Relevés attendus aujourd'hui et encore manquants.
    var pendingReadings: [PendingReading] {
        activeEquipments.flatMap { equipment in
            equipment.pendingMoments(on: referenceDate, calendar: calendar)
                .map { PendingReading(equipment: equipment, moment: $0) }
        }
    }

    /// Nombre total de relevés attendus dans la journée.
    var expectedReadingsToday: Int {
        activeEquipments.reduce(0) { $0 + $1.type.expectedReadingsPerDay }
    }

    var completedReadingsToday: Int {
        max(0, expectedReadingsToday - pendingReadings.count)
    }

    /// Avancement de 0 à 1, pour la jauge du tableau de bord.
    var readingProgress: Double {
        guard expectedReadingsToday > 0 else { return 1 }
        return Double(completedReadingsToday) / Double(expectedReadingsToday)
    }

    var isReadingRoutineComplete: Bool {
        pendingReadings.isEmpty
    }

    /// Relevés du jour hors plage.
    var nonCompliantReadingsToday: [TemperatureReading] {
        activeEquipments
            .flatMap { $0.readings(on: referenceDate, calendar: calendar) }
            .filter { !$0.isCompliant }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Non-conformités sans action corrective renseignée, sur 30 jours.
    /// C'est le premier point que regarde un inspecteur.
    var unresolvedNonCompliances: [TemperatureReading] {
        guard let start = calendar.date(byAdding: .day, value: -30, to: referenceDate) else { return [] }
        return equipments
            .flatMap(\.readings)
            .filter { $0.recordedAt >= start && $0.needsCorrectiveAction }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Taux de conformité sur une période, arrondi au pourcentage.
    func complianceRate(overLastDays days: Int = 30) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -days, to: referenceDate) else { return nil }
        let readings = equipments.flatMap(\.readings).filter { $0.recordedAt >= start }
        guard !readings.isEmpty else { return nil }
        let compliant = readings.filter(\.isCompliant).count
        return Double(compliant) / Double(readings.count)
    }

    // MARK: - Produits tracés

    private var openProducts: [TrackedProduct] {
        products.filter { $0.status == .inUse }
    }

    /// Produits dont la DLC secondaire est dépassée : à retirer immédiatement.
    var expiredProducts: [TrackedProduct] {
        openProducts
            .filter { $0.urgency(at: referenceDate, calendar: calendar) == .expired }
            .sorted { $0.effectiveLimitDate < $1.effectiveLimitDate }
    }

    /// Produits à utiliser en priorité (aujourd'hui, demain ou après-demain).
    var expiringProducts: [TrackedProduct] {
        openProducts
            .filter {
                let urgency = $0.urgency(at: referenceDate, calendar: calendar)
                return urgency == .critical || urgency == .warning
            }
            .sorted { $0.effectiveLimitDate < $1.effectiveLimitDate }
    }

    var openProductsCount: Int { openProducts.count }

    // MARK: - Plan de nettoyage

    var dueCleaningTasks: [CleaningTask] {
        cleaningTasks
            .filter { $0.isDue(at: referenceDate, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.frequency.sortWeight != rhs.frequency.sortWeight {
                    return lhs.frequency.sortWeight < rhs.frequency.sortWeight
                }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    var overdueCleaningTasks: [CleaningTask] {
        cleaningTasks.filter { $0.isOverdue(at: referenceDate, calendar: calendar) }
    }

    // MARK: - Synthèse

    /// Alertes classées de la plus grave à la plus anodine. C'est ce que la vue
    /// d'accueil affiche en tête d'écran.
    var alerts: [DashboardAlert] {
        var alerts: [DashboardAlert] = []

        if !expiredProducts.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .critical,
                    title: "\(expiredProducts.count) produit(s) à retirer",
                    message: "La DLC secondaire est dépassée. Retirez-les et enregistrez la mise au rebut.",
                    systemImage: "trash.circle.fill"
                )
            )
        }

        if !nonCompliantReadingsToday.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .critical,
                    title: "\(nonCompliantReadingsToday.count) relevé(s) hors plage aujourd'hui",
                    message: "Renseignez l'action corrective pour chaque écart constaté.",
                    systemImage: "thermometer.high"
                )
            )
        }

        if !unresolvedNonCompliances.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .warning,
                    title: "\(unresolvedNonCompliances.count) écart(s) sans action corrective",
                    message: "Un écart non documenté est un dossier incomplet en cas de contrôle.",
                    systemImage: "exclamationmark.bubble"
                )
            )
        }

        if !overdueCleaningTasks.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .warning,
                    title: "\(overdueCleaningTasks.count) opération(s) de nettoyage en retard",
                    message: "Le plan de nettoyage n'a pas été respecté sur la période.",
                    systemImage: "sparkles"
                )
            )
        }

        if !expiringProducts.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .info,
                    title: "\(expiringProducts.count) produit(s) à utiliser en priorité",
                    message: "Leur DLC secondaire arrive à échéance sous 48 heures.",
                    systemImage: "clock.badge.exclamationmark"
                )
            )
        }

        return alerts.sorted { $0.severity > $1.severity }
    }

    /// Message affiché quand tout est à jour.
    var isEverythingClear: Bool {
        alerts.isEmpty && isReadingRoutineComplete && dueCleaningTasks.isEmpty
    }
}
