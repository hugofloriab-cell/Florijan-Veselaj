//
//  DocumentArchiveView.swift
//  HACCPPocket
//
//  Archive documentaire : PMS, procédures, contrats, attestations.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct DocumentArchiveListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \RegulatoryDocument.issuedAt, order: .reverse)
    private var documents: [RegulatoryDocument]

    @State private var isCreating = false
    @State private var editedDocument: RegulatoryDocument?
    @State private var showsPaywall = false

    private struct DocumentGroup: Identifiable {
        let category: DocumentCategory
        var documents: [RegulatoryDocument]
        var id: String { category.rawValue }
    }

    private var groups: [DocumentGroup] {
        DocumentCategory.allCases
            .sorted { $0.sortWeight < $1.sortWeight }
            .compactMap { category in
                let matching = documents.filter { $0.category == category }
                return matching.isEmpty ? nil : DocumentGroup(category: category, documents: matching)
            }
    }

    private var attention: [RegulatoryDocument] { documents.filter(\.needsAction) }

    private var hasSanitaryPlan: Bool {
        documents.contains { $0.category == .sanitaryPlan && $0.hasFile }
    }

    var body: some View {
        List {
            if !hasSanitaryPlan {
                Section {
                    Label(
                        "Aucun plan de maîtrise sanitaire archivé. C'est le document que l'on vous demandera en premier.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if documents.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun document", systemImage: "folder")
                    } description: {
                        Text("Le plan de maîtrise sanitaire, les contrats et les attestations vivent souvent dans un classeur, une clé USB ou la boîte mail du comptable. Mettez-les ici.")
                    } actions: {
                        Button("Ajouter un document") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section {
                    ForEach(attention) { document in row(document) }
                } header: {
                    Text("À traiter")
                } footer: {
                    Text("Documents expirés, à renouveler, ou enregistrés sans pièce jointe.")
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.documents) { document in row(document) }
                } header: {
                    Text(group.category.label)
                } footer: {
                    Text(group.category.detail)
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Ajouter un document", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            DocumentEditorView(document: nil, context: modelContext)
        }
        .sheet(item: $editedDocument) { document in
            DocumentEditorView(document: document, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ document: RegulatoryDocument) -> some View {
        Button {
            editedDocument = document
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: document.category.systemImage, tint: tint(for: document))

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle(for: document))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if document.needsAction {
                        StatusBadge(text: document.statusLabel, color: tint(for: document))
                    }
                    if document.hasFile {
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
            Button(role: .destructive) { delete(document) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func subtitle(for document: RegulatoryDocument) -> String {
        var parts: [String] = []
        if !document.issuer.isEmpty { parts.append(document.issuer) }
        parts.append("du \(AppFormatters.shortDate(document.issuedAt))")
        if let expiry = document.expiresAt {
            parts.append("valable jusqu'au \(AppFormatters.shortDate(expiry))")
        }
        return parts.joined(separator: " · ")
    }

    private func tint(for document: RegulatoryDocument) -> Color {
        if document.isExpired() { return .red }
        if document.needsAction { return .orange }
        return .brand
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ document: RegulatoryDocument) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(document)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct DocumentEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let document: RegulatoryDocument?
    private let context: ModelContext

    @State private var title: String
    @State private var category: DocumentCategory
    @State private var issuer: String
    @State private var issuedAt: Date
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var reference: String
    @State private var notes: String
    @State private var fileData: Data?
    @State private var fileItem: PhotosPickerItem?

    init(document: RegulatoryDocument?, context: ModelContext) {
        self.document = document
        self.context = context

        _title = State(initialValue: document?.title ?? "")
        _category = State(initialValue: document?.category ?? .sanitaryPlan)
        _issuer = State(initialValue: document?.issuer ?? "")
        _issuedAt = State(initialValue: document?.issuedAt ?? .now)
        _hasExpiry = State(initialValue: document?.expiresAt != nil)
        _expiresAt = State(
            initialValue: document?.expiresAt
                ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)
                ?? .now
        )
        _reference = State(initialValue: document?.reference ?? "")
        _notes = State(initialValue: document?.notes ?? "")
        _fileData = State(initialValue: document?.fileData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Nature", selection: $category) {
                        ForEach(DocumentCategory.allCases) { category in
                            Label(category.label, systemImage: category.systemImage).tag(category)
                        }
                    }
                    TextField("Intitulé", text: $title)
                    TextField("Établi ou délivré par", text: $issuer)
                    TextField("Référence ou version", text: $reference)
                } header: {
                    Text("Document")
                } footer: {
                    Text(category.detail)
                }

                Section("Dates") {
                    DatePicker("Établi le", selection: $issuedAt, displayedComponents: .date)
                    Toggle("Le document expire", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Valable jusqu'au", selection: $expiresAt, displayedComponents: .date)
                    }
                }

                fileSection

                Section("Notes") {
                    TextField("Commentaire", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(document == nil ? "Nouveau document" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        Section {
            #if canImport(UIKit)
            if let fileData, let image = UIImage(data: fileData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.fileData = nil
                } label: {
                    Label("Retirer la pièce jointe", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $fileItem, matching: .images) {
                Label(
                    fileData == nil ? "Photographier le document" : "Remplacer la pièce jointe",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Pièce jointe")
        } footer: {
            Text("Un document sans pièce jointe est une ligne dans une liste, pas une preuve. Pour un document de plusieurs pages, photographiez au minimum la page de garde et la date de révision.")
        }
        .onChange(of: fileItem) { _, item in
            Task { await loadFile(item) }
        }
    }

    private func loadFile(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            fileData = data
        }
    }

    private func save() {
        let target = document ?? RegulatoryDocument()

        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.issuer = issuer
        target.issuedAt = issuedAt
        target.expiresAt = hasExpiry ? expiresAt : nil
        target.reference = reference
        target.fileData = fileData
        target.notes = notes
        target.touch()

        if document == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
