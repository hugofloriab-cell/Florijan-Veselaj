//
//  DeliveryCheckViewModel.swift
//  HACCPPocket
//
//  Contrôle des marchandises à réception. Le seuil de température se déduit du
//  type de denrée, et un refus impose un motif écrit.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DeliveryCheckViewModel {

    /// Familles de denrées et seuil maximal admis à réception.
    enum GoodsCategory: String, CaseIterable, Identifiable {
        case chilled        // Frais : 0 à 4 °C
        case veryPerishable // Très périssable (viande hachée, poisson) : 2 °C
        case frozen         // Surgelé : -18 °C
        case ambient        // Épicerie sèche : pas de seuil

        var id: String { rawValue }

        var label: String {
            switch self {
            case .chilled:        "Frais"
            case .veryPerishable: "Très périssable"
            case .frozen:         "Surgelé"
            case .ambient:        "Épicerie sèche"
            }
        }

        /// Température maximale acceptée à réception, en °C.
        var temperatureLimit: Double? {
            switch self {
            case .chilled:        4
            case .veryPerishable: 2
            case .frozen:         -18
            case .ambient:        nil
            }
        }

        var requiresTemperature: Bool { temperatureLimit != nil }
    }

    private let modelContext: ModelContext
    private let existingCheck: DeliveryCheck?

    // MARK: - État du formulaire

    var supplierName: String
    var productLabel: String
    var batchNumber: String
    var category: GoodsCategory
    var temperatureText: String
    var receivedAt: Date
    var packagingIntact: Bool
    var labellingCompliant: Bool
    var decision: DeliveryDecision
    var reason: String
    var operatorName: String
    var notes: String
    var photoData: Data?

    private(set) var errorMessage: String?

    // MARK: - Initialisation

    init(
        check: DeliveryCheck? = nil,
        context: ModelContext,
        preferences: UserPreferences? = nil
    ) {
        let prefs = preferences ?? UserPreferences.shared

        self.modelContext = context
        self.existingCheck = check

        if let check {
            self.supplierName = check.supplierName
            self.productLabel = check.productLabel
            self.batchNumber = check.batchNumber
            self.category = GoodsCategory.allCases.first { $0.temperatureLimit == check.temperatureLimit } ?? .chilled
            self.temperatureText = check.temperature.map {
                $0.formatted(.number.precision(.fractionLength(1)))
            } ?? ""
            self.receivedAt = check.receivedAt
            self.packagingIntact = check.packagingIntact
            self.labellingCompliant = check.labellingCompliant
            self.decision = check.decision
            self.reason = check.reason
            self.operatorName = check.operatorName
            self.notes = check.notes
            self.photoData = check.photoData
        } else {
            self.supplierName = ""
            self.productLabel = ""
            self.batchNumber = ""
            self.category = .chilled
            self.temperatureText = ""
            self.receivedAt = .now
            self.packagingIntact = true
            self.labellingCompliant = true
            self.decision = .accepted
            self.reason = ""
            self.operatorName = prefs.operatorName
            self.notes = ""
            self.photoData = nil
        }
    }

    var isEditing: Bool { existingCheck != nil }

    // MARK: - Validation

    var temperature: Double? {
        AppFormatters.parseTemperature(temperatureText)
    }

    var temperatureLimit: Double? {
        category.temperatureLimit
    }

    var isTemperatureCompliant: Bool {
        guard let temperature, let temperatureLimit else { return true }
        return temperature <= temperatureLimit
    }

    /// Les trois points de contrôle réglementaires à réception.
    var isFullyCompliant: Bool {
        isTemperatureCompliant && packagingIntact && labellingCompliant
    }

    var anomalies: [String] {
        var found: [String] = []
        if !isTemperatureCompliant { found.append("Température hors seuil") }
        if !packagingIntact { found.append("Emballage endommagé") }
        if !labellingCompliant { found.append("Étiquetage non conforme") }
        return found
    }

    /// Décision suggérée : un refus est proposé dès qu'une anomalie apparaît,
    /// l'utilisateur reste libre de la modifier.
    var suggestedDecision: DeliveryDecision {
        isFullyCompliant ? .accepted : .refused
    }

    private var hasReason: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var requiresReason: Bool {
        decision.requiresReason
    }

    var canSave: Bool {
        guard !supplierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if category.requiresTemperature && temperature == nil { return false }
        if requiresReason && !hasReason { return false }
        return true
    }

    /// Motif pré-rempli à partir des anomalies détectées.
    func fillReasonFromAnomalies() {
        guard !anomalies.isEmpty else { return }
        reason = anomalies.joined(separator: ", ") + "."
    }

    // MARK: - Enregistrement

    @discardableResult
    func save() -> Bool {
        errorMessage = nil

        let trimmedSupplier = supplierName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSupplier.isEmpty else {
            errorMessage = "Le fournisseur est obligatoire."
            return false
        }

        if category.requiresTemperature && temperature == nil {
            errorMessage = "Relevez la température de la marchandise."
            return false
        }

        if requiresReason && !hasReason {
            errorMessage = "Un refus ou une réserve exige un motif écrit."
            return false
        }

        if let existing = existingCheck {
            existing.supplierName = trimmedSupplier
            existing.productLabel = productLabel
            existing.batchNumber = batchNumber
            existing.temperature = temperature
            existing.temperatureLimit = temperatureLimit
            existing.receivedAt = receivedAt
            existing.packagingIntact = packagingIntact
            existing.labellingCompliant = labellingCompliant
            existing.decision = decision
            existing.reason = reason
            existing.operatorName = operatorName
            existing.notes = notes
            existing.photoData = photoData
        } else {
            let check = DeliveryCheck(
                supplierName: trimmedSupplier,
                productLabel: productLabel,
                receivedAt: receivedAt,
                temperature: temperature,
                temperatureLimit: temperatureLimit,
                packagingIntact: packagingIntact,
                labellingCompliant: labellingCompliant,
                decision: decision,
                reason: reason,
                batchNumber: batchNumber,
                operatorName: operatorName,
                photoData: photoData,
                notes: notes
            )
            modelContext.insert(check)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
            return false
        }
    }
}
