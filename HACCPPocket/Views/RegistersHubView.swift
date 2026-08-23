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

            Section("Information du consommateur") {
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
