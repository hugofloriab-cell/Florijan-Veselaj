//
//  PaywallView.swift
//  HACCPPocket
//
//  Écran d'abonnement. Il s'ouvre à la fin de l'essai, ou depuis les réglages.
//  Tant que RevenueCat n'est pas configuré, les offres sont affichées à titre
//  indicatif pour permettre de travailler la maquette.
//

import SwiftUI

struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription

    @State private var selectedPlanID: String?
    @State private var showsRestoreResult = false
    @State private var restoreSucceeded = false

    /// Offres réelles si elles sont chargées, sinon un aperçu de développement.
    private var displayedPlans: [SubscriptionPlan] {
        subscription.plans.isEmpty ? PaywallView.previewPlans : subscription.plans
    }

    private var selectedPlan: SubscriptionPlan? {
        displayedPlans.first { $0.id == selectedPlanID } ?? displayedPlans.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    features
                    plansSection
                    callToAction
                    legal
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HACCP Pocket Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                if subscription.plans.isEmpty { await subscription.loadPlans() }
                if selectedPlanID == nil {
                    selectedPlanID = displayedPlans.first(where: \.isBestValue)?.id
                        ?? displayedPlans.first?.id
                }
            }
            .alert(
                restoreSucceeded ? "Abonnement restauré" : "Aucun abonnement trouvé",
                isPresented: $showsRestoreResult
            ) {
                Button("OK", role: .cancel) {
                    if restoreSucceeded { dismiss() }
                }
            } message: {
                Text(subscription.lastError ?? "Votre abonnement a bien été réactivé sur cet appareil.")
            }
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: 10) {
            BrandLogo(size: 76)

            Text(subscription.statusTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(subscription.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Arguments

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(
                "Registre PDF sans filigrane",
                detail: "Le document prêt à présenter lors d'un contrôle.",
                systemImage: "doc.text.fill"
            )
            featureRow(
                "Relevés et traçabilité illimités",
                detail: "Autant d'enceintes, de produits et de contrôles que nécessaire.",
                systemImage: "thermometer.medium"
            )
            featureRow(
                "Lecture des DLC par l'appareil photo",
                detail: "Une photo de l'étiquette suffit à remplir la fiche.",
                systemImage: "camera.viewfinder"
            )
            featureRow(
                "Rappels quotidiens",
                detail: "Plus d'oubli de relevé matin ou soir.",
                systemImage: "bell.badge.fill"
            )
            featureRow(
                "Aucune donnée envoyée sur Internet",
                detail: "Tout reste sur votre appareil, sans compte à créer.",
                systemImage: "lock.shield.fill"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.brand)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Offres

    private var plansSection: some View {
        VStack(spacing: 12) {
            ForEach(displayedPlans) { plan in
                Button {
                    selectedPlanID = plan.id
                } label: {
                    planCard(plan)
                }
                .buttonStyle(.plain)
            }

            if !subscription.isBillingAvailable {
                Label(
                    "Achats non configurés : ces tarifs sont un aperçu. Renseignez la clé RevenueCat dans AppConfiguration pour les activer.",
                    systemImage: "hammer"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
            }
        }
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = plan.id == selectedPlan?.id

        return HStack(spacing: 14) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.brand : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title)
                    .font(.headline)
                if let highlight = plan.highlight {
                    Text(highlight)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.brand)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.priceLabel)
                    .font(.headline.monospacedDigit())
                Text(plan.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.brand : Color.clear, lineWidth: 2)
        }
    }

    // MARK: - Action

    private var callToAction: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase() }
            } label: {
                HStack {
                    if subscription.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(subscription.isSubscribed ? "Abonnement actif" : "S'abonner")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
            .disabled(subscription.isPurchasing || subscription.isSubscribed || selectedPlan == nil)

            Button("Restaurer mes achats") {
                Task { await restore() }
            }
            .font(.subheadline)
            .disabled(subscription.isPurchasing)

            if let error = subscription.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Mentions légales

    private var legal: some View {
        VStack(spacing: 8) {
            Text("L'abonnement se renouvelle automatiquement, sauf résiliation au moins 24 h avant la fin de la période en cours. La gestion se fait dans les réglages de votre compte Apple.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Conditions d'utilisation", destination: AppConfiguration.termsOfUseURL)
                Link("Confidentialité", destination: AppConfiguration.privacyPolicyURL)
            }
            .font(.caption2)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func purchase() async {
        guard let plan = selectedPlan else { return }
        if await subscription.purchase(plan) { dismiss() }
    }

    private func restore() async {
        restoreSucceeded = await subscription.restorePurchases()
        showsRestoreResult = true
    }

    // MARK: - Aperçu de développement

    /// Tarifs affichés tant que les offres réelles ne sont pas chargées.
    /// Ils permettent de travailler la maquette sans compte App Store.
    static let previewPlans: [SubscriptionPlan] = [
        SubscriptionPlan(
            id: "$rc_annual",
            title: "Abonnement annuel",
            priceLabel: "99,99 €",
            periodLabel: "par an",
            highlight: "Deux mois offerts",
            isBestValue: true
        ),
        SubscriptionPlan(
            id: "$rc_monthly",
            title: "Abonnement mensuel",
            priceLabel: "9,99 €",
            periodLabel: "par mois"
        )
    ]
}

// MARK: - Bandeau d'état

/// Affiché en tête du tableau de bord pendant l'essai et en lecture seule.
struct SubscriptionBanner: View {

    @Environment(SubscriptionManager.self) private var subscription

    let onTap: () -> Void

    var body: some View {
        if !subscription.isSubscribed {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: subscription.canWrite ? "hourglass" : "lock.fill")
                        .font(.title3)
                        .foregroundStyle(subscription.canWrite ? Color.brand : Color.orange)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.statusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subscription.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionManager.shared)
}
