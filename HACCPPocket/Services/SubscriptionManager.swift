//
//  SubscriptionManager.swift
//  HACCPPocket
//
//  Droits d'accès de l'utilisateur : essai libre de 14 jours, puis lecture
//  seule jusqu'à souscription.
//
//  L'intégration RevenueCat est encadrée par `#if canImport(RevenueCat)` :
//  le projet compile et tourne même tant que le paquet n'est pas installé,
//  ce qui évite de bloquer le développement sur une dépendance externe.
//

import Foundation
import Observation

#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Offre présentée à l'utilisateur

/// Représentation neutre d'un abonnement, indépendante du SDK de facturation.
/// Les vues ne connaissent que ce type : changer de fournisseur d'achats
/// n'impacterait que ce fichier.
struct SubscriptionPlan: Identifiable, Equatable {
    let id: String
    let title: String
    let priceLabel: String
    let periodLabel: String
    /// Argument commercial affiché sur la carte (« deux mois offerts »).
    var highlight: String?
    var isBestValue: Bool = false
}

// MARK: - Gestionnaire

@MainActor
@Observable
final class SubscriptionManager {

    static let shared = SubscriptionManager()

    /// État d'accès de l'utilisateur.
    enum Status: Equatable {
        case trial(daysRemaining: Int)
        case subscribed
        case expired

        var isWritable: Bool {
            switch self {
            case .trial, .subscribed: true
            case .expired:            false
            }
        }
    }

    private enum Key {
        static let trialStart = "haccp.trialStartDate"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// Abonnement actif côté facturation.
    private(set) var isSubscribed = false

    /// Vrai une fois RevenueCat configuré avec une clé valide.
    private(set) var isBillingAvailable = false

    private(set) var plans: [SubscriptionPlan] = []
    private(set) var isPurchasing = false
    private(set) var isLoadingPlans = false
    private(set) var lastError: String?

    /// Début de l'essai, posé au tout premier lancement.
    private(set) var trialStartDate: Date

    #if canImport(RevenueCat)
    /// Correspondance entre nos identifiants d'offre et les paquets RevenueCat.
    private var packagesByPlanID: [String: Package] = [:]
    #endif

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar

        if let stored = defaults.object(forKey: Key.trialStart) as? Date {
            self.trialStartDate = stored
        } else {
            let now = Date.now
            defaults.set(now, forKey: Key.trialStart)
            self.trialStartDate = now
        }
    }

    // MARK: - Droits

    var trialEndDate: Date {
        calendar.date(
            byAdding: .day,
            value: AppConfiguration.trialDurationDays,
            to: trialStartDate
        ) ?? trialStartDate
    }

    /// Jours entiers restants avant la fin de l'essai (0 le dernier jour).
    var trialDaysRemaining: Int {
        let start = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: trialEndDate)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    var isTrialActive: Bool {
        !isSubscribed && Date.now < trialEndDate
    }

    var status: Status {
        if isSubscribed { return .subscribed }
        if Date.now < trialEndDate { return .trial(daysRemaining: trialDaysRemaining) }
        return .expired
    }

    /// Seul verrou consulté par les écrans : l'utilisateur peut-il enregistrer ?
    var canWrite: Bool { status.isWritable }

    /// Le filigrane disparaît dès que l'abonnement est actif.
    var pdfWatermark: String? {
        isSubscribed ? nil : "VERSION D'ESSAI"
    }

    // MARK: - Messages

    var statusTitle: String {
        switch status {
        case .subscribed:
            "Abonnement actif"
        case .trial(let days) where days <= 1:
            "Dernier jour d'essai"
        case .trial(let days):
            "Essai : \(days) jours restants"
        case .expired:
            "Mode lecture seule"
        }
    }

    var statusMessage: String {
        switch status {
        case .subscribed:
            "Toutes les fonctions sont débloquées."
        case .trial:
            "Vous disposez de l'application complète, sans carte bancaire."
        case .expired:
            "Vos enregistrements restent consultables et exportables, mais la saisie est bloquée."
        }
    }

    // MARK: - Configuration

    /// Appelée une fois au lancement. Sans clé API, l'app reste utilisable :
    /// seul l'achat est indisponible.
    func configure() async {
        #if canImport(RevenueCat)
        guard !AppConfiguration.revenueCatAPIKey.isEmpty else {
            isBillingAvailable = false
            return
        }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: AppConfiguration.revenueCatAPIKey)
        isBillingAvailable = true

        await refreshEntitlements()
        await loadPlans()
        #else
        isBillingAvailable = false
        #endif
    }

    /// Relit les droits auprès du store. À appeler au retour au premier plan.
    func refreshEntitlements() async {
        #if canImport(RevenueCat)
        guard isBillingAvailable else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            applyEntitlements(from: info)
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    func loadPlans() async {
        #if canImport(RevenueCat)
        guard isBillingAvailable else { return }

        isLoadingPlans = true
        defer { isLoadingPlans = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                lastError = "Aucune offre configurée dans RevenueCat."
                return
            }

            packagesByPlanID.removeAll()
            plans = current.availablePackages.map { package in
                packagesByPlanID[package.identifier] = package
                return makePlan(from: package)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    // MARK: - Achat

    /// Renvoie `true` si l'abonnement est actif au terme de l'opération.
    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async -> Bool {
        #if canImport(RevenueCat)
        guard isBillingAvailable, let package = packagesByPlanID[plan.id] else {
            lastError = "Les achats ne sont pas disponibles pour le moment."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return isSubscribed }
            applyEntitlements(from: result.customerInfo)
            lastError = nil
            return isSubscribed
        } catch {
            lastError = error.localizedDescription
            return false
        }
        #else
        lastError = "Le module d'achat n'est pas installé dans ce build."
        return false
        #endif
    }

    /// Obligatoire pour la validation App Store : l'utilisateur doit pouvoir
    /// retrouver son abonnement sur un nouvel appareil.
    @discardableResult
    func restorePurchases() async -> Bool {
        #if canImport(RevenueCat)
        guard isBillingAvailable else {
            lastError = "Les achats ne sont pas disponibles pour le moment."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let info = try await Purchases.shared.restorePurchases()
            applyEntitlements(from: info)
            lastError = isSubscribed ? nil : "Aucun abonnement actif trouvé pour ce compte Apple."
            return isSubscribed
        } catch {
            lastError = error.localizedDescription
            return false
        }
        #else
        lastError = "Le module d'achat n'est pas installé dans ce build."
        return false
        #endif
    }

    // MARK: - Traduction RevenueCat vers le modèle neutre

    #if canImport(RevenueCat)
    private func applyEntitlements(from info: CustomerInfo) {
        isSubscribed = info.entitlements[AppConfiguration.entitlementIdentifier]?.isActive == true
    }

    private func makePlan(from package: Package) -> SubscriptionPlan {
        let product = package.storeProduct

        var periodLabel = ""
        var highlight: String?
        var isBestValue = false

        switch package.packageType {
        case .annual:
            periodLabel = "par an"
            highlight = "Deux mois offerts"
            isBestValue = true
        case .monthly:
            periodLabel = "par mois"
        case .weekly:
            periodLabel = "par semaine"
        default:
            periodLabel = ""
        }

        return SubscriptionPlan(
            id: package.identifier,
            title: product.localizedTitle,
            priceLabel: product.localizedPriceString,
            periodLabel: periodLabel,
            highlight: highlight,
            isBestValue: isBestValue
        )
    }
    #endif
}
