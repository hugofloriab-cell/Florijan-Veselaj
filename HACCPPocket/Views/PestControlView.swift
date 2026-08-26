//
//  PestControlView.swift
//  HACCPPocket
//
//  Registre de lutte contre les nuisibles : visites du prestataire, constats
//  et suites données.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liste

struct PestControlListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \PestControlVisit.visitedAt, order: .reverse)
    private var visits: [PestControlVisit]

    @State private var editedVisit: PestControlVisit?
    @State private var isCreating = false
    @State private var showsPaywall = false
    @State private var visitPendingDeletion: PestControlVisit?

    /// Prochaine échéance connue, tirée de la visite la plus récente.
    private var nextVisit: PestControlVisit? {
        visits.first { $0.nextVisitDate != nil }
    }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .pestControl) }

            if let nextVisit, let date = nextVisit.nextVisitDate {
                Section {
                    HStack(spacing: 12) {
                        RowIcon(
                            systemImage: "calendar.badge.clock",
                            tint: nextVisit.isNextVisitOverdue() ? .orange : .brand
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prochaine visite")
                                .font(.subheadline.weight(.semibold))
                            Text(AppFormatters.shortDate(date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if nextVisit.isNextVisitOverdue() {
                            StatusBadge(text: "En retard", color: .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Visites") {
                if visits.isEmpty {
                    Text("Aucune visite enregistrée.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visits) { visit in
                        Button {
                            editedVisit = visit
                        } label: {
                            row(visit)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                visitPendingDeletion = visit
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nuisibles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if subscription.canWrite { isCreating = true } else { showsPaywall = true }
                } label: {
                    Label("Nouvelle visite", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) { PestControlFormView(context: modelContext) }
        .sheet(item: $editedVisit) { visit in
            PestControlFormView(visit: visit, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .confirmationDialog(
            "Supprimer cette visite ?",
            isPresented: Binding(
                get: { visitPendingDeletion != nil },
                set: { if !$0 { visitPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let visit = visitPendingDeletion {
                    modelContext.delete(visit)
                    try? modelContext.save()
                }
                visitPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { visitPendingDeletion = nil }
        }
    }

    private func row(_ visit: PestControlVisit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: visit.hasInfestation ? "exclamationmark.triangle.fill" : "checkmark.shield",
                tint: visit.hasInfestation ? .orange : .green
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(visit.company)
                    .font(.subheadline.weight(.semibold))
                Text(AppFormatters.shortDate(visit.visitedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !visit.findings.isEmpty {
                    Text(visit.findings)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                if visit.needsAction {
                    Label("Mesures non renseignées", systemImage: "exclamationmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: visit.statusLabel,
                color: visit.hasInfestation ? .orange : .green
            )
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Formulaire

struct PestControlFormView: View {

    @Environment(\.dismiss) private var dismiss

    private let visit: PestControlVisit?
    private let context: ModelContext

    @State private var company: String
    @State private var technician: String
    @State private var visitedAt: Date
    @State private var findings: String
    @State private var hasInfestation: Bool
    @State private var baitsReplaced: Bool
    @State private var deviceCount: Int
    @State private var actionsTaken: String
    @State private var hasNextVisit: Bool
    @State private var nextVisitDate: Date
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?

    init(visit: PestControlVisit? = nil, context: ModelContext) {
        self.visit = visit
        self.context = context

        _company = State(initialValue: visit?.company ?? "")
        _technician = State(initialValue: visit?.technician ?? "")
        _visitedAt = State(initialValue: visit?.visitedAt ?? .now)
        _findings = State(initialValue: visit?.findings ?? "")
        _hasInfestation = State(initialValue: visit?.hasInfestation ?? false)
        _baitsReplaced = State(initialValue: visit?.baitsReplaced ?? true)
        _deviceCount = State(initialValue: visit?.deviceCount ?? 0)
        _actionsTaken = State(initialValue: visit?.actionsTaken ?? "")
        _hasNextVisit = State(initialValue: visit?.nextVisitDate != nil)
        _nextVisitDate = State(
            initialValue: visit?.nextVisitDate
                ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)
                ?? .now
        )
        _photoData = State(initialValue: visit?.reportPhotoData)
    }

    private var canSave: Bool {
        guard !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if hasInfestation {
            return !actionsTaken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prestataire") {
                    TextField("Société", text: $company)
                    TextField("Technicien", text: $technician)
                    DatePicker("Date de visite", selection: $visitedAt, in: ...Date.now)
                }

                Section {
                    Toggle("Présence de nuisibles constatée", isOn: $hasInfestation)
                    TextField("Constat du technicien", text: $findings, axis: .vertical)
                        .lineLimit(2...5)
                    Stepper("Postes de contrôle : \(deviceCount)", value: $deviceCount, in: 0...200)
                    Toggle("Appâts remplacés", isOn: $baitsReplaced)
                } header: {
                    Text("Constat")
                }

                Section {
                    TextField("Mesures prises ou recommandées", text: $actionsTaken, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Suites données")
                } footer: {
                    if hasInfestation {
                        Text("Obligatoire dès qu'une présence est constatée : c'est la preuve que le signalement a été traité.")
                    }
                }

                Section {
                    Toggle("Planifier la prochaine visite", isOn: $hasNextVisit)
                    if hasNextVisit {
                        DatePicker("Prochaine visite", selection: $nextVisitDate, displayedComponents: .date)
                    }
                }

                Section {
                    if let photoData, let image = photo(from: photoData) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            photoData == nil ? "Joindre le rapport" : "Remplacer la photo",
                            systemImage: "doc.viewfinder"
                        )
                    }

                    if photoData != nil {
                        Button("Retirer la photo", role: .destructive) { photoData = nil }
                    }
                } header: {
                    Text("Rapport de visite")
                }
            }
            .navigationTitle(visit == nil ? "Nouvelle visite" : "Modifier la visite")
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
                        photoData = data
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
        let trimmed = company.trimmingCharacters(in: .whitespacesAndNewlines)

        if let visit {
            visit.company = trimmed
            visit.technician = technician
            visit.visitedAt = visitedAt
            visit.findings = findings
            visit.hasInfestation = hasInfestation
            visit.baitsReplaced = baitsReplaced
            visit.deviceCount = deviceCount
            visit.actionsTaken = actionsTaken
            visit.nextVisitDate = hasNextVisit ? nextVisitDate : nil
            visit.reportPhotoData = photoData
        } else {
            let created = PestControlVisit(
                company: trimmed,
                visitedAt: visitedAt,
                technician: technician,
                findings: findings,
                baitsReplaced: baitsReplaced,
                deviceCount: deviceCount,
                actionsTaken: actionsTaken,
                nextVisitDate: hasNextVisit ? nextVisitDate : nil,
                hasInfestation: hasInfestation,
                reportPhotoData: photoData
            )
            context.insert(created)
        }

        try? context.save()
        dismiss()
    }
}
