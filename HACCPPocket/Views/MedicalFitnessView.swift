//
//  MedicalFitnessView.swift
//  HACCPPocket
//
//  Suivi médical du personnel.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct MedicalFitnessListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \MedicalFitnessRecord.examinedAt, order: .reverse)
    private var records: [MedicalFitnessRecord]

    @State private var isCreating = false
    @State private var editedRecord: MedicalFitnessRecord?
    @State private var showsPaywall = false

    private var attention: [MedicalFitnessRecord] { records.filter(\.needsAction) }
    private var upToDate: [MedicalFitnessRecord] { records.filter { !$0.needsAction } }

    var body: some View {
        List {
            Section {
                Label(
                    "Une personne atteinte d'une maladie transmissible par les aliments ne doit pas manipuler de denrées. Le suivi médical qui permet de s'en assurer relève de la médecine du travail.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun suivi enregistré", systemImage: "stethoscope")
                    } description: {
                        Text("Archivez ici les attestations de suivi et les avis d'aptitude délivrés par le service de santé au travail, et voyez venir les échéances.")
                    } actions: {
                        Button("Enregistrer un suivi") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section("À traiter") {
                    ForEach(attention) { record in row(record) }
                }
            }

            if !upToDate.isEmpty {
                Section("À jour") {
                    ForEach(upToDate) { record in row(record) }
                }
            }
        }
        .navigationTitle("Suivi médical")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un suivi", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            MedicalFitnessEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            MedicalFitnessEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ record: MedicalFitnessRecord) -> some View {
        Button {
            editedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: record.verdict.systemImage, tint: tint(for: record))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle(for: record))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !record.restrictions.isEmpty {
                        Text(record.restrictions)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(text: record.statusLabel, color: tint(for: record))
                    if record.hasDocument {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(record) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func subtitle(for record: MedicalFitnessRecord) -> String {
        var parts: [String] = []
        if !record.jobTitle.isEmpty { parts.append(record.jobTitle) }
        parts.append("visite du \(AppFormatters.shortDate(record.examinedAt))")
        if let next = record.nextVisitDate {
            parts.append("prochaine le \(AppFormatters.shortDate(next))")
        }
        return parts.joined(separator: " · ")
    }

    private func tint(for record: MedicalFitnessRecord) -> Color {
        if record.isOverdue() || record.verdict == .unfit { return .red }
        if record.needsAction { return .orange }
        return .green
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ record: MedicalFitnessRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct MedicalFitnessEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let record: MedicalFitnessRecord?
    private let context: ModelContext

    @State private var personName: String
    @State private var jobTitle: String
    @State private var service: String
    @State private var examinedAt: Date
    @State private var hasNextVisit: Bool
    @State private var nextVisitDate: Date
    @State private var verdict: FitnessVerdict
    @State private var restrictions: String
    @State private var comment: String
    @State private var documentData: Data?
    @State private var documentItem: PhotosPickerItem?

    init(record: MedicalFitnessRecord?, context: ModelContext) {
        self.record = record
        self.context = context

        _personName = State(initialValue: record?.personName ?? "")
        _jobTitle = State(initialValue: record?.jobTitle ?? "")
        _service = State(initialValue: record?.occupationalHealthService ?? "")
        _examinedAt = State(initialValue: record?.examinedAt ?? .now)
        _hasNextVisit = State(initialValue: record?.nextVisitDate != nil)
        _nextVisitDate = State(
            initialValue: record?.nextVisitDate
                ?? Calendar.current.date(byAdding: .year, value: 2, to: .now)
                ?? .now
        )
        _verdict = State(initialValue: record?.verdict ?? .fit)
        _restrictions = State(initialValue: record?.restrictions ?? "")
        _comment = State(initialValue: record?.comment ?? "")
        _documentData = State(initialValue: record?.documentData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personne") {
                    OperatorField(name: $personName, placeholder: "Nom et prénom")
                    TextField("Poste occupé", text: $jobTitle)
                }

                Section {
                    DatePicker("Date de la visite", selection: $examinedAt, in: ...Date.now, displayedComponents: .date)
                    TextField("Service de santé au travail", text: $service)

                    Toggle("Prochaine visite programmée", isOn: $hasNextVisit)
                    if hasNextVisit {
                        DatePicker("Prochaine visite", selection: $nextVisitDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Visite")
                } footer: {
                    Text("La périodicité dépend du poste et du service de santé au travail : elle n'est pas la même pour tout le monde. Reportez la date que votre service vous a indiquée.")
                }

                Section {
                    Picker("Avis", selection: $verdict) {
                        ForEach(FitnessVerdict.allCases) { verdict in
                            Label(verdict.label, systemImage: verdict.systemImage).tag(verdict)
                        }
                    }

                    if verdict != .fit {
                        TextField(
                            "Aménagements ou restrictions prononcés",
                            text: $restrictions,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                } header: {
                    Text("Avis rendu")
                }

                documentSection

                Section("Détails") {
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouveau suivi" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var documentSection: some View {
        Section {
            #if canImport(UIKit)
            if let documentData, let image = UIImage(data: documentData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.documentData = nil
                } label: {
                    Label("Retirer le document", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $documentItem, matching: .images) {
                Label(
                    documentData == nil ? "Photographier l'attestation" : "Remplacer le document",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Attestation")
        } footer: {
            Text("L'employeur tient ces documents à disposition. Les conserver ici évite de fouiller un classeur le jour où on les demande.")
        }
        .onChange(of: documentItem) { _, item in
            Task { await loadDocument(item) }
        }
    }

    private func loadDocument(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            documentData = data
        }
    }

    private func save() {
        let target = record ?? MedicalFitnessRecord()

        target.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.jobTitle = jobTitle
        target.occupationalHealthService = service
        target.examinedAt = examinedAt
        target.nextVisitDate = hasNextVisit ? nextVisitDate : nil
        target.verdict = verdict
        target.restrictions = verdict == .fit ? "" : restrictions
        target.documentData = documentData
        target.comment = comment

        if record == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
