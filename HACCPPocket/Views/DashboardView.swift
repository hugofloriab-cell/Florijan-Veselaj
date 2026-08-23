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
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aujourd'hui")
            .sheet(isPresented: $showsPaywall) { PaywallView() }
            .sheet(item: $editedProduct) { product in
                ProductFormView(product: product, context: modelContext)
            }
            .sheet(item: $entryTarget) { target in
                TemperatureEntryView(
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
        cleaningViewModel?.complete(task)
    }
}

#Preview {
    DashboardView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(SubscriptionManager.shared)
        .environment(AppRouter())
}
