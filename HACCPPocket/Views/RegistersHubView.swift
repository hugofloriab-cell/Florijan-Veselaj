//
//  RegistersHubView.swift
//  HACCPPocket
//
//  La page Registres : tout ce que l'application sait tenir, en pavés.
//
//  L'accueil répond à « qu'est-ce que je dois faire maintenant ». Cette
//  page-ci répond à « où est-ce que je note ça ». Deux questions différentes,
//  deux écrans — et celui-ci vient juste derrière l'accueil, parce que c'est
//  le point de départ de tout ce qui n'est pas quotidien.
//
//  Les pastilles rouges ne sont pas décoratives : elles portent le nombre de
//  choses en attente dans chaque registre, ce qui permet de repérer d'un coup
//  d'œil ce qui traîne sans ouvrir quoi que ce soit.
//

import SwiftUI
import SwiftData

struct RegistersHubView: View {

    @Environment(RoleSession.self) private var roles
    @Environment(AppRouter.self) private var router

    // Chaque compteur alimente une pastille : c'est le seul intérêt de ces
    // requêtes ici, les écrans concernés font leur propre travail.
    @Query private var deliveries: [DeliveryCheck]
    @Query private var thermalRecords: [ThermalProcessRecord]
    @Query private var oilChecks: [OilCheckRecord]
    @Query private var pestVisits: [PestControlVisit]
    @Query private var trainings: [StaffTraining]
    @Query private var dishes: [Dish]
    @Query private var thawings: [ThawingRecord]
    @Query private var samples: [FoodSample]
    @Query private var sanitizing: [SanitizingFreezeRecord]
    @Query private var beefOrigins: [BeefOriginRecord]
    @Query private var hygieneChecks: [ShiftHygieneCheck]
    @Query private var medicalRecords: [MedicalFitnessRecord]
    @Query private var cleaningProducts: [CleaningProduct]
    @Query private var documents: [RegulatoryDocument]
    @Query private var maintenance: [EquipmentMaintenance]
    @Query private var recalls: [ProductRecall]
    @Query private var analyses: [LabAnalysis]
    @Query private var waterControls: [WaterControl]
    @Query private var oilCollections: [WasteOilCollection]

    @State private var showsSettings = false

    /// Même grille que les raccourcis de l'accueil : l'utilisateur reconnaît
    /// le format avant de lire quoi que ce soit.
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                    dailySection
                    preparationsSection
                    controlsSection
                    staffSection
                    consumerSection
                    documentsSection
                    exportSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Registres")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(showsDoneButton: true)
            }
        }
    }

    // MARK: - Sections

    private var dailySection: some View {
        group("Au quotidien") {
            tabTile(.temperatures, title: "Températures", systemImage: "thermometer.medium")
            tabTile(.products, title: "Produits entamés", systemImage: "shippingbox")
            tabTile(.cleaning, title: "Nettoyage", systemImage: "sparkles")

            tile("Réception", systemImage: "truck.box", tint: .teal) {
                DeliveryListView()
            }
        }
    }

    private var preparationsSection: some View {
        group("Préparations") {
            tile(
                "Refroidissement",
                systemImage: "thermometer.variable",
                tint: .purple,
                badge: runningProcesses
            ) {
                ThermalProcessListView()
            }
            tile(
                "Décongélation",
                systemImage: "snowflake.slash",
                tint: .cyan,
                badge: expiredThawings
            ) {
                ThawingListView()
            }
            tile(
                "Poisson cru",
                systemImage: "fish",
                tint: .indigo
            ) {
                SanitizingFreezeListView()
            }
            tile(
                "Plats témoins",
                systemImage: "takeoutbag.and.cup.and.straw",
                tint: .brown,
                badge: samplesToDiscard
            ) {
                FoodSampleListView()
            }
        }
    }

    private var controlsSection: some View {
        group("Contrôles") {
            tile(
                "Huiles de friture",
                systemImage: "drop.triangle",
                tint: .yellow,
                badge: oilToChange
            ) {
                OilCheckListView()
            }
            tile(
                "Produits d'entretien",
                systemImage: "bubbles.and.sparkles",
                tint: .mint
            ) {
                CleaningProductListView()
            }
            tile(
                "Analyses",
                systemImage: "flask",
                tint: .pink,
                badge: analysesToHandle
            ) {
                LabAnalysisListView()
            }
            tile(
                "Eau et réseau",
                systemImage: "drop",
                tint: .blue,
                badge: waterToHandle
            ) {
                WaterControlListView()
            }
        }
    }

    private var staffSection: some View {
        group("Personnel") {
            tile(
                "Prise de poste",
                systemImage: "hands.and.sparkles",
                tint: .green,
                badge: hygieneCheckedToday ? 0 : 1
            ) {
                ShiftHygieneListView()
            }
            tile(
                "Suivi médical",
                systemImage: "stethoscope",
                tint: .red,
                badge: medicalToHandle
            ) {
                MedicalFitnessListView()
            }
            tile(
                "Formations",
                systemImage: "graduationcap",
                tint: .indigo,
                badge: expiringTrainings
            ) {
                StaffTrainingListView()
            }
        }
    }

    private var consumerSection: some View {
        group("Information du client") {
            tile(
                "Ma carte",
                systemImage: "fork.knife",
                tint: .pink,
                badge: incompleteDishes
            ) {
                MenuListView()
            }
            tile(
                "Origine des viandes",
                systemImage: "text.badge.checkmark",
                tint: .brown,
                badge: incompleteBeef
            ) {
                BeefOriginListView()
            }
        }
    }

    private var documentsSection: some View {
        group("Documents et incidents") {
            tile(
                "Documents",
                systemImage: "folder",
                tint: .indigo,
                badge: documentsToHandle
            ) {
                DocumentArchiveListView()
            }
            tile(
                "Photos",
                systemImage: "photo.on.rectangle.angled",
                tint: .purple
            ) {
                PhotoLibraryView()
            }
            tile(
                "Nuisibles",
                systemImage: "ant",
                tint: .orange,
                badge: overduePest ? 1 : 0
            ) {
                PestControlListView()
            }
            tile(
                "Carnet d'entretien",
                systemImage: "wrench.and.screwdriver",
                tint: .gray,
                badge: maintenanceToHandle
            ) {
                MaintenanceListView()
            }
            tile(
                "Huiles usagées",
                systemImage: "arrow.3.trianglepath",
                tint: .yellow,
                badge: missingSlips
            ) {
                WasteOilListView()
            }
            tile(
                "Retrait et rappel",
                systemImage: "exclamationmark.octagon",
                tint: .red,
                badge: openRecalls
            ) {
                ProductRecallListView()
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: DS.gutter) {
            SectionTitle(text: "Sortir les registres")

            LazyVGrid(columns: columns, spacing: 10) {
                tile("Historique", systemImage: "clock.arrow.circlepath", tint: .cyan) {
                    HistoryView()
                }
                tile("Registre mensuel", systemImage: "doc.text", tint: .purple) {
                    ReportView()
                }

                if roles.role.canAdminister {
                    tile("Intégrité", systemImage: "checkmark.seal", tint: .green) {
                        IntegrityListView()
                    }
                    tile("Sauvegarde", systemImage: "externaldrive", tint: .gray) {
                        BackupView()
                    }
                }

                Button {
                    showsSettings = true
                } label: {
                    ShortcutTile(title: "Réglages", systemImage: "gearshape", tint: .secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Le registre mensuel rassemble tous ces enregistrements en un seul document, prêt à présenter. Les photos n'y figurent pas : elles s'impriment à part, depuis la page Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Assemblage

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.gutter) {
            SectionTitle(text: title)
            LazyVGrid(columns: columns, spacing: 10) {
                content()
            }
        }
    }

    /// Les trois écrans d'onglet apportent leur propre pile de navigation :
    /// les empiler ici produirait deux barres de navigation superposées et
    /// aucun retour possible. On bascule donc d'onglet.
    private func tabTile(
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

    /// Les écrans de registre n'ont pas leur propre pile de navigation : ils
    /// s'empilent proprement ici. Les trois écrans d'onglet — températures,
    /// produits, nettoyage — en ont une, mais l'empilement reste correct
    /// depuis cette page, qui n'est pas leur onglet.
    private func tile<Destination: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        badge: Int = 0,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ShortcutTile(
                title: title,
                systemImage: systemImage,
                tint: tint,
                badgeCount: badge
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compteurs d'attention

    private var runningProcesses: Int {
        thermalRecords.filter { !$0.isFinished }.count
    }

    private var expiredThawings: Int {
        thawings.filter { $0.isExpired() }.count
    }

    private var samplesToDiscard: Int {
        samples.filter(\.needsAction).count
    }

    private var oilToChange: Int {
        oilChecks.filter(\.needsAction).count
    }

    private var analysesToHandle: Int {
        analyses.filter(\.needsAction).count
    }

    private var waterToHandle: Int {
        waterControls.filter(\.needsAction).count
    }

    private var hygieneCheckedToday: Bool {
        let calendar = Calendar.current
        return hygieneChecks.contains { calendar.isDateInToday($0.checkedAt) }
    }

    private var medicalToHandle: Int {
        medicalRecords.filter(\.needsAction).count
    }

    private var expiringTrainings: Int {
        trainings.filter { $0.isExpired() || $0.isExpiringSoon() }.count
    }

    private var incompleteDishes: Int {
        dishes.filter { $0.isAvailable && $0.needsAllergenReview }.count
    }

    /// Seules les viandes réellement proposées comptent : celles retirées de
    /// la carte n'ont pas à figurer sur l'affichage en salle.
    private var incompleteBeef: Int {
        beefOrigins.filter { $0.isOnMenu && !$0.isComplete }.count
    }

    private var documentsToHandle: Int {
        documents.filter(\.needsAction).count
    }

    private var overduePest: Bool {
        pestVisits.contains { $0.isNextVisitOverdue() }
    }

    private var maintenanceToHandle: Int {
        maintenance.filter(\.needsAction).count
    }

    private var missingSlips: Int {
        oilCollections.filter(\.isIncomplete).count
    }

    private var openRecalls: Int {
        recalls.filter { !$0.isClosed }.count
    }
}

#Preview {
    RegistersHubView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(SubscriptionManager.shared)
        .environment(RoleSession.shared)
        .environment(AppRouter())
}
