//
//  ProductFormViewModel.swift
//  HACCPPocket
//
//  Création et modification d'un produit tracé. Gère le calcul automatique de
//  la DLC secondaire et l'intégration du scan d'étiquette (OCR + code-barres).
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProductFormViewModel {

    // MARK: - Dépendances

    private let modelContext: ModelContext
    private let existingProduct: TrackedProduct?

    // MARK: - État du formulaire

    var name: String
    var batchNumber: String
    var barcode: String
    var supplier: String
    var storage: StorageZone
    var openedAt: Date
    var shelfLifeDays: Int
    var notes: String

    /// DLC fournisseur : facultative, d'où l'interrupteur qui la gouverne.
    var hasSupplierExpiry: Bool
    var supplierExpiryDate: Date

    /// Photo de l'étiquette, conservée comme preuve.
    var labelPhotoData: Data?

    /// Permet de forcer une DLC secondaire différente du calcul automatique.
    var overridesSecondaryLimit: Bool
    var customSecondaryLimitDate: Date

    private(set) var errorMessage: String?
    private(set) var isScanning: Bool = false
    private(set) var lastScanResult: LabelScanResult?

    // MARK: - Initialisation

    init(
        product: TrackedProduct? = nil,
        context: ModelContext,
        preferences: UserPreferences = .shared
    ) {
        self.modelContext = context
        self.existingProduct = product

        if let product {
            self.name = product.name
            self.batchNumber = product.batchNumber
            self.barcode = product.barcode
            self.supplier = product.supplier
            self.storage = product.storage
            self.openedAt = product.openedAt
            self.notes = product.notes
            self.labelPhotoData = product.labelPhotoData
            self.hasSupplierExpiry = product.supplierExpiryDate != nil
            self.supplierExpiryDate = product.supplierExpiryDate ?? .now

            // On retrouve la durée de vie appliquée à l'origine.
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: product.openedAt),
                to: Calendar.current.startOfDay(for: product.secondaryLimitDate)
            ).day ?? preferences.defaultShelfLifeDays
            self.shelfLifeDays = max(0, days)

            self.overridesSecondaryLimit = false
            self.customSecondaryLimitDate = product.secondaryLimitDate
        } else {
            self.name = ""
            self.batchNumber = ""
            self.barcode = ""
            self.supplier = ""
            self.storage = .positiveCold
            self.openedAt = .now
            self.shelfLifeDays = preferences.defaultShelfLifeDays
            self.notes = ""
            self.labelPhotoData = nil
            self.hasSupplierExpiry = false
            self.supplierExpiryDate = .now
            self.overridesSecondaryLimit = false
            self.customSecondaryLimitDate = TrackedProduct.defaultLimitDate(
                openedAt: .now,
                days: preferences.defaultShelfLifeDays
            )
        }
    }

    var isEditing: Bool { existingProduct != nil }

    var title: String { isEditing ? "Modifier le produit" : "Nouveau produit entamé" }

    // MARK: - Calculs

    /// DLC secondaire calculée à partir de la date d'ouverture.
    var computedSecondaryLimit: Date {
        TrackedProduct.defaultLimitDate(openedAt: openedAt, days: shelfLifeDays)
    }

    var secondaryLimitDate: Date {
        overridesSecondaryLimit ? customSecondaryLimitDate : computedSecondaryLimit
    }

    /// Date réellement retenue : la plus contraignante des deux.
    var effectiveLimitDate: Date {
        guard hasSupplierExpiry else { return secondaryLimitDate }
        return min(supplierExpiryDate, secondaryLimitDate)
    }

    /// Signale à l'utilisateur que la DLC fournisseur prend le dessus.
    var supplierDateWins: Bool {
        hasSupplierExpiry && supplierExpiryDate < secondaryLimitDate
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Scan d'étiquette

    /// Analyse une photo d'étiquette et pré-remplit DLC et code-barres.
    /// Les champs déjà renseignés par l'utilisateur ne sont jamais écrasés.
    func scanLabel(imageData: Data) async {
        isScanning = true
        errorMessage = nil
        labelPhotoData = imageData

        do {
            let result = try await DateOCRService.scan(imageData: imageData)
            lastScanResult = result

            if let date = result.expiryDate, !hasSupplierExpiry {
                hasSupplierExpiry = true
                supplierExpiryDate = date
            }

            if let code = result.barcode, barcode.isEmpty {
                barcode = code
            }

            if result.isEmpty {
                errorMessage = "Aucune date ni code-barres détecté. Vous pouvez saisir la DLC à la main."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isScanning = false
    }

    // MARK: - Enregistrement

    @discardableResult
    func save() -> TrackedProduct? {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Le nom du produit est obligatoire."
            return nil
        }

        let product: TrackedProduct

        if let existing = existingProduct {
            existing.name = trimmedName
            existing.batchNumber = batchNumber
            existing.barcode = barcode
            existing.supplier = supplier
            existing.storage = storage
            existing.openedAt = openedAt
            existing.secondaryLimitDate = secondaryLimitDate
            existing.supplierExpiryDate = hasSupplierExpiry ? supplierExpiryDate : nil
            existing.labelPhotoData = labelPhotoData
            existing.notes = notes
            product = existing
        } else {
            let created = TrackedProduct(
                name: trimmedName,
                openedAt: openedAt,
                secondaryLimitDate: secondaryLimitDate,
                storage: storage,
                batchNumber: batchNumber,
                barcode: barcode,
                supplier: supplier,
                supplierExpiryDate: hasSupplierExpiry ? supplierExpiryDate : nil,
                labelPhotoData: labelPhotoData,
                notes: notes
            )
            modelContext.insert(created)
            product = created
        }

        do {
            try modelContext.save()
            return product
        } catch {
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
            return nil
        }
    }
}
