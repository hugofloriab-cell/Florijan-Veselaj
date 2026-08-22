//
//  AppConfiguration.swift
//  HACCPPocket
//
//  Constantes de configuration commerciale. Tout ce qui devra être renseigné
//  dans App Store Connect et RevenueCat est regroupé ici, à un seul endroit.
//

import Foundation

enum AppConfiguration {

    // MARK: - RevenueCat

    /// Clé publique RevenueCat du projet iOS (elle commence par « appl_ »).
    /// Tant qu'elle est vide, l'application fonctionne normalement mais les
    /// achats sont indisponibles : c'est le mode de développement.
    ///
    /// Où la trouver : app.revenuecat.com ▸ ton projet ▸ API keys ▸ Public SDK key.
    static let revenueCatAPIKey = ""

    /// Identifiant de l'entitlement RevenueCat qui débloque l'app complète.
    /// À créer à l'identique dans RevenueCat ▸ Entitlements.
    static let entitlementIdentifier = "pro"

    // MARK: - Produits App Store Connect

    static let monthlyProductIdentifier = "com.florijan.HACCPPocket.pro.monthly"
    static let annualProductIdentifier = "com.florijan.HACCPPocket.pro.annual"

    // MARK: - Essai

    /// Durée de l'essai libre, sans carte bancaire, décomptée sur l'appareil.
    static let trialDurationDays = 14

    // MARK: - Liens légaux

    /// Obligatoires pour la validation App Store d'une app à abonnement.
    /// À remplacer par tes vraies pages avant soumission.
    static let privacyPolicyURL = URL(string: "https://example.com/haccp-pocket/confidentialite")!
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static let supportEmail = "contact@example.com"
}
