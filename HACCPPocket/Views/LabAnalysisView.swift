//
//  LabAnalysisView.swift
//  HACCPPocket
//
//  Registre des analyses de laboratoire.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct LabAnalysisListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \LabAnalysis.sampledAt, order: .reverse)
    private var analyses: [LabAnalysis]

    @State private var isCreating = false
    @State private var editedAnalysis: LabAnalysis?
    @State private var showsPaywall = false

    private var attention: [LabAnalysis] { analyses.filter(\.needsAction) }
    private var settled: [LabAnalysis] { analyses.filter { !$0.needsAction } }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .surfaceSampling) }

            if analyses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune analyse", systemImage: "flask")
                    } description: {
                        Text("Aucun texte n'impose une périodicité à un restaurant. Mais un établissement qui n'analyse jamais rien ne peut pas démontrer que ses procédures fonctionnent.")
                    } actions: {
                        Button("Enregistrer une analyse") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section("À traiter") {
                    ForEach(attention) { analysis in row(analysis) }
                }
            }

            if !settled.isEmpty {
                Section("Historique") {
                    ForEach(settled) { analysis in row(analysis) }
                }
            }
        }
        .navigationTitle("Analyses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer une analyse", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            LabAnalysisEditorView(analysis: nil, context: modelContext)
        }
        .sheet(item: $editedAnalysis) { analysis in
            LabAnalysisEditorView(analysis: analysis, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ analysis: LabAnalysis) -> some View {
        Button {
            editedAnalysis = analysis
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(systemImage: analysis.kind.systemImage, tint: tint(for: analysis))

                VStack(alignment: .leading, spacing: 3) {
                    Text(analysis.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle(for: analysis))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if analysis.needsCorrectiveAction {
                        Label("Suite à écrire", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !analysis.findings.isEmpty {
                        Text(analysis.findings)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(text: analysis.statusLabel, color: tint(for: analysis))
                    if analysis.hasReport {
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
            Button(role: .destructive) { delete(analysis) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func subtitle(for analysis: LabAnalysis) -> String {
        var parts = ["\(analysis.kind.label) · \(AppFormatters.shortDate(analysis.sampledAt))"]
        if !analysis.laboratory.isEmpty { parts.append(analysis.laboratory) }
        return parts.joined(separator: " · ")
    }

    private func tint(for analysis: LabAnalysis) -> Color {
        switch analysis.result {
        case .pending:        return .secondary
        case .satisfactory:   return analysis.isOverdue() ? .orange : .green
        case .acceptable:     return .orange
        case .unsatisfactory: return .red
        }
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ analysis: LabAnalysis) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(analysis)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct LabAnalysisEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let analysis: LabAnalysis?
    private let context: ModelContext

    @State private var sampleName: String
    @State private var kind: AnalysisKind
    @State private var location: String
    @State private var sampledAt: Date
    @State private var laboratory: String
    @State private var reportReference: String
    @State private var result: AnalysisResult
    @State private var hasResultDate: Bool
    @State private var resultReceivedAt: Date
    @State private var findings: String
    @State private var correctiveAction: String
    @State private var hasNextDue: Bool
    @State private var nextDueDate: Date
    @State private var operatorName: String
    @State private var notes: String
    @State private var reportData: Data?
    @State private var reportItem: PhotosPickerItem?

    init(analysis: LabAnalysis?, context: ModelContext) {
        self.analysis = analysis
        self.context = context

        _sampleName = State(initialValue: analysis?.sampleName ?? "")
        _kind = State(initialValue: analysis?.kind ?? .surface)
        _location = State(initialValue: analysis?.location ?? "")
        _sampledAt = State(initialValue: analysis?.sampledAt ?? .now)
        _laboratory = State(initialValue: analysis?.laboratory ?? "")
        _reportReference = State(initialValue: analysis?.reportReference ?? "")
        _result = State(initialValue: analysis?.result ?? .pending)
        _hasResultDate = State(initialValue: analysis?.resultReceivedAt != nil)
        _resultReceivedAt = State(initialValue: analysis?.resultReceivedAt ?? .now)
        _findings = State(initialValue: analysis?.findings ?? "")
        _correctiveAction = State(initialValue: analysis?.correctiveAction ?? "")
        _hasNextDue = State(initialValue: analysis?.nextDueDate != nil)
        _nextDueDate = State(
            initialValue: analysis?.nextDueDate
                ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)
                ?? .now
        )
        _operatorName = State(initialValue: analysis?.operatorName ?? "")
        _notes = State(initialValue: analysis?.notes ?? "")
        _reportData = State(initialValue: analysis?.reportData)
    }

    private var canSave: Bool {
        guard !sampleName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if result.requiresAction && correctiveAction.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .surfaceSampling) }

                Section {
                    Picker("Nature", selection: $kind) {
                        ForEach(AnalysisKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    TextField("Ce qui a été prélevé", text: $sampleName)
                    TextField("Emplacement", text: $location)
                    DatePicker("Prélevé le", selection: $sampledAt, in: ...Date.now)
                } header: {
                    Text("Prélèvement")
                } footer: {
                    Text(kind.detail)
                }

                Section("Laboratoire") {
                    TextField("Nom du laboratoire", text: $laboratory)
                    TextField("Numéro de rapport", text: $reportReference)
                }

                Section {
                    Picker("Résultat", selection: $result) {
                        ForEach(AnalysisResult.allCases) { result in
                            Label(result.label, systemImage: result.systemImage).tag(result)
                        }
                    }

                    if result != .pending {
                        Toggle("Date de réception connue", isOn: $hasResultDate)
                        if hasResultDate {
                            DatePicker("Reçu le", selection: $resultReceivedAt, in: sampledAt...Date.now)
                        }

                        TextField("Germes recherchés et valeurs", text: $findings, axis: .vertical)
                            .lineLimit(2...6)
                    }
                } header: {
                    Text("Résultat")
                }

                if result.requiresAction {
                    Section {
                        TextField(
                            "Ex. protocole revu, dilution corrigée, planche remplacée, nouveau prélèvement le…",
                            text: $correctiveAction,
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                    } header: {
                        Label("Suite donnée", systemImage: "wrench.and.screwdriver")
                    } footer: {
                        Text("Obligatoire. Un mauvais résultat sans suite écrite est pire qu'une absence d'analyse : il prouve qu'on savait et qu'on n'a rien fait.")
                    }
                }

                Section {
                    Toggle("Prochaine analyse prévue", isOn: $hasNextDue)
                    if hasNextDue {
                        DatePicker("À refaire le", selection: $nextDueDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("La fréquence est celle que vous avez retenue dans votre plan de maîtrise sanitaire. Aucun texte n'en impose une à un restaurant.")
                }

                reportSection

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(analysis == nil ? "Nouvelle analyse" : "Modifier")
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
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    @ViewBuilder
    private var reportSection: some View {
        Section {
            #if canImport(UIKit)
            if let reportData, let image = UIImage(data: reportData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.reportData = nil
                } label: {
                    Label("Retirer le rapport", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $reportItem, matching: .images) {
                Label(
                    reportData == nil ? "Photographier le rapport" : "Remplacer le rapport",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Rapport du laboratoire")
        }
        .onChange(of: reportItem) { _, item in
            Task { await loadReport(item) }
        }
    }

    private func loadReport(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            reportData = data
        }
    }

    private func save() {
        let target = analysis ?? LabAnalysis()

        target.sampleName = sampleName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind
        target.location = location
        target.sampledAt = sampledAt
        target.laboratory = laboratory
        target.reportReference = reportReference
        target.result = result
        target.resultReceivedAt = (result != .pending && hasResultDate) ? resultReceivedAt : nil
        target.findings = findings
        target.correctiveAction = correctiveAction
        target.nextDueDate = hasNextDue ? nextDueDate : nil
        target.reportData = reportData
        target.operatorName = operatorName
        target.notes = notes

        if analysis == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
