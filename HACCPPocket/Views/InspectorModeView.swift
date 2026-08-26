//
//  InspectorModeView.swift
//  HACCPPocket
//
//  L'interface remise au contrôleur.
//
//  Rien n'y est modifiable, et ce n'est pas obtenu en désactivant des
//  boutons : il n'y en a pas. On y trouve ce qu'un contrôle demande —
//  l'identité de l'établissement, les registres, les scellés, et le PDF
//  mensuel — et rien d'autre.
//

import SwiftUI
import SwiftData

struct InspectorModeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(InspectorAccess.self) private var access

    @Query private var establishments: [Establishment]
    @Query(sort: \IntegritySeal.sequence, order: .reverse) private var seals: [IntegritySeal]

    @Query private var readings: [TemperatureReading]
    @Query private var products: [TrackedProduct]
    @Query private var deliveries: [DeliveryCheck]
    @Query private var cleaningRecords: [CleaningRecord]
    @Query private var thermalRecords: [ThermalProcessRecord]
    @Query private var oilChecks: [OilCheckRecord]
    @Query private var dishes: [Dish]
    @Query private var documents: [RegulatoryDocument]

    @State private var showsExit = false

    private var establishment: Establishment? { establishments.first }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                registersSection
                sealsSection
                documentsSection
                exitSection
            }
            .navigationTitle("Consultation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Lecture seule", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showsExit) {
                InspectorExitView()
            }
        }
        .tint(.brand)
    }

    // MARK: - En-tête

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                BrandLogo(size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(establishment?.displayName ?? "Établissement non renseigné")
                        .font(.headline)
                    if let siret = establishment?.siret, !siret.isEmpty {
                        Text("SIRET \(siret)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let approval = establishment?.approvalNumber, !approval.isEmpty {
                        Text("Agrément \(approval)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            if let address = establishment?.address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Établissement")
        } footer: {
            if let activatedAt = access.activatedAt {
                Text("Consultation ouverte le \(AppFormatters.dateAndTime(activatedAt)). Aucune donnée ne peut être modifiée depuis cet écran.")
            } else {
                Text("Aucune donnée ne peut être modifiée depuis cet écran.")
            }
        }
    }

    // MARK: - Registres

    private var registersSection: some View {
        Section {
            registerLink("Relevés de température", systemImage: "thermometer.medium", count: readings.count) {
                InspectorTemperatureList()
            }
            registerLink("Produits entamés", systemImage: "shippingbox", count: products.count) {
                InspectorProductList()
            }
            registerLink("Contrôles à réception", systemImage: "truck.box", count: deliveries.count) {
                InspectorDeliveryList()
            }
            registerLink("Opérations de nettoyage", systemImage: "sparkles", count: cleaningRecords.count) {
                InspectorCleaningList()
            }
            registerLink("Process thermiques", systemImage: "thermometer.variable", count: thermalRecords.count) {
                InspectorThermalList()
            }
            registerLink("Bains de friture", systemImage: "drop.triangle", count: oilChecks.count) {
                InspectorOilList()
            }
            registerLink("Carte et allergènes", systemImage: "fork.knife", count: dishes.count) {
                InspectorMenuList()
            }
        } header: {
            Text("Registres")
        }
    }

    private func registerLink<Destination: View>(
        _ title: String,
        systemImage: String,
        count: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                RowIcon(systemImage: systemImage, tint: .brand)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Scellés

    private var sealsSection: some View {
        Section {
            if seals.isEmpty {
                Text("Aucun mois clôturé.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                NavigationLink {
                    IntegrityListView(isReadOnly: true)
                } label: {
                    HStack(spacing: 12) {
                        RowIcon(systemImage: "checkmark.seal", tint: .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scellés mensuels")
                                .font(.subheadline)
                            Text("Dernier : \(seals[0].periodLabel), empreinte \(seals[0].shortDigest)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }

            NavigationLink {
                ReportView()
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "doc.text", tint: .brand)
                    Text("Registre mensuel (PDF)")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Clôtures et export")
        } footer: {
            Text("Chaque clôture enregistre une empreinte des données du mois. La recalculer permet de vérifier qu'aucun enregistrement n'a été modifié depuis.")
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        Section {
            NavigationLink {
                InspectorDocumentList()
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "folder", tint: .brand)
                    Text("Documents réglementaires")
                        .font(.subheadline)
                    Spacer()
                    Text("\(documents.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Documents")
        }
    }

    // MARK: - Sortie

    private var exitSection: some View {
        Section {
            Button {
                showsExit = true
            } label: {
                Label("Quitter le mode consultation", systemImage: "lock.open")
            }
        } footer: {
            Text("Réservé à l'exploitant.")
        }
    }
}

// MARK: - Sortie du mode

struct InspectorExitView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(InspectorAccess.self) private var access

    @State private var code = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Code de sortie", text: $code)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Code")
                } footer: {
                    if failed {
                        Text("Code incorrect.")
                            .foregroundStyle(.red)
                    } else if !access.hasCode {
                        Text("Aucun code n'a été défini : vous pouvez sortir sans en saisir un. Définissez-en un dans les réglages avant de confier l'appareil.")
                    }
                }

                Section {
                    Button {
                        attempt()
                    } label: {
                        Label("Reprendre la main", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Quitter la consultation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func attempt() {
        if access.deactivate(using: code) {
            dismiss()
        } else {
            failed = true
            code = ""
        }
    }
}
