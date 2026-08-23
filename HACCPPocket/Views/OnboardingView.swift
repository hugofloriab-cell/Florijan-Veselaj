//
//  OnboardingView.swift
//  HACCPPocket
//
//  Première configuration. Sans elle, un nouvel utilisateur atterrissait sur
//  un « 0 / 6 » sans savoir ce qu'on attendait de lui.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService

    @Query private var establishments: [Establishment]
    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]

    private enum Step: Int, CaseIterable {
        case welcome
        case establishment
        case equipments
        case reminders

        var title: String {
            switch self {
            case .welcome:       "Bienvenue"
            case .establishment: "Votre établissement"
            case .equipments:    "Vos enceintes"
            case .reminders:     "Vos rappels"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var isCreatingEquipment = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .tint(.teal)
                    .padding(.horizontal)
                    .padding(.top, 8)

                content

                footer
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .welcome {
                        Button("Passer") { finish() }
                    }
                }
            }
            .sheet(isPresented: $isCreatingEquipment) {
                EquipmentEditorView(equipment: nil, sortIndex: equipments.count)
            }
            .task {
                if establishments.isEmpty {
                    modelContext.insert(Establishment())
                    try? modelContext.save()
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Étapes

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:      welcomeStep
        case .establishment: establishmentStep
        case .equipments:   equipmentsStep
        case .reminders:    remindersStep
        }
    }

    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.teal)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Text("Votre registre sanitaire, dans votre poche")
                    .font(.title2.weight(.bold))

                Text("HACCP Pocket remplace le classeur papier : relevés de températures, produits entamés, contrôles à réception et plan de nettoyage. En fin de mois, un PDF prêt à présenter lors d'un contrôle.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    bullet("Tout reste sur votre appareil", "lock.shield.fill",
                           "Aucun compte à créer, aucune donnée envoyée sur Internet.")
                    bullet("Trois minutes par jour", "clock.fill",
                           "Deux relevés, quelques cases à cocher.")
                    bullet("Prêt pour le contrôle", "doc.text.fill",
                           "Le registre mensuel se génère en un geste.")
                }
                .padding(.top, 4)

                Text("Configurons l'essentiel : cela prend une minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func bullet(_ title: String, _ systemImage: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.teal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var establishmentStep: some View {
        if let establishment = establishments.first {
            Form {
                Section {
                    TextField("Raison sociale", text: Bindable(establishment).name)
                    TextField("Adresse", text: Bindable(establishment).address, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Responsable du plan sanitaire", text: Bindable(establishment).managerName)
                } footer: {
                    Text("Ces informations forment l'en-tête du registre mensuel. Vous pourrez les compléter plus tard dans les réglages.")
                }

                Section {
                    TextField("Votre nom", text: Bindable(preferences).operatorName)
                } header: {
                    Text("Qui saisit les relevés ?")
                } footer: {
                    Text("Pré-rempli dans chaque formulaire. La traçabilité impose de savoir qui a fait quoi.")
                }
            }
        }
    }

    private var equipmentsStep: some View {
        Form {
            Section {
                ForEach(equipments) { equipment in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(equipment.name, systemImage: equipment.type.systemImage)
                        Text(equipment.formattedRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    offsets.map { equipments[$0] }.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }

                Button {
                    isCreatingEquipment = true
                } label: {
                    Label("Ajouter une enceinte", systemImage: "plus")
                }
            } header: {
                Text("Enceintes à surveiller")
            } footer: {
                Text("Nous en avons pré-rempli trois. Renommez-les, supprimez celles que vous n'avez pas, ajoutez les vôtres : c'est sur cette liste que se basent les relevés quotidiens.")
            }
        }
    }

    private var remindersStep: some View {
        Form {
            Section {
                Toggle("Rappels matin et soir", isOn: Bindable(preferences).remindersEnabled)

                if preferences.remindersEnabled {
                    DatePicker("Matin", selection: morningTime, displayedComponents: .hourAndMinute)
                    DatePicker("Soir", selection: eveningTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Ne rien oublier")
            } footer: {
                Text("Un oubli de relevé est une ligne vide dans le registre. Les rappels sont locaux : ils ne quittent pas l'appareil.")
            }

            if !notificationService.isAuthorized {
                Section {
                    Button {
                        Task { await notificationService.requestAuthorization() }
                    } label: {
                        Label("Autoriser les notifications", systemImage: "bell.badge")
                    }
                }
            }
        }
    }

    private var morningTime: Binding<Date> {
        Binding(
            get: { preferences.time(hour: preferences.morningHour, minute: preferences.morningMinute) },
            set: { preferences.setMorning(from: $0) }
        )
    }

    private var eveningTime: Binding<Date> {
        Binding(
            get: { preferences.time(hour: preferences.eveningHour, minute: preferences.eveningMinute) },
            set: { preferences.setEvening(from: $0) }
        )
    }

    // MARK: - Navigation

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Précédent") {
                    if let previous = Step(rawValue: step.rawValue - 1) {
                        withAnimation { step = previous }
                    }
                }
                .buttonStyle(.bordered)
            }

            Button(step == Step.allCases.last ? "Terminer" : "Continuer") {
                if let next = Step(rawValue: step.rawValue + 1) {
                    withAnimation { step = next }
                } else {
                    finish()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.bar)
    }

    private func finish() {
        establishments.first?.touch()
        try? modelContext.save()
        Task { await notificationService.applySchedule(from: preferences) }
        dismiss()
    }
}
