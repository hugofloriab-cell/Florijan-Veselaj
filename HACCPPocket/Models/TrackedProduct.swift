//
//  TrackedProduct.swift
//  HACCPPocket
//
//  Produit entamé et tracé : DLC fournisseur, date d'ouverture et DLC secondaire
//  (règle des 3 jours après ouverture, ajustable). C'est l'écran qui remplace
//  les étiquettes autocollantes du frigo.
//

import Foundation
import SwiftData

// MARK: - Zone de stockage

enum StorageZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case positiveCold
    case freezer
    case coldRoom
    case displayCase
    case ambient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .positiveCold: "Frigo positif"
        case .freezer:      "Congélateur"
        case .coldRoom:     "Chambre froide"
        case .displayCase:  "Vitrine"
        case .ambient:      "Réserve sèche"
        }
    }

    var systemImage: String {
        switch self {
        case .positiveCold: "refrigerator"
        case .freezer:      "snowflake"
        case .coldRoom:     "door.left.hand.closed"
        case .displayCase:  "rectangle.split.3x1"
        case .ambient:      "shippingbox"
        }
    }
}

// MARK: - Statut du produit

enum ProductStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inUse      // Entamé, en cours d'utilisation
    case consumed   // Terminé normalement
    case discarded  // Jeté (DLC dépassée, non-conformité...)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inUse:     "En cours"
        case .consumed:  "Consommé"
        case .discarded: "Jeté"
        }
    }

    var systemImage: String {
        switch self {
        case .inUse:     "clock.badge.checkmark"
        case .consumed:  "checkmark.circle"
        case .discarded: "trash"
        }
    }
}

// MARK: - Niveau d'urgence

/// Sert au tri et à la couleur des pastilles. Volontairement sans dépendance
/// SwiftUI : la conversion en `Color` se fait côté vue.
enum ExpiryUrgency: Int, CaseIterable, Comparable, Sendable {
    case safe = 0       // Plus de 2 jours restants
    case warning = 1    // 2 jours
    case critical = 2   // Aujourd'hui ou demain
    case expired = 3    // DLC secondaire dépassée

    static func < (lhs: ExpiryUrgency, rhs: ExpiryUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .safe:     "Conforme"
        case .warning:  "Bientôt limite"
        case .critical: "À utiliser en priorité"
        case .expired:  "À retirer"
        }
    }
}

// MARK: - Modèle

@Model
final class TrackedProduct {

    /// Durée de vie secondaire appliquée par défaut après ouverture (en jours).
    static let defaultShelfLifeDays: Int = 3

    var name: String

    /// Numéro de lot fournisseur (obligatoire en cas de retrait/rappel).
    var batchNumber: String

    /// Code-barres lu via Vision, conservé pour retrouver le produit rapidement.
    var barcode: String

    var supplier: String

    /// DLC / DDM imprimée par le fournisseur, lue par OCR quand elle existe.
    var supplierExpiryDate: Date?

    /// Date d'ouverture, point de départ de la DLC secondaire.
    var openedAt: Date

    /// DLC secondaire : la date réelle de retrait du produit.
    var secondaryLimitDate: Date

    var storageRawValue: String
    var statusRawValue: String

    /// Photo de l'étiquette d'origine : la preuve la plus solide en contrôle.
    @Attribute(.externalStorage) var labelPhotoData: Data?

    /// Date de clôture (consommation ou mise au rebut).
    var closedAt: Date?

    /// Motif de la mise au rebut, exigé pour justifier une destruction.
    var discardReason: String

    var notes: String
    var createdAt: Date

    init(
        name: String,
        openedAt: Date = .now,
        secondaryLimitDate: Date? = nil,
        storage: StorageZone = .positiveCold,
        status: ProductStatus = .inUse,
        batchNumber: String = "",
        barcode: String = "",
        supplier: String = "",
        supplierExpiryDate: Date? = nil,
        labelPhotoData: Data? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.name = name
        self.openedAt = openedAt
        self.secondaryLimitDate = secondaryLimitDate
            ?? TrackedProduct.defaultLimitDate(openedAt: openedAt)
        self.storageRawValue = storage.rawValue
        self.statusRawValue = status.rawValue
        self.batchNumber = batchNumber
        self.barcode = barcode
        self.supplier = supplier
        self.supplierExpiryDate = supplierExpiryDate
        self.labelPhotoData = labelPhotoData
        self.closedAt = nil
        self.discardReason = ""
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - Calcul de la DLC secondaire

extension TrackedProduct {

    /// DLC secondaire par défaut : ouverture + N jours, ramenée en fin de journée.
    static func defaultLimitDate(
        openedAt: Date,
        days: Int = TrackedProduct.defaultShelfLifeDays,
        calendar: Calendar = .current
    ) -> Date {
        let shifted = calendar.date(byAdding: .day, value: days, to: openedAt) ?? openedAt
        return calendar.date(
            bySettingHour: 23, minute: 59, second: 0, of: shifted
        ) ?? shifted
    }

    /// La date retenue est toujours la plus contraignante entre la DLC
    /// fournisseur et la DLC secondaire : on ne prolonge jamais un produit.
    var effectiveLimitDate: Date {
        guard let supplierExpiryDate else { return secondaryLimitDate }
        return Swift.min(supplierExpiryDate, secondaryLimitDate)
    }
}

// MARK: - Logique métier

extension TrackedProduct {

    var storage: StorageZone {
        get { StorageZone(rawValue: storageRawValue) ?? .positiveCold }
        set { storageRawValue = newValue.rawValue }
    }

    var status: ProductStatus {
        get { ProductStatus(rawValue: statusRawValue) ?? .inUse }
        set { statusRawValue = newValue.rawValue }
    }

    /// Nombre de jours restants (0 = dernier jour, négatif = dépassé).
    func daysRemaining(from reference: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: effectiveLimitDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func isExpired(at reference: Date = .now) -> Bool {
        effectiveLimitDate < reference
    }

    func urgency(at reference: Date = .now, calendar: Calendar = .current) -> ExpiryUrgency {
        guard status == .inUse else { return .safe }
        if isExpired(at: reference) { return .expired }
        switch daysRemaining(from: reference, calendar: calendar) {
        case ..<0:  return .expired
        case 0, 1:  return .critical
        case 2:     return .warning
        default:    return .safe
        }
    }

    /// Libellé court affiché dans la liste : « J-2 », « Dernier jour », « Périmé ».
    func remainingLabel(at reference: Date = .now, calendar: Calendar = .current) -> String {
        guard status == .inUse else { return status.label }
        let days = daysRemaining(from: reference, calendar: calendar)
        switch days {
        case ..<0:  return "Périmé"
        case 0:     return "Dernier jour"
        case 1:     return "Demain"
        default:    return "J-\(days)"
        }
    }

    /// Clôture le produit comme entièrement consommé.
    func markConsumed(at date: Date = .now) {
        status = .consumed
        closedAt = date
        discardReason = ""
    }

    /// Clôture le produit comme jeté, avec son motif obligatoire.
    func markDiscarded(reason: String, at date: Date = .now) {
        status = .discarded
        closedAt = date
        discardReason = reason
    }

    /// Rouvre un produit clôturé par erreur.
    func reopen() {
        status = .inUse
        closedAt = nil
        discardReason = ""
    }

    /// Recalcule la DLC secondaire après un changement de date d'ouverture.
    func refreshSecondaryLimit(days: Int = TrackedProduct.defaultShelfLifeDays) {
        secondaryLimitDate = TrackedProduct.defaultLimitDate(openedAt: openedAt, days: days)
    }
}
