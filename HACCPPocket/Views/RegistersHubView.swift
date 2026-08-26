//
//  RegistersHubView.swift
//  HACCPPocket
//
//  Point d'entrée unique vers les registres qui ne se tiennent pas au
//  quotidien : réception, process thermiques, huiles, nuisibles, formations.
//

import SwiftUI
import SwiftData

struct RegistersHubView: View {

    @Query private var thermalRecords: [ThermalProcessRecord]
    @Query private var oilChecks: [OilCheckRecord]
    @Query private var pestVisits: [PestControlVisit]
    @Query private var trainings: [StaffTraining]
    @Query private var deliveries: [DeliveryCheck]
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

    /// Opérations thermiques encore ouvertes : c'est l'information la plus
    /// urgente de cet écran, un refroidissement oublié devient non conforme.
    private var runningProcesses: Int {
        thermalRecords.filter { !$0.isFinished }.count
    }

    private var expiringTrainings: Int {
        trainings.filter { $0.isExpired() || $0.isExpiringSoon() }.count
    }

    private var overduePest: Bool {
        pestVisits.contains { $0.isNextVisitOverdue() }
    }

    /// Plats dont la fiche allergènes n'a jamais été remplie.
    private var incompleteDishes: Int {
        dishes.filter { $0.isAvailable && $0.needsAllergenReview }.count
    }

    /// Échantillons dont le délai est écoulé : ils encombrent le frigo sans
    /// plus rien prouver.
    private var samplesToDiscard: Int {
        samples.filter(\.needsAction).count
    }

    private var thawingsExpired: Int {
        thawings.filter { $0.isExpired() }.count
    }

    private var incompleteBeef: Int {
        beefOrigins.filter { !$0.isComplete }.count
    }

    private var medicalToHandle: Int {
        medicalRecords.filter(\.needsAction).count
    }

    private var hygieneCheckedToday: Bool {
        let calendar = Calendar.current
        return hygieneChecks.contains { calendar.isDateInToday($0.checkedAt) }
    }

    private var documentsToHandle: Int {
        documents.filter(\.needsAction).count
    }

    private var maintenanceToHandle: Int {
        maintenance.filter(\.needsAction).count
    }

    private var openRecalls: Int {
        recalls.filter { !$0.isClosed }.count
    }

    private var analysesToHandle: Int {
        analyses.filter(\.needsAction).count
    }

    private var waterToHandle: Int {
        waterControls.filter(\.needsAction).count
    }

    private var missingSlips: Int {
        oilCollections.filter(\.isIncomplete).count
    }

    private var oilToChange: Int {
        oilChecks.filter(\.needsAction).count
    }

    var body: some View {
        List {
            Section("Suivi quotidien") {
                NavigationLink {
                    DeliveryListView()
                } label: {
                    registerRow(
                        "Contrôles à réception",
                        detail: "Températures et conformité des livraisons",
                        systemImage: "shippingbox",
                        count: deliveries.count
                    )
                }

                NavigationLink {
                    ThermalProcessListView()
                } label: {
                    registerRow(
                        "Refroidissement et remise en température",
                        detail: runningProcesses > 0
                            ? "\(runningProcesses) opération(s) en cours"
                            : "Suivi chronométré des process",
                        systemImage: "thermometer.variable",
                        badge: runningProcesses > 0 ? "\(runningProcesses) en cours" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    CleaningProductListView()
                } label: {
                    registerRow(
                        "Produits d'entretien",
                        detail: "Dosages, temps de contact, fiches de sécurité",
                        systemImage: "bubbles.and.sparkles",
                        count: cleaningProducts.count
                    )
                }

                NavigationLink {
                    OilCheckListView()
                } label: {
                    registerRow(
                        "Huiles de friture",
                        detail: "Composés polaires et changements de bain",
                        systemImage: "drop.triangle",
                        badge: oilToChange > 0 ? "\(oilToChange) à traiter" : nil,
                        badgeColor: .red
                    )
                }
            }

            Section("Préparations") {
                NavigationLink {
                    ThawingListView()
                } label: {
                    registerRow(
                        "Décongélation",
                        detail: "DLC résiduelle après décongélation",
                        systemImage: "snowflake.slash",
                        count: thawings.count,
                        badge: thawingsExpired > 0 ? "\(thawingsExpired) à retirer" : nil,
                        badgeColor: .red
                    )
                }

                NavigationLink {
                    SanitizingFreezeListView()
                } label: {
                    registerRow(
                        "Poisson servi cru",
                        detail: "Traitement assainissant −20 °C / 24 h",
                        systemImage: "fish",
                        count: sanitizing.count
                    )
                }

                NavigationLink {
                    FoodSampleListView()
                } label: {
                    registerRow(
                        "Plats témoins",
                        detail: "Prélèvements conservés 5 jours",
                        systemImage: "takeoutbag.and.cup.and.straw",
                        count: samples.count,
                        badge: samplesToDiscard > 0 ? "\(samplesToDiscard) à éliminer" : nil,
                        badgeColor: .orange
                    )
                }
            }

            Section("Information du consommateur") {
                NavigationLink {
                    BeefOriginListView()
                } label: {
                    registerRow(
                        "Origine viande bovine",
                        detail: "Naissance, élevage, abattage",
                        systemImage: "text.badge.checkmark",
                        count: beefOrigins.count,
                        badge: incompleteBeef > 0 ? "\(incompleteBeef) à compléter" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    MenuListView()
                } label: {
                    registerRow(
                        "Ma carte et les allergènes",
                        detail: dishes.isEmpty
                            ? "Vos plats et leurs allergènes déclarés"
                            : "\(dishes.count) plat(s) à la carte",
                        systemImage: "fork.knife",
                        badge: incompleteDishes > 0 ? "\(incompleteDishes) à compléter" : nil,
                        badgeColor: .orange
                    )
                }
            }

            Section("Personnel") {
                NavigationLink {
                    ShiftHygieneListView()
                } label: {
                    registerRow(
                        "Prise de poste",
                        detail: "Mains, tenue, bijoux, symptômes",
                        systemImage: "hands.and.sparkles",
                        badge: hygieneCheckedToday ? nil : "Pas de contrôle aujourd'hui",
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    MedicalFitnessListView()
                } label: {
                    registerRow(
                        "Suivi médical",
                        detail: "Attestations et avis d'aptitude",
                        systemImage: "stethoscope",
                        count: medicalRecords.count,
                        badge: medicalToHandle > 0 ? "\(medicalToHandle) à traiter" : nil,
                        badgeColor: .orange
                    )
                }
            }

            Section("Suivi périodique") {
                NavigationLink {
                    PestControlListView()
                } label: {
                    registerRow(
                        "Lutte contre les nuisibles",
                        detail: "Visites du prestataire et constats",
                        systemImage: "ant",
                        badge: overduePest ? "Visite en retard" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    StaffTrainingListView()
                } label: {
                    registerRow(
                        "Formations du personnel",
                        detail: "Attestations d'hygiène alimentaire",
                        systemImage: "graduationcap",
                        badge: expiringTrainings > 0 ? "\(expiringTrainings) à renouveler" : nil,
                        badgeColor: .orange
                    )
                }
            }

            Section("Documents et incidents") {
                NavigationLink {
                    DocumentArchiveListView()
                } label: {
                    registerRow(
                        "Documents réglementaires",
                        detail: "Plan de maîtrise sanitaire, contrats, attestations",
                        systemImage: "folder.badge.person.crop",
                        count: documents.count,
                        badge: documentsToHandle > 0 ? "\(documentsToHandle) à traiter" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    MaintenanceListView()
                } label: {
                    registerRow(
                        "Carnet d'entretien",
                        detail: "Pannes, entretiens, étalonnage des sondes",
                        systemImage: "wrench.and.screwdriver",
                        count: maintenance.count,
                        badge: maintenanceToHandle > 0 ? "\(maintenanceToHandle) à traiter" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    LabAnalysisListView()
                } label: {
                    registerRow(
                        "Analyses de laboratoire",
                        detail: "Surfaces, denrées, eau",
                        systemImage: "flask",
                        count: analyses.count,
                        badge: analysesToHandle > 0 ? "\(analysesToHandle) à traiter" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    WaterControlListView()
                } label: {
                    registerRow(
                        "Eau et réseau intérieur",
                        detail: "Chlore, purges, filtres, adoucisseur",
                        systemImage: "drop",
                        count: waterControls.count,
                        badge: waterToHandle > 0 ? "\(waterToHandle) à traiter" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    WasteOilListView()
                } label: {
                    registerRow(
                        "Huiles usagées",
                        detail: "Bordereaux de collecte",
                        systemImage: "arrow.3.trianglepath",
                        count: oilCollections.count,
                        badge: missingSlips > 0 ? "\(missingSlips) sans bordereau" : nil,
                        badgeColor: .orange
                    )
                }

                NavigationLink {
                    ProductRecallListView()
                } label: {
                    registerRow(
                        "Retrait et rappel",
                        detail: "Lots contaminés signalés par un fournisseur",
                        systemImage: "exclamationmark.octagon",
                        count: recalls.count,
                        badge: openRecalls > 0 ? "\(openRecalls) en cours" : nil,
                        badgeColor: .red
                    )
                }
            }

            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    registerRow(
                        "Historique complet",
                        detail: "Rechercher dans tous les registres",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                NavigationLink {
                    ReportView()
                } label: {
                    registerRow(
                        "Registre mensuel",
                        detail: "PDF prêt à présenter, export tableur",
                        systemImage: "doc.text"
                    )
                }

                NavigationLink {
                    BackupView()
                } label: {
                    registerRow(
                        "Sauvegarde",
                        detail: "Exporter ou restaurer toutes les données",
                        systemImage: "externaldrive"
                    )
                }
            } footer: {
                Text("Le registre mensuel rassemble l'ensemble de ces enregistrements en un seul document. La sauvegarde, elle, met vos données à l'abri de la perte de l'appareil.")
            }
        }
        .navigationTitle("Registres")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func registerRow(
        _ title: String,
        detail: String,
        systemImage: String,
        count: Int? = nil,
        badge: String? = nil,
        badgeColor: Color = .brand
    ) -> some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: systemImage, tint: badge == nil ? .brand : badgeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let badge {
                StatusBadge(text: badge, color: badgeColor)
            } else if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
