//
//  CleaningPlanView.swift
//  HACCPPocket
//
//  Plan de nettoyage et de désinfection : on coche, l'app horodate et retient
//  qui a fait quoi. C'est la preuve d'exécution exigée par le PMS.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct CleaningPlanView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \CleaningTask.sortIndex) private var tasks: [CleaningTask]

    @State private var viewModel: CleaningPlanViewModel?
    @State private var expandedTask: CleaningTask?
    @State private var showsPaywall = false
    @State private var editedTask: CleaningTask?
    @State private var isCreatingTask = false
    @State private var taskPendingDeletion: CleaningTask?
    @State private var photoTask: CleaningTask?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Nettoyage")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if subscription.canWrite {
                            isCreatingTask = true
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        Label("Nouvelle opération", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingTask) {
                CleaningTaskEditorView(task: nil, sortIndex: tasks.count)
            }
            .sheet(item: $editedTask) { task in
                CleaningTaskEditorView(task: task)
            }
            .confirmationDialog(
                "Supprimer cette opération ?",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let task = taskPendingDeletion { viewModel?.delete(task) }
                    taskPendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { taskPendingDeletion = nil }
            } message: {
                Text("Son historique d'exécution sera perdu. Pour la retirer du plan en conservant les preuves, archivez-la plutôt.")
            }
            .sheet(item: $expandedTask) { task in
                CleaningTaskDetailView(task: task)
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .sheet(item: $photoTask) { task in
                PhotoCaptureSheet(
                    title: "Photo du nettoyage",
                    message: "La photo est jointe à l'enregistrement de l'opération et figure dans vos preuves d'exécution."
                ) { data in
                    viewModel?.complete(task, photoData: data)
                    photoTask = nil
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = CleaningPlanViewModel(context: modelContext)
                }
            }
        }
    }

    private func content(viewModel: CleaningPlanViewModel) -> some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    TextField("Qui réalise le nettoyage ?", text: Bindable(viewModel).operatorName)
                }
                Toggle("Afficher les opérations déjà faites", isOn: Bindable(viewModel).showsCompletedTasks)
            } footer: {
                Text("Le nom saisi ici est enregistré avec chaque opération cochée.")
            }

            ForEach(viewModel.sections(from: tasks)) { section in
                Section(section.frequency.label) {
                    ForEach(section.tasks) { task in
                        row(for: task, viewModel: viewModel)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    guard subscription.canWrite else { showsPaywall = true; return }
                                    photoTask = task
                                } label: {
                                    Label("Photo", systemImage: "camera")
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    taskPendingDeletion = task
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }

                                Button {
                                    viewModel.archive(task)
                                } label: {
                                    Label("Archiver", systemImage: "archivebox")
                                }
                                .tint(.orange)

                                Button {
                                    editedTask = task
                                } label: {
                                    Label("Modifier", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }
            }
        }
        .overlay {
            if tasks.filter(\.isActive).isEmpty {
                ContentUnavailableView(
                    "Plan de nettoyage vide",
                    systemImage: "sparkles",
                    description: Text("Aucune opération active.")
                )
            }
        }
    }

    private func row(for task: CleaningTask, viewModel: CleaningPlanViewModel) -> some View {
        let isDone = task.isCompleted(on: .now)

        return HStack(alignment: .top, spacing: 12) {
            Button {
                guard subscription.canWrite else { showsPaywall = true; return }
                if isDone {
                    viewModel.undoCompletion(for: task)
                } else {
                    viewModel.complete(task)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Annuler le pointage de \(task.title)" : "Pointer \(task.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)

                if !task.zone.isEmpty {
                    Text(task.zone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.dueLabel(for: task))
                    .font(.caption2)
                    .foregroundStyle(task.isOverdue() ? Color.orange : Color.secondary)
            }

            Spacer()

            Button {
                expandedTask = task
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Détail de \(task.title)")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Détail d'une opération

struct CleaningTaskDetailView: View {

    @Environment(\.dismiss) private var dismiss

    let task: CleaningTask

    private func photo(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private var history: [CleaningRecord] {
        task.records
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Mode opératoire") {
                    if task.procedure.isEmpty {
                        Text("Aucun mode opératoire renseigné.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(task.procedure)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Fiche") {
                    InfoRow(label: "Fréquence", value: task.frequency.label, systemImage: task.frequency.systemImage)
                    if !task.zone.isEmpty {
                        InfoRow(label: "Zone", value: task.zone, systemImage: "mappin.and.ellipse")
                    }
                    if !task.productUsed.isEmpty {
                        InfoRow(label: "Produit", value: task.productUsed, systemImage: "drop")
                    }
                    if let next = task.nextDueDate() {
                        InfoRow(
                            label: "Prochaine échéance",
                            value: AppFormatters.shortDate(next),
                            systemImage: "calendar"
                        )
                    }
                }

                Section("Historique") {
                    if history.isEmpty {
                        Text("Aucune exécution enregistrée.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppFormatters.dateAndTime(record.completedAt))
                                    .font(.subheadline)
                                if record.isTraceable {
                                    Text("Par \(record.operatorName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Label("Opérateur non renseigné", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                if let data = record.photoData, let image = photo(from: data) {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
