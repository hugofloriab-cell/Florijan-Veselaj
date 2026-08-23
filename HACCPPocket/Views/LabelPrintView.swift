//
//  LabelPrintView.swift
//  HACCPPocket
//
//  Choix du format, aperçu et impression des étiquettes d'un produit.
//

import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct LabelPrintView: View {

    @Environment(\.dismiss) private var dismiss

    @Query private var establishments: [Establishment]

    let product: TrackedProduct

    @AppStorage("haccp.lastLabelFormat") private var storedFormat: String = LabelFormat.roll62x29.rawValue
    @State private var copies: Int = 1
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    /// Construit à l'usage plutôt que stocké : le type est isolé sur le
    /// thread principal, et l'initialisation d'une propriété de vue ne l'est pas.
    private var printer: AirPrintLabelPrinter { AirPrintLabelPrinter() }

    private var format: LabelFormat {
        LabelFormat(rawValue: storedFormat) ?? .roll62x29
    }

    var body: some View {
        NavigationStack {
            List {
                productSection
                formatSection
                copiesSection
                previewSection
                actionSection
            }
            .navigationTitle("Étiquette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { refreshPreview() }
            .onChange(of: storedFormat) { _, _ in refreshPreview() }
            .onChange(of: copies) { _, _ in refreshPreview() }
        }
    }

    // MARK: - Sections

    private var productSection: some View {
        Section {
            InfoRow(label: "Produit", value: product.name, systemImage: "shippingbox")
            InfoRow(
                label: "À consommer avant le",
                value: AppFormatters.shortDate(product.effectiveLimitDate),
                systemImage: "calendar.badge.exclamationmark"
            )
            if !product.batchNumber.isEmpty {
                InfoRow(label: "Lot", value: product.batchNumber, systemImage: "number")
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $storedFormat) {
                ForEach(LabelFormat.allCases) { format in
                    VStack(alignment: .leading) {
                        Text(format.label)
                        Text(format.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(format.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Format")
        } footer: {
            if format.supportsQRCode {
                Text("Un QR code de traçabilité est imprimé : le scanner depuis l'app rouvre la fiche du produit.")
            } else {
                Text("Ce format est trop petit pour un QR code lisible : seul le texte est imprimé.")
            }
        }
    }

    private var copiesSection: some View {
        Section {
            Stepper("Nombre d'étiquettes : \(copies)", value: $copies, in: 1...48)
            if format.isSheet, let layout = format.sheetLayout {
                Text("\(layout.labelsPerSheet) étiquettes par planche A4.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let previewURL {
            Section("Aperçu") {
                PDFPreview(url: previewURL)
                    .frame(height: format.isSheet ? 400 : 180)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                printLabels()
            } label: {
                Label("Imprimer", systemImage: "printer")
            }
            .disabled(!printer.isAvailable || previewURL == nil)

            if let previewURL {
                ShareLink(item: previewURL) {
                    Label("Partager le PDF", systemImage: "square.and.arrow.up")
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            if printer.isAvailable {
                Text("« Imprimer » ouvre la fenêtre d'AirPrint : choisissez-y votre imprimante Wi-Fi. Pour une imprimante Bluetooth, passez par « Partager le PDF » et l'application du fabricant.")
            } else {
                Text("L'impression n'est pas disponible sur le simulateur. Utilisez « Partager le PDF » pour vérifier le rendu.")
            }
        }
    }

    // MARK: - Actions

    private func refreshPreview() {
        let data = LabelRenderer.render(
            products: [product],
            format: format,
            establishment: establishments.first,
            copies: copies
        )
        do {
            previewURL = try LabelRenderer.writeToTemporaryFile(data: data, name: "etiquette-\(product.identifier.uuidString.prefix(8))")
            errorMessage = nil
        } catch {
            errorMessage = "Aperçu impossible : \(error.localizedDescription)"
        }
    }

    private func printLabels() {
        let data = LabelRenderer.render(
            products: [product],
            format: format,
            establishment: establishments.first,
            copies: copies
        )
        do {
            try printer.send(
                pdf: data,
                jobName: "Étiquettes — \(product.name)",
                pageSize: format.pageSize
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
