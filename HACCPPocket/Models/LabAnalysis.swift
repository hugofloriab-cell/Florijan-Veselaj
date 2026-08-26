//
//  LabAnalysis.swift
//  HACCPPocket
//
//  Analyses de laboratoire : surfaces, denrées, eau.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE LA RÈGLE DIT, ET CE QU'ELLE NE DIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le règlement (CE) n° 2073/2005 fixe les critères microbiologiques à
//  respecter — les seuils, pas les fréquences. Aucun texte n'impose à un
//  restaurant « une analyse de surface par mois ».
//
//  Ce que la règle impose vraiment : l'exploitant doit vérifier que son plan
//  fonctionne, prévoir dans son PMS les analyses qu'il juge nécessaires, et
//  pouvoir justifier la fréquence retenue. Un établissement qui n'analyse
//  jamais rien ne peut pas démontrer que ses procédures sont efficaces.
//
//  L'application propose donc un registre et un rappel d'échéance, sans
//  inventer une périodicité réglementaire qui n'existe pas.
//

import Foundation
import SwiftData

// MARK: - Nature du prélèvement

enum AnalysisKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case surface
    case foodProduct
    case water
    case hands
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .surface:     "Surface"
        case .foodProduct: "Denrée ou plat"
        case .water:       "Eau"
        case .hands:       "Mains d'un opérateur"
        case .other:       "Autre"
        }
    }

    var detail: String {
        switch self {
        case .surface:
            "Plan de travail, planche, trancheuse, poignée de chambre froide. Le prélèvement se fait après nettoyage et désinfection : c'est leur efficacité que l'on mesure."
        case .foodProduct:
            "Plat cuisiné, préparation froide, produit sensible. Prélevé tel qu'il est servi."
        case .water:
            "Eau du réseau interne, glaçons, eau d'un puits ou d'un forage."
        case .hands:
            "Prélèvement sur les mains, après lavage. Sert surtout à démontrer, en formation, que le geste fonctionne — ou pas."
        case .other:
            "Air, textiles, matériel spécifique."
        }
    }

    var systemImage: String {
        switch self {
        case .surface:     "square.grid.3x3"
        case .foodProduct: "takeoutbag.and.cup.and.straw"
        case .water:       "drop"
        case .hands:       "hand.raised"
        case .other:       "flask"
        }
    }
}

// MARK: - Résultat

enum AnalysisResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case satisfactory
    case acceptable
    case unsatisfactory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending:        "En attente"
        case .satisfactory:   "Satisfaisant"
        case .acceptable:     "Acceptable"
        case .unsatisfactory: "Non satisfaisant"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:        "clock"
        case .satisfactory:   "checkmark.seal.fill"
        case .acceptable:     "exclamationmark.circle.fill"
        case .unsatisfactory: "xmark.seal.fill"
        }
    }

    /// Un résultat non satisfaisant impose une action corrective écrite, au
    /// même titre qu'un écart de température.
    var requiresAction: Bool {
        self == .unsatisfactory || self == .acceptable
    }
}

// MARK: - Analyse

@Model
final class LabAnalysis {

    /// Ce qui a été prélevé : « planche à découper poisson », « lasagnes ».
    var sampleName: String = ""

    var kindRawValue: String = AnalysisKind.surface.rawValue

    /// Emplacement ou contexte du prélèvement.
    var location: String = ""

    var sampledAt: Date = Date.now

    /// Laboratoire ayant réalisé l'analyse.
    var laboratory: String = ""

    /// Numéro de rapport, pour retrouver la pièce chez le laboratoire.
    var reportReference: String = ""

    var resultRawValue: String = AnalysisResult.pending.rawValue

    /// Réception du résultat.
    var resultReceivedAt: Date?

    /// Germes recherchés et valeurs obtenues, recopiés du rapport.
    var findings: String = ""

    /// Obligatoire dès que le résultat n'est pas satisfaisant.
    var correctiveAction: String = ""

    /// Rapport du laboratoire.
    @Attribute(.externalStorage) var reportData: Data?

    /// Prochaine analyse prévue, selon la fréquence retenue au PMS.
    var nextDueDate: Date?

    var operatorName: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    init(
        sampleName: String = "",
        kind: AnalysisKind = .surface,
        location: String = "",
        sampledAt: Date = .now,
        laboratory: String = "",
        reportReference: String = "",
        result: AnalysisResult = .pending,
        resultReceivedAt: Date? = nil,
        findings: String = "",
        correctiveAction: String = "",
        reportData: Data? = nil,
        nextDueDate: Date? = nil,
        operatorName: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.sampleName = sampleName
        self.kindRawValue = kind.rawValue
        self.location = location
        self.sampledAt = sampledAt
        self.laboratory = laboratory
        self.reportReference = reportReference
        self.resultRawValue = result.rawValue
        self.resultReceivedAt = resultReceivedAt
        self.findings = findings
        self.correctiveAction = correctiveAction
        self.reportData = reportData
        self.nextDueDate = nextDueDate
        self.operatorName = operatorName
        self.notes = notes
        self.createdAt = createdAt
    }

    // MARK: - Accès typé

    var kind: AnalysisKind {
        get { AnalysisKind(rawValue: kindRawValue) ?? .surface }
        set { kindRawValue = newValue.rawValue }
    }

    var result: AnalysisResult {
        get { AnalysisResult(rawValue: resultRawValue) ?? .pending }
        set { resultRawValue = newValue.rawValue }
    }

    var displayName: String {
        sampleName.isEmpty ? kind.label : sampleName
    }

    var hasReport: Bool { reportData != nil }

    // MARK: - Suites

    private var hasCorrectiveAction: Bool {
        !correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Un mauvais résultat sans suite écrite est pire qu'une absence
    /// d'analyse : il prouve qu'on savait et qu'on n'a rien fait.
    var needsCorrectiveAction: Bool {
        result.requiresAction && !hasCorrectiveAction
    }

    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let nextDueDate else { return false }
        return calendar.startOfDay(for: nextDueDate) < calendar.startOfDay(for: reference)
    }

    var needsAction: Bool {
        result == .pending || needsCorrectiveAction || isOverdue()
    }

    var statusLabel: String {
        if result == .pending { return "Résultat attendu" }
        if needsCorrectiveAction { return "Suite à écrire" }
        if isOverdue() { return "Analyse à refaire" }
        return result.label
    }
}
