//
//  StaffTrainingView.swift
//  HACCPPocket
//
//  Registre des formations à l'hygiène alimentaire. L'attestation est l'une
//  des premières pièces réclamées lors d'un contrôle.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liste

struct StaffTrainingListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \StaffTraining.completedAt, order: .reverse)
    private var trainings: [StaffTraining]

    @State private var editedTraining: StaffTraining?
    @State private var isCreating = false
    @State private var showsPaywall = false
    @State private var trainingPendingDeletion: StaffTraining?

    private var expiring: [StaffTraining] {
        trainings.filter { $0.isExpired() || $0.isExpiringSoon() }
    }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .staffTraining) }

            if !expiring.isEmpty {
                Section {
                    ForEach(expiring) { training in
                        HStack(spacing: 12) {
                            RowIcon(
                                systemImage: "clock.badge.exclamationmark",
                                tint: training.isExpired() ? .red : .orange
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(training.personName)
                                    .font(.subheadline.weight(.semibold))
                                if let expiresAt = training.expiresAt {
                                    Text("Échéance le \(AppFormatters.shortDate(expiresAt))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            StatusBadge(
                                text: training.statusLabel,
                                color: training.isExpired() ? .red : .orange
                            )
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("À renouveler")
                }
            }

            Section("Formations") {
                if trainings.isEmpty {
                    Text("Aucune formation enregistrée.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trainings) { training in
                        Button {
                            editedTraining = training
                        } label: {
                            row(training)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                trainingPendingDeletion = training
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Formations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if subscription.canWrite { isCreating = true } else { showsPaywall = true }
                } label: {
                    Label("Nouvelle formation", systemImage: "plus")
                }
            }
        }
        .overlay {
            if trainings.isEmpty {
                ContentUnavailableView {
                    Label("Aucune formation", systemImage: "graduationcap")
                } description: {
                    Text("Au moins une personne de l'établissement doit justifier d'une formation à l'hygiène alimentaire.")
                } actions: {
                    Button("Ajouter une formation") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $isCreating) { StaffTrainingFormView(context: modelContext) }
        .sheet(item: $editedTraining) { training in
            StaffTrainingFormView(training: training, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .confirmationDialog(
            "Supprimer cette formation ?",
            isPresented: Binding(
                get: { trainingPendingDeletion != nil },
                set: { if !$0 { trainingPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let training = trainingPendingDeletion {
                    modelContext.delete(training)
                    try? modelContext.save()
                }
                trainingPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { trainingPendingDeletion = nil }
        }
    }

    private func row(_ training: StaffTraining) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: training.hasCertificate ? "doc.badge.checkmark" : "graduationcap",
                tint: training.isExpired() ? .red : .brand
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(training.personName)
                    .font(.subheadline.weight(.semibold))
                Text(training.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(AppFormatters.shortDate(training.completedAt))\(training.organisation.isEmpty ? "" : " · \(training.organisation)")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !training.hasCertificate {
                    Label("Attestation non jointe", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: training.statusLabel,
                color: training.isExpired() ? .red : (training.isExpiringSoon() ? .orange : .green)
            )
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Formulaire

struct StaffTrainingFormView: View {

    @Environment(\.dismiss) private var dismiss

    private let training: StaffTraining?
    private let context: ModelContext

    @State private var personName: String
    @State private var title: String
    @State private var organisation: String
    @State private var completedAt: Date
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var notes: String
    @State private var certificateData: Data?
    @State private var photoItem: PhotosPickerItem?

    init(training: StaffTraining? = nil, context: ModelContext) {
        self.training = training
        self.context = context

        _personName = State(initialValue: training?.personName ?? "")
        _title = State(initialValue: training?.title ?? "Hygiène alimentaire")
        _organisation = State(initialValue: training?.organisation ?? "")
        _completedAt = State(initialValue: training?.completedAt ?? .now)
        _hasExpiry = State(initialValue: training?.expiresAt != nil)
        _expiresAt = State(
            initialValue: training?.expiresAt
                ?? Calendar.current.date(byAdding: .year, value: 5, to: .now)
                ?? .now
        )
        _notes = State(initialValue: training?.notes ?? "")
        _certificateData = State(initialValue: training?.certificateData)
    }

    private var canSave: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personne") {
                    OperatorField(name: $personName, placeholder: "Nom et prénom")
                        .textContentType(.name)
                }

                Section {
                    TextField("Intitulé de la formation", text: $title)
                    TextField("Organisme de formation", text: $organisation)
                    DatePicker("Suivie le", selection: $completedAt, in: ...Date.now, displayedComponents: .date)

                    Toggle("Formation à renouveler", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Échéance", selection: $expiresAt, displayedComponents: .date)
                    }
                } header: {
                    Text("Formation")
                } footer: {
                    Text("Toutes les formations n'expirent pas. Activez l'échéance seulement si l'organisme impose un recyclage.")
                }

                Section {
                    if let certificateData, let image = photo(from: certificateData) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            certificateData == nil ? "Joindre l'attestation" : "Remplacer l'attestation",
                            systemImage: "doc.viewfinder"
                        )
                    }

                    if certificateData != nil {
                        Button("Retirer l'attestation", role: .destructive) { certificateData = nil }
                    }
                } header: {
                    Text("Attestation")
                } footer: {
                    Text("Une photo de l'attestation évite de courir après le papier le jour du contrôle.")
                }

                Section("Notes") {
                    TextField("Observations", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(training == nil ? "Nouvelle formation" : "Modifier la formation")
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
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
                        certificateData = data
                    }
                }
            }
        }
    }

    private func photo(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private func save() {
        let trimmed = personName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let training {
            training.personName = trimmed
            training.title = title
            training.organisation = organisation
            training.completedAt = completedAt
            training.expiresAt = hasExpiry ? expiresAt : nil
            training.certificateData = certificateData
            training.notes = notes
        } else {
            let created = StaffTraining(
                personName: trimmed,
                title: title,
                organisation: organisation,
                completedAt: completedAt,
                expiresAt: hasExpiry ? expiresAt : nil,
                certificateData: certificateData,
                notes: notes
            )
            context.insert(created)
        }

        try? context.save()
        dismiss()
    }
}
