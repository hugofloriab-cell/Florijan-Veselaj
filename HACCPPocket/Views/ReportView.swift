//
//  ReportView.swift
//  HACCPPocket
//
//  Export du registre sanitaire mensuel : sélection du mois, aperçu du PDF et
//  partage (mail, AirDrop, impression) via la feuille de partage d'iOS.
//

import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct ReportView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query private var products: [TrackedProduct]
    @Query private var deliveries: [DeliveryCheck]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]
    @Query private var establishments: [Establishment]

    @State private var selectedMonth: Date = .now
    @State private var pdfURL: URL?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var csvRegister: CSVRegister = .temperatures
    @State private var csvURL: URL?

    /// Les douze derniers mois, du plus récent au plus ancien.
    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: currentMonth) }
    }

    private var report: MonthlyReport {
        MonthlyReport(
            month: selectedMonth,
            establishment: establishments.first,
            equipments: equipments,
            products: products,
            deliveries: deliveries,
            cleaningTasks: cleaningTasks
        )
    }

    var body: some View {
        List {
            monthSection
            summarySection
            actionSection

            csvSection

            if let pdfURL {
                Section("Aperçu") {
                    PDFPreview(url: pdfURL)
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle("Registre mensuel")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedMonth) { _, _ in
            // Les fichiers produits ne correspondent plus au mois choisi.
            pdfURL = nil
            csvURL = nil
        }
        .onChange(of: csvRegister) { _, _ in
            csvURL = nil
        }
    }

    // MARK: - Sections

    private var monthSection: some View {
        Section("Période") {
            Picker("Mois", selection: $selectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    Text(AppFormatters.sentenceCased(AppFormatters.monthTitle(month))).tag(month)
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            InfoRow(
                label: "Relevés de température",
                value: "\(report.allReadings.count)",
                systemImage: "thermometer.medium"
            )
            InfoRow(
                label: "Relevés non conformes",
                value: "\(report.nonCompliantReadings.count)",
                systemImage: "exclamationmark.triangle"
            )
            InfoRow(
                label: "Produits tracés",
                value: "\(report.productsInPeriod.count)",
                systemImage: "shippingbox"
            )
            InfoRow(
                label: "Contrôles à réception",
                value: "\(report.deliveriesInPeriod.count)",
                systemImage: "truck.box"
            )

            if !report.undocumentedDeviations.isEmpty {
                Label(
                    "\(report.undocumentedDeviations.count) écart(s) sans action corrective seront signalés en rouge dans le document.",
                    systemImage: "exclamationmark.bubble"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Contenu du registre")
        } footer: {
            if let establishment = establishments.first, !establishment.isReadyForExport {
                Text("Complétez la fiche de l'établissement dans Réglages : elle constitue l'en-tête du document.")
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                generate()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "doc.badge.gearshape")
                    }
                    Text(pdfURL == nil ? "Générer le registre" : "Régénérer")
                }
            }
            .disabled(isGenerating || report.isEmpty)

            if let pdfURL {
                ShareLink(item: pdfURL) {
                    Label("Partager le PDF", systemImage: "square.and.arrow.up")
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            if report.isEmpty {
                Text("Aucun enregistrement sur cette période : il n'y a rien à exporter.")
            } else {
                if subscription.pdfWatermark != nil {
                    Text("Le PDF porte le filigrane « VERSION D'ESSAI ». Il disparaît avec l'abonnement.")
                } else {
                    Text("Le PDF est produit sur l'appareil. Envoyez-le par mail à votre comptable ou conservez-le sur iCloud Drive.")
                }
            }
        }
    }

    private var csvSection: some View {
        Section {
            Picker("Registre", selection: $csvRegister) {
                ForEach(CSVRegister.allCases) { register in
                    Label(register.label, systemImage: register.systemImage).tag(register)
                }
            }

            Button {
                generateCSV()
            } label: {
                Label("Préparer le fichier CSV", systemImage: "tablecells")
            }
            .disabled(report.isEmpty)

            if let csvURL {
                ShareLink(item: csvURL) {
                    Label("Partager le CSV", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Export tableur")
        } footer: {
            Text("Le CSV s'ouvre dans Numbers ou Excel. Utile pour votre comptable ou pour vos propres analyses ; le PDF, lui, reste le document à présenter en contrôle.")
        }
    }

    // MARK: - Génération

    private func generate() {
        isGenerating = true
        errorMessage = nil

        let report = self.report
        let data = PDFReportService.generate(report: report, watermark: subscription.pdfWatermark)

        do {
            pdfURL = try PDFReportService.writeToTemporaryFile(data: data, report: report)
        } catch {
            errorMessage = "Impossible d'écrire le document : \(error.localizedDescription)"
        }

        isGenerating = false
    }

    private func generateCSV() {
        let report = self.report
        let csv = CSVExportService.makeCSV(csvRegister, report: report)

        do {
            csvURL = try CSVExportService.writeToTemporaryFile(csv, register: csvRegister, report: report)
            errorMessage = nil
        } catch {
            errorMessage = "Export CSV impossible : \(error.localizedDescription)"
        }
    }
}

// MARK: - Aperçu PDF

/// Encapsule `PDFView` : SwiftUI n'offre pas encore de visionneuse PDF native.
struct PDFPreview: UIViewRepresentable {

    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
