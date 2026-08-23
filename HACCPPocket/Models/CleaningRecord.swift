//
//  CleaningRecord.swift
//  HACCPPocket
//
//  Trace d'exécution d'une opération de nettoyage : qui, quand, avec quel
//  produit. C'est la preuve que le plan de nettoyage est réellement appliqué.
//

import Foundation
import SwiftData

@Model
final class CleaningRecord {

    var completedAt: Date = Date.now

    /// Opérateur ayant réalisé l'opération.
    var operatorName: String = ""

    /// Produit réellement employé : on recopie celui de la tâche par défaut,
    /// mais il peut changer (rupture de stock, produit de remplacement).
    var productUsed: String = ""

    var comment: String = ""

    /// Photo facultative de la zone nettoyée.
    @Attribute(.externalStorage) var photoData: Data?

    var task: CleaningTask?

    init(
        task: CleaningTask?,
        completedAt: Date = .now,
        operatorName: String = "",
        productUsed: String? = nil,
        comment: String = "",
        photoData: Data? = nil
    ) {
        self.task = task
        self.completedAt = completedAt
        self.operatorName = operatorName
        self.productUsed = productUsed ?? task?.productUsed ?? ""
        self.comment = comment
        self.photoData = photoData
    }
}

// MARK: - Logique métier

extension CleaningRecord {

    /// Intitulé de la tâche associée, sécurisé si la relation est absente.
    var taskTitle: String {
        task?.title ?? "Opération supprimée"
    }

    /// Un enregistrement sans opérateur est incomplet pour la traçabilité.
    var isTraceable: Bool {
        !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
