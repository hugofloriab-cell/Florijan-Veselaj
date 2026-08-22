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

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]

    @State private var entryTarget: PendingReading?
    @State private var editedEquipment: Equipment?
    @State private var isCreatingEquipment = false
    @State private var showsArchived = false

    private var visibleEquipments: [Equipment] {
        equipments.filter { showsArchived || $0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEquipments) { equipment in
                    NavigationLink {
                        EquipmentDetailView(equipment: equipment)
                    } label: {
                        row(for: equipment)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
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
                        isCreatingEquipment = true
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

            HStack(spacing: 6) {
                ForEach(ReadingMoment.dailyRoutine, id: \.self) { moment in
                    let done = equipment.hasReading(on: .now, moment: moment)
                    StatusBadge(
                        text: moment.label,
                        color: done ? .green : .secondary,
                        systemImage: done ? "checkmark" : moment.systemImage
                    )
                }

                if !equipment.isActive {
                    StatusBadge(text: "Archivé", color: .orange, systemImage: "archivebox")
                }
            }
        }
        .padding(.vertical, 4)
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
}
