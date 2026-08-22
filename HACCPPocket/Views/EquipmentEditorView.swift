//
//  EquipmentEditorView.swift
//  HACCPPocket
//
//  Création et modification d'une enceinte. Choisir un type pré-remplit la
//  plage réglementaire recommandée, que l'utilisateur reste libre d'ajuster.
//

import SwiftUI
import SwiftData

struct EquipmentEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let equipment: Equipment?
    private let sortIndex: Int

    @State private var name: String
    @State private var type: EquipmentType
    @State private var location: String
    @State private var minText: String
    @State private var maxText: String
    @State private var isActive: Bool

    /// `equipment` à `nil` crée une nouvelle enceinte.
    init(equipment: Equipment?, sortIndex: Int = 0) {
        self.equipment = equipment
        self.sortIndex = equipment?.sortIndex ?? sortIndex

        let type = equipment?.type ?? .positiveCold
        let range = equipment?.acceptedRange ?? type.recommendedRange

        _name = State(initialValue: equipment?.name ?? "")
        _type = State(initialValue: type)
        _location = State(initialValue: equipment?.location ?? "")
        _minText = State(initialValue: EquipmentEditorView.format(range.lowerBound))
        _maxText = State(initialValue: EquipmentEditorView.format(range.upperBound))
        _isActive = State(initialValue: equipment?.isActive ?? true)
    }

    private var minValue: Double? { AppFormatters.parseTemperature(minText) }
    private var maxValue: Double? { AppFormatters.parseTemperature(maxText) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && minValue != nil
            && maxValue != nil
    }

    private var isRangeInverted: Bool {
        guard let minValue, let maxValue else { return false }
        return minValue > maxValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identification") {
                    TextField("Nom (ex. Frigo cuisine)", text: $name)

                    Picker("Type", selection: $type) {
                        ForEach(EquipmentType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .onChange(of: type) { _, newValue in
                        applyRecommendedRange(for: newValue)
                    }

                    TextField("Emplacement (facultatif)", text: $location)
                }

                Section {
                    HStack {
                        Text("Minimum")
                        Spacer()
                        TextField("0,0", text: $minText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 100)
                        Text("°C").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("4,0", text: $maxText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 100)
                        Text("°C").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Plage acceptée")
                } footer: {
                    if isRangeInverted {
                        Label("Le minimum est supérieur au maximum : les valeurs seront inversées à l'enregistrement.",
                              systemImage: "info.circle")
                    } else {
                        Text("Valeur recommandée pour ce type : \(AppFormatters.range(type.recommendedRange)).")
                    }
                }

                if equipment != nil {
                    Section {
                        Toggle("Enceinte en service", isOn: $isActive)
                    } footer: {
                        Text("Une enceinte archivée disparaît des relevés quotidiens, mais son historique reste consultable.")
                    }
                }
            }
            .navigationTitle(equipment == nil ? "Nouvelle enceinte" : "Modifier l'enceinte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Actions

    /// Le changement de type ne réécrit la plage que si l'utilisateur n'a pas
    /// déjà personnalisé la sienne.
    private func applyRecommendedRange(for newType: EquipmentType) {
        guard equipment == nil else { return }
        minText = EquipmentEditorView.format(newType.recommendedRange.lowerBound)
        maxText = EquipmentEditorView.format(newType.recommendedRange.upperBound)
    }

    private func save() {
        guard let minValue, let maxValue else { return }

        let lower = Swift.min(minValue, maxValue)
        let upper = Swift.max(minValue, maxValue)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let equipment {
            equipment.name = trimmedName
            equipment.type = type
            equipment.location = location
            equipment.minTemperature = lower
            equipment.maxTemperature = upper
            equipment.isActive = isActive
        } else {
            let created = Equipment(
                name: trimmedName,
                type: type,
                location: location,
                minTemperature: lower,
                maxTemperature: upper,
                sortIndex: sortIndex
            )
            modelContext.insert(created)
        }

        try? modelContext.save()
        dismiss()
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(AppFormatters.locale))
    }
}

#Preview {
    EquipmentEditorView(equipment: nil)
        .modelContainer(AppSchema.preview)
}
