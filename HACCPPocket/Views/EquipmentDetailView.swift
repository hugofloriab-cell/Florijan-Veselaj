//
//  EquipmentDetailView.swift
//  HACCPPocket
//
//  Historique d'une enceinte : courbe des 14 derniers jours et journal des
//  relevés, avec les écarts et leurs actions correctives.
//

import SwiftUI
import SwiftData
import Charts

struct EquipmentDetailView: View {

    @Environment(\.modelContext) private var modelContext

    let equipment: Equipment

    @State private var entryTarget: PendingReading?
    @State private var editedReading: TemperatureReading?
    @State private var isEditingEquipment = false

    /// Fenêtre d'analyse de la courbe.
    private let chartWindowDays = 14

    private var chartReadings: [TemperatureReading] {
        guard let start = Calendar.current.date(byAdding: .day, value: -chartWindowDays, to: .now) else {
            return []
        }
        return equipment.readings
            .filter { $0.recordedAt >= start }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var recentReadings: [TemperatureReading] {
        equipment.readings
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(60)
            .map { $0 }
    }

    var body: some View {
        List {
            infoSection
            chartSection
            historySection
        }
        .navigationTitle(equipment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        entryTarget = PendingReading(equipment: equipment, moment: .suggested())
                    } label: {
                        Label("Nouveau relevé", systemImage: "plus.circle")
                    }
                    Button {
                        isEditingEquipment = true
                    } label: {
                        Label("Modifier l'enceinte", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $entryTarget) { target in
            GuidedTemperatureInputView(
                equipment: target.equipment,
                moment: target.moment,
                context: modelContext
            )
        }
        .sheet(item: $editedReading) { reading in
            GuidedTemperatureInputView(
                equipment: equipment,
                moment: reading.moment,
                reading: reading,
                context: modelContext
            )
        }
        .sheet(isPresented: $isEditingEquipment) {
            EquipmentEditorView(equipment: equipment)
        }
    }

    // MARK: - Fiche

    private var infoSection: some View {
        Section {
            InfoRow(label: "Type", value: equipment.type.label, systemImage: equipment.type.systemImage)
            InfoRow(label: "Plage acceptée", value: equipment.formattedRange, systemImage: "thermometer.variable")
            if !equipment.location.isEmpty {
                InfoRow(label: "Emplacement", value: equipment.location, systemImage: "mappin.and.ellipse")
            }
            if let latest = equipment.latestReading {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("Dernier relevé")
                    Spacer()
                    TemperatureLabel(value: latest.value, isCompliant: latest.isCompliant)
                }
                InfoRow(
                    label: "Effectué le",
                    value: AppFormatters.dateAndTime(latest.recordedAt),
                    systemImage: "calendar"
                )
            }
        }
    }

    // MARK: - Courbe

    @ViewBuilder
    private var chartSection: some View {
        Section("14 derniers jours") {
            if chartReadings.count < 2 {
                Text("Pas encore assez de relevés pour tracer une courbe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    // Les deux bornes réglementaires, en pointillés : tout point
                    // qui sort de cette bande est une non-conformité.
                    RuleMark(y: .value("Minimum", equipment.acceptedRange.lowerBound))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    RuleMark(y: .value("Maximum", equipment.acceptedRange.upperBound))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(chartReadings) { reading in
                        LineMark(
                            x: .value("Date", reading.recordedAt),
                            y: .value("Température", reading.value)
                        )
                        .foregroundStyle(.brand)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Date", reading.recordedAt),
                            y: .value("Température", reading.value)
                        )
                        .foregroundStyle(reading.isCompliant ? Color.brand : Color.red)
                        .symbolSize(reading.isCompliant ? 20 : 60)
                    }
                }
                .chartYAxisLabel("°C")
                .frame(height: 200)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Journal

    @ViewBuilder
    private var historySection: some View {
        if recentReadings.isEmpty {
            Section("Journal") {
                Text("Aucun relevé enregistré.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Journal") {
                ForEach(recentReadings) { reading in
                    Button {
                        editedReading = reading
                    } label: {
                        readingRow(reading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func readingRow(_ reading: TemperatureReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: reading.moment.systemImage)
                    .foregroundStyle(reading.moment.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppFormatters.relativeDay(reading.recordedAt))
                        .font(.subheadline)
                    Text("\(reading.moment.label) · \(AppFormatters.time(reading.recordedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TemperatureLabel(value: reading.value, isCompliant: reading.isCompliant)
            }

            if !reading.isCompliant {
                if reading.correctiveAction.isEmpty {
                    Label("Action corrective manquante", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(reading.correctiveAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !reading.operatorName.isEmpty {
                Text("Relevé par \(reading.operatorName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
