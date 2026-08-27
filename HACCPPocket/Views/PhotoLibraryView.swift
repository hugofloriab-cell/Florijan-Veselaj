//
//  PhotoLibraryView.swift
//  HACCPPocket
//
//  L'album : toutes les photos prises par l'application, au même endroit.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI UNE PAGE SÉPARÉE, ET PAS DANS LE REGISTRE MENSUEL
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le registre mensuel se lit : des lignes, des températures, des décisions,
//  sur quelques pages qu'un contrôleur parcourt en dix minutes. Y intercaler
//  deux cents photos de bons de livraison le rendrait illisible, impossible à
//  imprimer, et noierait ce qui compte.
//
//  Les photos ne sont pourtant pas décoratives : ce sont les preuves. Elles
//  ont donc leur propre page, consultable et imprimable séparément, qu'on
//  sort seulement si on la demande.
//
//  ─────────────────────────────────────────────────────────────────────────
//  RIEN N'EST DUPLIQUÉ
//  ─────────────────────────────────────────────────────────────────────────
//
//  Cet écran ne stocke aucune image : il relit celles qui vivent déjà dans
//  les registres et les présente ensemble. Supprimer une réception fait donc
//  disparaître ses photos de l'album, ce qui est le comportement voulu — une
//  preuve orpheline ne prouve rien.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Une entrée de l'album

/// Photo présentée dans l'album, quelle que soit sa provenance.
struct PhotoEntry: Identifiable, Hashable {

    enum Source: String, CaseIterable, Identifiable, Hashable {
        case delivery
        case cleaning
        case product
        case cleaningProduct
        case pest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .delivery:        "Réceptions"
            case .cleaning:        "Nettoyage"
            case .product:         "Étiquettes produits"
            case .cleaningProduct: "Produits d'entretien"
            case .pest:            "Nuisibles"
            }
        }

        var systemImage: String {
            switch self {
            case .delivery:        "truck.box"
            case .cleaning:        "sparkles"
            case .product:         "shippingbox"
            case .cleaningProduct: "bubbles.and.sparkles"
            case .pest:            "ant"
            }
        }

        var tint: Color {
            switch self {
            case .delivery:        .teal
            case .cleaning:        .blue
            case .product:         .orange
            case .cleaningProduct: .mint
            case .pest:            .brown
            }
        }
    }

    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let capturedAt: Date
    let data: Data

    #if canImport(UIKit)
    var image: UIImage? { UIImage(data: data) }
    #endif
}

// MARK: - Écran

struct PhotoLibraryView: View {

    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse)
    private var deliveries: [DeliveryCheck]

    @Query private var cleaningTasks: [CleaningTask]

    @Query(sort: \TrackedProduct.openedAt, order: .reverse)
    private var products: [TrackedProduct]

    @Query private var cleaningProducts: [CleaningProduct]

    @Query(sort: \PestControlVisit.visitedAt, order: .reverse)
    private var pestVisits: [PestControlVisit]

    @Query private var establishments: [Establishment]

    @State private var selectedSources: Set<PhotoEntry.Source> = []
    @State private var preview: PhotoEntry?
    @State private var albumURL: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                if entries.isEmpty {
                    emptyState
                } else {
                    filterBar
                    grid
                    exportCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { entry in
            PhotoPreviewView(entry: entry)
        }
        .alert("Album", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("Fermer", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: Contenu

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucune photo", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Les photos prises lors des réceptions, des nettoyages et sur les étiquettes se rassemblent ici. Elles ne figurent pas dans le registre mensuel, mais s'impriment à part si on vous les demande.")
        }
        .padding(.top, 40)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "Tout", count: allEntries.count)

                ForEach(availableSources) { source in
                    filterChip(source, label: source.label, count: count(of: source))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ source: PhotoEntry.Source?, label: String, count: Int) -> some View {
        let isOn: Bool = {
            guard let source else { return selectedSources.isEmpty }
            return selectedSources.contains(source)
        }()

        return Button {
            toggle(source)
        } label: {
            HStack(spacing: 5) {
                if let source {
                    Image(systemName: source.systemImage)
                        .font(.caption2)
                }
                Text(label)
                Text("\(count)")
                    .foregroundStyle(isOn ? .white.opacity(0.75) : .secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isOn ? (source?.tint ?? Color.brand) : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ source: PhotoEntry.Source?) {
        guard let source else {
            selectedSources.removeAll()
            return
        }
        if selectedSources.contains(source) {
            selectedSources.remove(source)
        } else {
            selectedSources.insert(source)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(entries) { entry in
                Button {
                    preview = entry
                } label: {
                    thumbnail(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thumbnail(_ entry: PhotoEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                #if canImport(UIKit)
                if let image = entry.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 104)
                        .clipped()
                } else {
                    placeholder
                }
                #else
                placeholder
                #endif

                Image(systemName: entry.source.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(entry.source.tint, in: Circle())
                    .padding(6)
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(entry.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)

            Text(AppFormatters.shortDate(entry.capturedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(.tertiarySystemGroupedBackground))
            .frame(height: 104)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: Impression

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Imprimer l'album")

            Text("\(entries.count) photo(s) sur \(allEntries.count), dans l'ordre où elles ont été prises. Chaque planche porte la date, l'origine et l'établissement — ce qui est demandé lors d'un contrôle.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                prepareAlbum()
            } label: {
                if isPreparing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Préparation…")
                    }
                } else {
                    Label("Préparer le document", systemImage: "doc.text")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPreparing || entries.isEmpty)

            if let albumURL {
                ShareLink(item: albumURL) {
                    Label("Imprimer ou partager", systemImage: "printer")
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func prepareAlbum() {
        isPreparing = true
        let album = PhotoAlbum(entries: entries, establishment: establishments.first)

        Task { @MainActor in
            await Task.yield()
            do {
                albumURL = try PhotoAlbumService.render(album)
            } catch {
                errorMessage = "Le document n'a pas pu être créé. \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: Collecte

    /// Sources réellement représentées : afficher un filtre vide n'aide
    /// personne.
    private var availableSources: [PhotoEntry.Source] {
        let present = Set(allEntries.map(\.source))
        return PhotoEntry.Source.allCases.filter { present.contains($0) }
    }

    private func count(of source: PhotoEntry.Source) -> Int {
        allEntries.filter { $0.source == source }.count
    }

    private var entries: [PhotoEntry] {
        guard !selectedSources.isEmpty else { return allEntries }
        return allEntries.filter { selectedSources.contains($0.source) }
    }

    /// Toutes les photos des registres, la plus récente en tête.
    ///
    /// Assemblée section par section plutôt qu'en une seule expression : une
    /// concaténation de cinq tableaux issus de `map` et `flatMap` est
    /// exactement le genre d'expression que le compilateur n'arrive plus à
    /// résoudre en un temps raisonnable.
    private var allEntries: [PhotoEntry] {
        var found: [PhotoEntry] = []

        for delivery in deliveries {
            for document in delivery.documents {
                guard let data = document.photoData else { continue }
                found.append(
                    PhotoEntry(
                        id: "delivery-doc-\(document.persistentModelID.hashValue)",
                        source: .delivery,
                        title: document.kind.label,
                        subtitle: delivery.supplierName,
                        capturedAt: document.capturedAt,
                        data: data
                    )
                )
            }

            if let data = delivery.photoData {
                found.append(
                    PhotoEntry(
                        id: "delivery-\(delivery.persistentModelID.hashValue)",
                        source: .delivery,
                        title: "Photo de réception",
                        subtitle: delivery.supplierName,
                        capturedAt: delivery.receivedAt,
                        data: data
                    )
                )
            }
        }

        for task in cleaningTasks {
            for record in task.records {
                guard let data = record.photoData else { continue }
                found.append(
                    PhotoEntry(
                        id: "cleaning-\(record.persistentModelID.hashValue)",
                        source: .cleaning,
                        title: task.title,
                        subtitle: record.operatorName,
                        capturedAt: record.completedAt,
                        data: data
                    )
                )
            }
        }

        for product in products {
            guard let data = product.labelPhotoData else { continue }
            found.append(
                PhotoEntry(
                    id: "product-\(product.persistentModelID.hashValue)",
                    source: .product,
                    title: product.name,
                    subtitle: product.batchNumber,
                    capturedAt: product.openedAt,
                    data: data
                )
            )
        }

        for product in cleaningProducts {
            guard let data = product.containerPhotoData else { continue }
            found.append(
                PhotoEntry(
                    id: "cleaning-product-\(product.persistentModelID.hashValue)",
                    source: .cleaningProduct,
                    title: product.displayName,
                    subtitle: product.kind.label,
                    capturedAt: product.updatedAt,
                    data: data
                )
            )
        }

        for visit in pestVisits {
            guard let data = visit.reportPhotoData else { continue }
            found.append(
                PhotoEntry(
                    id: "pest-\(visit.persistentModelID.hashValue)",
                    source: .pest,
                    title: "Passage \(visit.company)",
                    subtitle: visit.technician,
                    capturedAt: visit.visitedAt,
                    data: data
                )
            )
        }

        return found.sorted { $0.capturedAt > $1.capturedAt }
    }
}

// MARK: - Aperçu plein écran

struct PhotoPreviewView: View {

    @Environment(\.dismiss) private var dismiss

    let entry: PhotoEntry

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    #if canImport(UIKit)
                    if let image = entry.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    #endif

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Origine", value: entry.source.label)
                        if !entry.subtitle.isEmpty {
                            LabeledContent("Détail", value: entry.subtitle)
                        }
                        LabeledContent("Prise le", value: AppFormatters.dateAndTime(entry.capturedAt))
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }
                .padding(16)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
