//
//  TemperatureListView.swift
//  HACCPPocket
//
//  Liste des enceintes : dernier relevé, statut du jour, accès à l'historique.
//

import SwiftUI
import SwiftData

struct TemperatureListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]

    @State private var entryTarget: PendingReading?
    @State private var editedEquipment: Equipment?
    @State private var isCreatingEquipment = false
    @State private var showsArchived = false
    @State private var showsPaywall = false

    private var visibleEquipments: [Equipment] {
        equipments.filter { showsArchived || $0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEquipments) { equipment in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            EquipmentDetailView(equipment: equipment)
                        } label: {
                            row(for: equipment)
                        }
                        momentButtons(for: equipment)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            guard subscription.canWrite else { showsPaywall = true; return }
                            entryTarget = PendingReading(
                                equipment: equipment,
                                moment: .suggested()
                            )
                        } label: {
                            Label("Relever", systemImage: "thermometer.medium")
                        }
                        .tint(.teal)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            editedEquipment = equipment
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .tint(.gray)

                        Button {
                            toggleArchive(equipment)
                        } label: {
                            Label(
                                equipment.isActive ? "Archiver" : "Réactiver",
                                systemImage: equipment.isActive ? "archivebox" : "arrow.uturn.backward"
                            )
                        }
                        .tint(equipment.isActive ? .orange : .green)
                    }
                }

                if equipments.contains(where: { !$0.isActive }) {
                    Section {
                        Toggle("Afficher les équipements archivés", isOn: $showsArchived)
                    }
                }
            }
            .navigationTitle("Températures")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if subscription.canWrite {
                            isCreatingEquipment = true
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        Label("Ajouter une enceinte", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if visibleEquipments.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune enceinte", systemImage: "refrigerator")
                    } description: {
                        Text("Ajoutez vos frigos, congélateurs et chambres froides pour suivre leurs températures.")
                    } actions: {
                        Button("Ajouter une enceinte") { isCreatingEquipment = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .sheet(item: $entryTarget) { target in
                TemperatureEntryView(
                    equipment: target.equipment,
                    moment: target.moment,
                    context: modelContext
                )
            }
            .sheet(item: $editedEquipment) { equipment in
                EquipmentEditorView(equipment: equipment)
            }
            .sheet(isPresented: $isCreatingEquipment) {
                EquipmentEditorView(equipment: nil, sortIndex: equipments.count)
            }
        }
    }

    // MARK: - Ligne

    private func row(for equipment: Equipment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(equipment.name, systemImage: equipment.type.systemImage)
                    .font(.headline)
                Spacer()
                if let reading = equipment.latestReading {
                    TemperatureLabel(value: reading.value, isCompliant: reading.isCompliant)
                }
            }

            Text("\(equipment.type.label) — \(equipment.formattedRange)")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .padding(.vertical, 4)
    }

    /// Les pastilles Matin et Soir lancent directement la saisie du relevé
    /// correspondant : c'est le geste le plus fréquent de la journée.
    private func momentButtons(for equipment: Equipment) -> some View {
        HStack(spacing: 8) {
            ForEach(ReadingMoment.dailyRoutine, id: \.self) { moment in
                let done = equipment.hasReading(on: .now, moment: moment)

                Button {
                    guard subscription.canWrite else { showsPaywall = true; return }
                    entryTarget = PendingReading(equipment: equipment, moment: moment)
                } label: {
                    StatusBadge(
                        text: moment.label,
                        color: done ? .green : .teal,
                        systemImage: done ? "checkmark" : moment.systemImage
                    )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    done
                        ? "\(moment.label) déjà relevé pour \(equipment.name), modifier"
                        : "Relever \(moment.label) pour \(equipment.name)"
                )
            }

            if !equipment.isActive {
                StatusBadge(text: "Archivé", color: .orange, systemImage: "archivebox")
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    /// Un équipement n'est jamais supprimé : son historique doit rester
    /// consultable lors d'un contrôle. On l'archive.
    private func toggleArchive(_ equipment: Equipment) {
        equipment.isActive.toggle()
        try? modelContext.save()
    }
}

#Preview {
    TemperatureListView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(SubscriptionManager.shared)
}
