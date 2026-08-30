//
//  LabelPrintView.swift
//  HACCPPocket
//
//  Choix du format, aperçu et impression d'une étiquette.
//
//  L'écran ne connaît plus les produits entamés en particulier : il imprime
//  un `LabelContent`, d'où qu'il vienne. C'est ce qui permet aux plats témoins
//  d'utiliser les mêmes cinq formats — rouleaux thermiques et planche A4 —
//  sans qu'un second écran parte vivre sa vie.
//

import SwiftUI
import SwiftData
import PDFKit
import UIKit

struct LabelPrintView: View {

    @Environment(\.dismiss) private var dismiss

    @Query private var establishments: [Establishment]

    /// Ce qui sera imprimé.
    let content: LabelContent

    /// Nom du travail d'impression, affiché par AirPrint.
    let jobName: String

    /// Lignes d'information rappelées en haut de l'écran.
    let summary: [(label: String, value: String, systemImage: String)]

    init(
        content: LabelContent,
        jobName: String,
        summary: [(label: String, value: String, systemImage: String)]
    ) {
        self.content = content
        self.jobName = jobName
        self.summary = summary
    }

    /// Étiquette d'un produit entamé.
    init(product: TrackedProduct) {
        var lines: [(label: String, value: String, systemImage: String)] = [
            ("Produit", product.name, "shippingbox"),
            (
                "À consommer avant le",
                AppFormatters.shortDate(product.effectiveLimitDate),
                "calendar.badge.exclamationmark"
            )
        ]
        lines.append(("Stockage", product.storage.label, product.storage.systemImage))
        if !product.batchNumber.isEmpty {
            lines.append(("Lot", product.batchNumber, "number"))
        }
        if !product.allergens.isEmpty {
            lines.append((
                "Allergènes",
                Allergen.summary(of: product.allergens),
                "exclamationmark.triangle"
            ))
        }

        self.init(
            content: product.labelContent,
            jobName: "Étiquettes — \(product.name)",
            summary: lines
        )
    }

    /// Étiquette d'un plat témoin.
    init(sample: FoodSample) {
        var lines: [(label: String, value: String, systemImage: String)] = [
            ("Plat", sample.displayName, "takeoutbag.and.cup.and.straw"),
            (
                "Prélevé le",
                AppFormatters.dateAndTime(sample.collectedAt),
                "clock"
            ),
            (
                "À conserver jusqu'au",
                AppFormatters.shortDate(sample.disposalDate()),
                "calendar.badge.exclamationmark"
            )
        ]
        if !sample.serviceLabel.isEmpty {
            lines.append(("Service", sample.serviceLabel, "fork.knife"))
        }

        self.init(
            content: sample.labelContent,
            jobName: "Plat témoin — \(sample.displayName)",
            summary: lines
        )
    }

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
            ForEach(summary, id: \.label) { line in
                InfoRow(label: line.label, value: line.value, systemImage: line.systemImage)
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
            VStack(alignment: .leading, spacing: 4) {
                if format.supportsQRCode && content.qrPayload != nil {
                    Text("Un QR code de traçabilité est imprimé : le scanner depuis l'app rouvre la fiche du produit.")
                } else if content.qrPayload == nil {
                    Text("Cette étiquette ne porte pas de QR code : seul le texte est imprimé.")
                } else {
                    Text("Ce format est trop petit pour un QR code lisible : seul le texte est imprimé.")
                }

                // Se taire ici laisserait croire qu'un produit sans ligne
                // d'allergènes n'en contient pas.
                if !content.allergens.isEmpty && !format.fitsAllergenLine {
                    Label(
                        "Ce format est trop étroit pour la ligne d'allergènes. Choisissez 50 mm de large ou plus si vous voulez les voir imprimés.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
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
            contents: [content],
            format: format,
            establishment: establishments.first,
            copies: copies
        )
        do {
            previewURL = try LabelRenderer.writeToTemporaryFile(data: data, name: "etiquette-\(content.id.suffix(12))")
            errorMessage = nil
        } catch {
            errorMessage = "Aperçu impossible : \(error.localizedDescription)"
        }
    }

    private func printLabels() {
        let data = LabelRenderer.render(
            contents: [content],
            format: format,
            establishment: establishments.first,
            copies: copies
        )
        do {
            try printer.send(
                pdf: data,
                jobName: jobName,
                pageSize: format.pageSize
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
