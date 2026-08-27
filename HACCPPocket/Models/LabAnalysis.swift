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

// MARK: - Qui prélève, et qui lit

enum AnalysisMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Prélèvement envoyé à un laboratoire, qui rend un rapport.
    case laboratory
    /// Lame ou tube gélosé, prélevé et lu sur place.
    case agarSlide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .laboratory: "Laboratoire"
        case .agarSlide:  "Tube gélosé (auto-contrôle)"
        }
    }

    var systemImage: String {
        switch self {
        case .laboratory: "building.columns"
        case .agarSlide:  "testtube.2"
        }
    }

    /// ⚠️ Ce que vaut la méthode, dit franchement.
    ///
    /// Une lame gélosée lue en cuisine n'est pas une analyse au sens du
    /// règlement : pas de laboratoire accrédité, pas de germe identifié, pas
    /// de rapport opposable. C'est un outil de surveillance interne, et le
    /// présenter autrement exposerait l'utilisateur en contrôle.
    var evidenceNote: String {
        switch self {
        case .laboratory:
            return "Le rapport du laboratoire est une pièce opposable : il identifie les germes recherchés et donne des valeurs comparables aux critères réglementaires."
        case .agarSlide:
            return "Un tube gélosé lu sur place est un auto-contrôle, pas une analyse officielle. Il montre si le nettoyage fonctionne, il ne remplace pas un laboratoire quand un résultat opposable est nécessaire."
        }
    }
}

// MARK: - Lecture d'un tube gélosé

/// Densité de colonies lue par comparaison avec l'échelle du fabricant.
///
/// Les valeurs sont des ordres de grandeur en UFC/cm², pas des mesures :
/// c'est exactement ce que produit une lecture à l'œil, et prétendre à plus
/// de précision serait faux.
enum ColonyDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case low
    case moderate
    case high
    case veryHigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     "Aucune colonie visible"
        case .low:      "Quelques colonies"
        case .moderate: "Colonies nombreuses"
        case .high:     "Colonies très nombreuses"
        case .veryHigh: "Tapis de colonies"
        }
    }

    /// Ordre de grandeur affiché à côté du libellé.
    var magnitude: String {
        switch self {
        case .none:     "moins de 1 UFC/cm²"
        case .low:      "de l'ordre de 10 UFC/cm²"
        case .moderate: "de l'ordre de 100 UFC/cm²"
        case .high:     "de l'ordre de 1 000 UFC/cm²"
        case .veryHigh: "10 000 UFC/cm² ou plus"
        }
    }

    var systemImage: String {
        switch self {
        case .none:     "checkmark.seal.fill"
        case .low:      "checkmark.circle"
        case .moderate: "exclamationmark.circle.fill"
        case .high:     "exclamationmark.triangle.fill"
        case .veryHigh: "xmark.seal.fill"
        }
    }

    /// Verdict correspondant, dans le vocabulaire déjà utilisé par le
    /// registre. Les deux plages hautes appellent une action écrite.
    var result: AnalysisResult {
        switch self {
        case .none, .low:      return .satisfactory
        case .moderate:        return .acceptable
        case .high, .veryHigh: return .unsatisfactory
        }
    }

    var interpretation: String {
        switch self {
        case .none:
            return "Le nettoyage et la désinfection font leur travail sur cette surface."
        case .low:
            return "Résultat correct. Quelques colonies sur une surface de cuisine sont attendues."
        case .moderate:
            return "Le protocole laisse passer quelque chose : temps de contact trop court, dilution trop faible, ou surface mal rincée avant désinfection. Reprenez le nettoyage et recontrôlez."
        case .high:
            return "Le nettoyage de cette surface ne fonctionne pas. Reprenez le protocole entièrement et notez ce que vous changez."
        case .veryHigh:
            return "Surface à retirer du service jusqu'à nouveau contrôle. Une densité pareille signale souvent un support abîmé — planche entaillée, joint fissuré — qu'aucun produit ne rattrape."
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

    /// Prélèvement envoyé au laboratoire, ou tube gélosé lu sur place.
    var methodRawValue: String = AnalysisMethod.laboratory.rawValue

    /// Laboratoire ayant réalisé l'analyse. Vide sur un auto-contrôle.
    var laboratory: String = ""

    // MARK: Incubation d'un tube gélosé

    /// Mise à l'étuve. `nil` hors auto-contrôle.
    var incubationStartedAt: Date?

    /// Durée d'incubation retenue, en heures. Les fabricants indiquent le
    /// plus souvent 48 h à 30 °C pour la flore totale.
    var incubationHours: Int = 48

    var incubationTemperature: Double = 30

    /// Lecture effective, qui peut arriver plus tard que prévu.
    var readAt: Date?

    /// Densité lue par comparaison avec l'échelle du fabricant.
    var colonyDensityRawValue: String = ""

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
        method: AnalysisMethod = .laboratory,
        laboratory: String = "",
        incubationStartedAt: Date? = nil,
        incubationHours: Int = 48,
        incubationTemperature: Double = 30,
        readAt: Date? = nil,
        colonyDensity: ColonyDensity? = nil,
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
        self.methodRawValue = method.rawValue
        self.laboratory = laboratory
        self.incubationStartedAt = incubationStartedAt
        self.incubationHours = incubationHours
        self.incubationTemperature = incubationTemperature
        self.readAt = readAt
        self.colonyDensityRawValue = colonyDensity?.rawValue ?? ""
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

    var method: AnalysisMethod {
        get { AnalysisMethod(rawValue: methodRawValue) ?? .laboratory }
        set { methodRawValue = newValue.rawValue }
    }

    var colonyDensity: ColonyDensity? {
        get { ColonyDensity(rawValue: colonyDensityRawValue) }
        set { colonyDensityRawValue = newValue?.rawValue ?? "" }
    }

    var result: AnalysisResult {
        get { AnalysisResult(rawValue: resultRawValue) ?? .pending }
        set { resultRawValue = newValue.rawValue }
    }

    var displayName: String {
        sampleName.isEmpty ? kind.label : sampleName
    }

    var hasReport: Bool { reportData != nil }

    // MARK: - Incubation

    /// Date à laquelle le tube gélosé peut être lu.
    var incubationEndsAt: Date? {
        guard method == .agarSlide, let incubationStartedAt else { return nil }
        return Calendar.current.date(byAdding: .hour, value: incubationHours, to: incubationStartedAt)
    }

    /// Incubation lancée, pas encore lue, et le temps n'est pas écoulé.
    func isIncubating(at reference: Date = .now) -> Bool {
        guard readAt == nil, let end = incubationEndsAt else { return false }
        return reference < end
    }

    /// L'incubation est terminée mais personne n'a lu le tube. C'est le
    /// moment où un auto-contrôle se perd : la lame reste dans l'étuve, et
    /// trois jours plus tard elle ne veut plus rien dire.
    func awaitsReading(at reference: Date = .now) -> Bool {
        guard method == .agarSlide, readAt == nil, let end = incubationEndsAt else { return false }
        return reference >= end
    }

    /// Une lecture faite bien après la fin d'incubation surestime la flore :
    /// les colonies continuent de pousser. On le signale plutôt que de
    /// laisser interpréter un chiffre faux.
    func readTooLate(tolerance: TimeInterval = 12 * 3600) -> Bool {
        guard let readAt, let end = incubationEndsAt else { return false }
        return readAt.timeIntervalSince(end) > tolerance
    }

    /// Reporte la densité lue sur le résultat du registre.
    func applyColonyReading(_ density: ColonyDensity, at date: Date = .now) {
        colonyDensity = density
        readAt = date
        result = density.result
        resultReceivedAt = date
    }

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
        if awaitsReading() { return "Tube à lire" }
        if isIncubating() { return "En incubation" }
        if result == .pending { return "Résultat attendu" }
        if needsCorrectiveAction { return "Suite à écrire" }
        if isOverdue() { return "Analyse à refaire" }
        return result.label
    }
}
