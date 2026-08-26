//
//  DashboardView.swift
//  HACCPPocket
//
//  Écran d'accueil : quatre tuiles qui se lisent d'un coup d'œil, les
//  anomalies en évidence, puis ce qu'il reste à saisir.
//
//  Toute la logique vient de `DashboardViewModel`, recalculé à chaque
//  rafraîchissement des `@Query`.
//

import SwiftUI
import SwiftData

struct DashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(AppRouter.self) private var router

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query private var products: [TrackedProduct]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]
    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse) private var deliveries: [DeliveryCheck]

    @State private var entryTarget: PendingReading?
    @State private var showsPaywall = false
    @State private var editedProduct: TrackedProduct?
    @State private var cleaningViewModel: CleaningPlanViewModel?

    private var dashboard: DashboardViewModel {
        DashboardViewModel(
            equipments: equipments,
            products: products,
            cleaningTasks: cleaningTasks
        )
    }

    /// Grille adaptative : deux tuiles sur iPhone, trois ou quatre sur iPad,
    /// sans code conditionnel.
    private let columns = [GridItem(.adaptive(minimum: 158), spacing: DS.gutter)]

    /// Grille des raccourcis : des pavés nettement plus petits que les
    /// tuiles de synthèse, pour qu'on distingue au premier coup d'œil ce qui
    /// informe de ce qui emmène ailleurs.
    private let shortcutColumns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    /// Change à chaque tâche terminée, ce qui relance l'animation.
    @State private var celebration: UUID?
    @State private var celebrationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                    Text(AppFormatters.sentenceCased(AppFormatters.longDay(.now)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Un problème de stockage passe avant tout le reste :
                    // l'utilisateur doit le voir au premier lancement.
                    StoreStatusBanner()

                    if !subscription.isSubscribed {
                        subscriptionCard
                    }

                    tilesSection
                    shortcutsSection
                    alertsSection
                    pendingReadingsSection
                    urgentProductsSection
                    cleaningSection
                    registersSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                // Sur un grand écran, une colonne de texte pleine largeur
                // devient illisible : on la borne et on la centre.
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .successBurst(trigger: celebration, message: celebrationMessage)
            .navigationTitle("Aujourd'hui")
            .sheet(isPresented: $showsPaywall) { PaywallView() }
            .sheet(item: $editedProduct) { product in
                ProductFormView(product: product, context: modelContext)
            }
            .sheet(item: $entryTarget) { target in
                GuidedTemperatureInputView(
                    equipment: target.equipment,
                    moment: target.moment,
                    context: modelContext
                )
            }
            .overlay {
                if equipments.isEmpty {
                    ContentUnavailableView(
                        "Aucun équipement",
                        systemImage: "refrigerator",
                        description: Text("Ajoutez vos enceintes dans l'onglet Températures pour démarrer le suivi.")
                    )
                }
            }
            .task {
                if cleaningViewModel == nil {
                    cleaningViewModel = CleaningPlanViewModel(context: modelContext)
                }
            }
        }
    }

    // MARK: - Bandeau d'abonnement

    private var subscriptionCard: some View {
        SubscriptionBanner { showsPaywall = true }
            .padding(14)
            .cardSurface()
    }

    // MARK: - Tuiles

    private var tilesSection: some View {
        LazyVGrid(columns: columns, spacing: DS.gutter) {
            Button {
                router.show(.temperatures)
            } label: {
                MetricTile(
                    title: "Relevés du jour",
                    value: "\(dashboard.completedReadingsToday)/\(dashboard.expectedReadingsToday)",
                    systemImage: "thermometer.medium",
                    tint: dashboard.isReadingRoutineComplete ? .green : .orange,
                    progress: dashboard.readingProgress,
                    needsAttention: !dashboard.isReadingRoutineComplete
                )
            }
            .buttonStyle(.plain)

            Button {
                router.show(.products)
            } label: {
                MetricTile(
                    title: "Produits entamés",
                    value: "\(dashboard.openProductsCount)",
                    caption: urgentProductsCaption,
                    systemImage: "shippingbox.fill",
                    tint: dashboard.expiredProducts.isEmpty ? .brand : .red,
                    needsAttention: !dashboard.expiredProducts.isEmpty
                )
            }
            .buttonStyle(.plain)

            Button {
                router.show(.cleaning)
            } label: {
                MetricTile(
                    title: "Nettoyages à faire",
                    value: "\(dashboard.dueCleaningTasks.count)",
                    caption: dashboard.overdueCleaningTasks.isEmpty
                        ? "À jour"
                        : "\(dashboard.overdueCleaningTasks.count) en retard",
                    systemImage: "sparkles",
                    tint: dashboard.overdueCleaningTasks.isEmpty ? .brand : .orange,
                    needsAttention: !dashboard.dueCleaningTasks.isEmpty
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                DeliveryListView()
            } label: {
                MetricTile(
                    title: "Réceptions du jour",
                    value: "\(deliveriesToday.count)",
                    caption: complianceCaption,
                    systemImage: "truck.box.fill",
                    tint: .brand
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var urgentProductsCaption: String {
        let urgent = dashboard.expiredProducts.count + dashboard.expiringProducts.count
        return urgent == 0 ? "Aucun urgent" : "\(urgent) à traiter"
    }

    private var deliveriesToday: [DeliveryCheck] {
        deliveries.filter { Calendar.current.isDateInToday($0.receivedAt) }
    }

    private var complianceCaption: String {
        guard let rate = dashboard.complianceRate() else { return "Pas d'historique" }
        return "Conformité \(rate.formatted(.percent.precision(.fractionLength(0)).locale(AppFormatters.locale)))"
    }

    // MARK: - Alertes

    @ViewBuilder
    private var alertsSection: some View {
        if dashboard.alerts.isEmpty {
            HStack(spacing: 12) {
                RowIcon(systemImage: "checkmark.seal.fill", tint: .green)
                Text("Aucune anomalie en cours")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(14)
            .cardSurface()
        } else {
            VStack(alignment: .leading, spacing: DS.gutter) {
                SectionTitle(text: "Alertes")
                ForEach(dashboard.alerts) { alert in
                    AlertCard(alert: alert)
                }
            }
        }
    }

    // MARK: - Relevés à saisir

    @ViewBuilder
    private var pendingReadingsSection: some View {
        if !dashboard.pendingReadings.isEmpty {
            VStack(alignment: .leading, spacing: DS.gutter) {
                SectionTitle(text: "Relevés à saisir")

                ForEach(dashboard.pendingReadings) { pending in
                    Button {
                        if subscription.canWrite {
                            entryTarget = pending
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        ActionRow(
                            title: pending.equipment.name,
                            subtitle: pending.equipment.formattedRange,
                            systemImage: pending.moment.systemImage,
                            tint: pending.moment.accentColor,
                            trailingText: pending.moment.label
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Produits à traiter

    @ViewBuilder
    private var urgentProductsSection: some View {
        let urgent = dashboard.expiredProducts + dashboard.expiringProducts
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: DS.gutter) {
                SectionTitle(text: "Produits à traiter") {
                    router.show(.products)
                }

                ForEach(urgent) { product in
                    Button {
                        if subscription.canWrite {
                            editedProduct = product
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        ActionRow(
                            title: product.name,
                            subtitle: product.storage.label,
                            systemImage: product.urgency().systemImage,
                            tint: product.urgency().color,
                            trailingText: product.remainingLabel()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Nettoyage

    @ViewBuilder
    private var cleaningSection: some View {
        if !dashboard.dueCleaningTasks.isEmpty {
            VStack(alignment: .leading, spacing: DS.gutter) {
                SectionTitle(text: "Nettoyage à réaliser") {
                    router.show(.cleaning)
                }

                ForEach(Array(dashboard.dueCleaningTasks.prefix(4))) { task in
                    Button {
                        completeCleaning(task)
                    } label: {
                        ActionRow(
                            title: task.title,
                            subtitle: task.zone.isEmpty ? task.frequency.label : task.zone,
                            systemImage: "circle",
                            tint: task.isOverdue() ? .orange : .brand,
                            trailingText: task.isOverdue() ? "En retard" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pointer \(task.title)")
                }
            }
        }
    }

    // MARK: - Raccourcis

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: DS.gutter) {
            SectionTitle(text: "Accès rapide")

            LazyVGrid(columns: shortcutColumns, spacing: 10) {
                // Les trois premiers sont des onglets : on bascule plutôt
                // que d'empiler un écran par-dessus l'accueil.
                tabShortcut(.temperatures, title: "Températures", systemImage: "thermometer.medium",
                            badge: dashboard.pendingReadings.count)
                tabShortcut(.products, title: "Produits", systemImage: "shippingbox",
                            badge: dashboard.expiredProducts.count)
                tabShortcut(.cleaning, title: "Nettoyage", systemImage: "sparkles",
                            badge: dashboard.dueCleaningTasks.count)

                pushShortcut("Réception", systemImage: "truck.box", tint: .teal) {
                    DeliveryListView()
                }
                pushShortcut("Registres", systemImage: "folder", tint: .indigo) {
                    RegistersHubView()
                }
                pushShortcut("Ma carte", systemImage: "fork.knife", tint: .pink) {
                    MenuListView()
                }
                pushShortcut("Historique", systemImage: "clock.arrow.circlepath", tint: .cyan) {
                    HistoryView()
                }
                pushShortcut("Registre mensuel", systemImage: "doc.text", tint: .purple) {
                    ReportView()
                }
            }
        }
    }

    private func tabShortcut(
        _ destination: AppRouter.Destination,
        title: String,
        systemImage: String,
        badge: Int = 0
    ) -> some View {
        Button {
            router.show(destination)
        } label: {
            ShortcutTile(
                title: title,
                systemImage: systemImage,
                tint: destination.tint,
                badgeCount: badge
            )
        }
        .buttonStyle(.plain)
    }

    /// Les écrans de registre n'apportent pas leur propre pile de
    /// navigation : ils s'empilent proprement sur l'accueil.
    private func pushShortcut<Destination: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ShortcutTile(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Registres

    private var registersSection: some View {
        VStack(alignment: .leading, spacing: DS.gutter) {
            SectionTitle(text: "Registres")

            NavigationLink {
                RegistersHubView()
            } label: {
                ActionRow(
                    title: "Tous les registres",
                    subtitle: "Réception, process, huiles, nuisibles, formations",
                    systemImage: "folder"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MenuListView()
            } label: {
                ActionRow(
                    title: "Ma carte et les allergènes",
                    subtitle: "Fiche à afficher en salle",
                    systemImage: "fork.knife"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                HistoryView()
            } label: {
                ActionRow(
                    title: "Historique",
                    subtitle: "Retrouver un lot, une date, un opérateur",
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ReportView()
            } label: {
                ActionRow(
                    title: "Registre mensuel",
                    subtitle: "PDF prêt à présenter, export tableur",
                    systemImage: "doc.text"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    /// Pointe une opération depuis l'accueil, sans passer par l'onglet Nettoyage.
    private func completeCleaning(_ task: CleaningTask) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }

        guard cleaningViewModel?.complete(task) == true else { return }

        celebrationMessage = remainingCleaningMessage()
        celebration = UUID()
    }

    /// Le message change selon ce qu'il reste : « il en reste deux » motive
    /// bien mieux qu'un « enregistré » identique à chaque fois.
    ///
    /// Le décompte passe par le ViewModel de nettoyage plutôt que par le
    /// tableau de bord : celui-ci est reconstruit à partir des `@Query`, qui
    /// ne se sont pas encore rafraîchies à cet instant.
    private func remainingCleaningMessage() -> String {
        let remaining = cleaningViewModel?.remainingCount(from: cleaningTasks) ?? 0

        switch remaining {
        case 0:  return "Plan de nettoyage terminé"
        case 1:  return "Encore une opération"
        default: return "Encore \(remaining) opérations"
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(SubscriptionManager.shared)
        .environment(AppRouter())
}
