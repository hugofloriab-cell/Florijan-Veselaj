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

/// Valeurs proposées à la création d'un produit, typiquement issues d'un scan.
struct ProductPrefill: Identifiable, Equatable {
    let id = UUID()
    var name: String?
    var barcode: String?
    var supplier: String?
    var batchNumber: String?
    var supplierExpiryDate: Date?
    var shelfLifeDays: Int?
    var storage: StorageZone?
    /// Message expliquant d'où viennent les valeurs pré-remplies.
    var origin: String?
}

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

    /// Allergènes déclarés sur l'emballage. Ils alimenteront la fiche
    /// allergènes des plats qui utilisent ce produit.
    var allergens: Set<Allergen>

    /// Famille d'aliment choisie. `nil` tant que l'utilisateur saisit la durée
    /// à la main : on ne prétend pas deviner ce qu'il a en main.
    var category: FoodCategory?

    /// Permet de forcer une DLC secondaire différente du calcul automatique.
    var overridesSecondaryLimit: Bool
    var customSecondaryLimitDate: Date

    private(set) var errorMessage: String?
    private(set) var isScanning: Bool = false
    private(set) var lastScanResult: LabelScanResult?

    // MARK: - Initialisation

    /// Origine des valeurs pré-remplies, affichée en tête du formulaire.
    private(set) var prefillOrigin: String?

    init(
        product: TrackedProduct? = nil,
        prefill: ProductPrefill? = nil,
        context: ModelContext,
        preferences: UserPreferences? = nil
    ) {
        let prefs = preferences ?? UserPreferences.shared

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
            self.allergens = product.allergens
            self.category = nil
            self.hasSupplierExpiry = product.supplierExpiryDate != nil
            self.supplierExpiryDate = product.supplierExpiryDate ?? .now

            // On retrouve la durée de vie appliquée à l'origine.
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: product.openedAt),
                to: Calendar.current.startOfDay(for: product.secondaryLimitDate)
            ).day ?? prefs.defaultShelfLifeDays
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
            self.shelfLifeDays = prefs.defaultShelfLifeDays
            self.notes = ""
            self.labelPhotoData = nil
            self.allergens = []
            self.category = nil
            self.hasSupplierExpiry = false
            self.supplierExpiryDate = .now
            self.overridesSecondaryLimit = false
            self.customSecondaryLimitDate = TrackedProduct.defaultLimitDate(
                openedAt: .now,
                days: prefs.defaultShelfLifeDays
            )
        }

        if let prefill, product == nil {
            apply(prefill)
        }
    }

    /// Applique les valeurs d'un scan sans jamais écraser une saisie existante.
    private func apply(_ prefill: ProductPrefill) {
        if let value = prefill.name, name.isEmpty { name = value }
        if let value = prefill.barcode, barcode.isEmpty { barcode = value }
        if let value = prefill.supplier, supplier.isEmpty { supplier = value }
        if let value = prefill.batchNumber, batchNumber.isEmpty { batchNumber = value }
        if let value = prefill.storage { storage = value }
        if let value = prefill.shelfLifeDays { shelfLifeDays = value }

        if let value = prefill.supplierExpiryDate {
            hasSupplierExpiry = true
            supplierExpiryDate = value
        }

        prefillOrigin = prefill.origin
    }

    var isEditing: Bool { existingProduct != nil }

    // MARK: - Famille d'aliment

    /// Applique la durée d'usage de la famille choisie, et la zone de
    /// stockage qui va avec si l'utilisateur n'y a pas déjà touché.
    func apply(_ category: FoodCategory) {
        self.category = category
        shelfLifeDays = category.shelfLifeDays
        overridesSecondaryLimit = false

        if !isEditing {
            storage = category.suggestedStorage
        }
    }

    /// L'utilisateur a modifié la durée après avoir choisi une famille : la
    /// proposition ne correspond plus à ce qu'il a saisi.
    var hasCustomShelfLife: Bool {
        guard let category else { return false }
        return shelfLifeDays != category.shelfLifeDays
    }

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
            existing.allergens = allergens
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
                notes: notes,
                allergens: allergens
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
