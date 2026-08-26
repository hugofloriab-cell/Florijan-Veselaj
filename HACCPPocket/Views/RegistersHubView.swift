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
