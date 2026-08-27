//
//  DateOCRService.swift
//  HACCPPocket
//
//  Lecture d'une étiquette produit avec Vision : dénomination, numéro de lot,
//  DLC/DDM et code-barres. Tout le traitement est fait sur l'appareil : aucune
//  image ne part sur un réseau, ce qui règle à la fois la question du coût et
//  celle de la confidentialité.
//
//  Ce que la reconnaissance sait faire, et ce qu'elle ne sait pas :
//  une étiquette imprimée bien cadrée sort presque toujours juste ; une
//  étiquette froissée, sous film, ou marquée au jet d'encre sur un carton se
//  lit mal. L'écran propose donc toujours le résultat en pré-remplissage,
//  jamais en validation automatique.
//

import Foundation
import Vision

/// Résultat d'un scan d'étiquette. `Sendable` pour traverser proprement les
/// frontières de concurrence entre le traitement Vision et la vue.
struct LabelScanResult: Sendable, Equatable {
    var productName: String?
    var batchNumber: String?
    var expiryDate: Date?
    var barcode: String?
    var recognizedLines: [String]

    init(
        productName: String? = nil,
        batchNumber: String? = nil,
        expiryDate: Date? = nil,
        barcode: String? = nil,
        recognizedLines: [String] = []
    ) {
        self.productName = productName
        self.batchNumber = batchNumber
        self.expiryDate = expiryDate
        self.barcode = barcode
        self.recognizedLines = recognizedLines
    }

    var isEmpty: Bool {
        productName == nil && batchNumber == nil && expiryDate == nil && barcode == nil
    }

    /// Ce qui a été trouvé, pour le dire à l'utilisateur sans lui faire
    /// relire les champs un par un.
    var summary: String {
        var found: [String] = []
        if productName != nil { found.append("dénomination") }
        if batchNumber != nil { found.append("lot") }
        if expiryDate != nil { found.append("date") }
        if barcode != nil { found.append("code-barres") }
        return found.isEmpty ? "" : found.joined(separator: ", ")
    }

    static let empty = LabelScanResult()
}

enum LabelScanError: LocalizedError {
    case invalidImage
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Image illisible. Reprenez la photo en cadrant bien l'étiquette."
        case .visionFailed(let reason):
            "La reconnaissance a échoué : \(reason)"
        }
    }
}

enum DateOCRService {

    // MARK: - Point d'entrée

    /// Analyse une image d'étiquette. Le travail Vision est exécuté hors du
    /// thread principal pour ne pas figer l'interface pendant la reconnaissance.
    static func scan(imageData: Data, reference: Date = .now) async throws -> LabelScanResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try performScan(imageData: imageData, reference: reference)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Traitement Vision

    private static func performScan(imageData: Data, reference: Date) throws -> LabelScanResult {
        let handler = VNImageRequestHandler(data: imageData, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["fr-FR", "en-US"]
        // Désactivé volontairement : la correction linguistique transforme
        // volontiers « 12/03/26 » en mots et détruit les dates.
        textRequest.usesLanguageCorrection = false

        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.ean13, .ean8, .code128, .upce, .qr]

        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            throw LabelScanError.visionFailed(error.localizedDescription)
        }

        let lines = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }

        let barcode = (barcodeRequest.results ?? [])
            .compactMap(\.payloadStringValue)
            .first

        return LabelScanResult(
            productName: productName(in: lines),
            batchNumber: batchNumber(in: lines),
            expiryDate: expiryDate(in: lines, reference: reference),
            barcode: barcode,
            recognizedLines: lines
        )
    }

    // MARK: - Extraction du numéro de lot

    /// Mots et abréviations qui annoncent un numéro de lot sur un emballage.
    private static let batchKeywords = ["lot", "l.", "l:", "batch", "lot n", "n lot"]

    /// Cherche le numéro de lot.
    ///
    /// Sur un emballage, il suit presque toujours le mot « LOT » ou un « L »
    /// isolé. On récupère ce qui vient après, en s'arrêtant au premier blanc
    /// significatif : un lot est un bloc, pas une phrase.
    static func batchNumber(in lines: [String]) -> String? {
        for line in lines {
            let normalized = normalize(line)
            guard batchKeywords.contains(where: { normalized.contains($0) }) else { continue }

            // On travaille sur la ligne d'origine : un numéro de lot contient
            // des majuscules qui font partie de sa valeur.
            guard let candidate = trailingToken(of: line) else { continue }
            if isPlausibleBatch(candidate) { return candidate }
        }
        return nil
    }

    /// Renvoie ce qui suit le dernier séparateur de la ligne.
    private static func trailingToken(of line: String) -> String? {
        let separators = CharacterSet(charactersIn: " :.-—#")
        let parts = line
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Le mot clé lui-même ne nous intéresse pas : on prend le morceau
        // suivant, donc le dernier une fois les vides retirés.
        guard parts.count >= 2 else { return nil }
        return parts.last
    }

    /// Écarte les faux positifs les plus courants : une date, une masse, un
    /// prix. Un lot mêle en général chiffres et lettres, ou n'est que des
    /// chiffres mais assez long.
    private static func isPlausibleBatch(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 24 else { return false }

        // Une date déguisée en lot : on la laisse à l'extracteur de dates.
        if trimmed.contains("/") || trimmed.contains("\\") { return false }

        let hasDigit = trimmed.contains { $0.isNumber }
        guard hasDigit else { return false }

        let normalized = normalize(trimmed)
        let units = ["kg", "g", "ml", "cl", "eur", "€", "%"]
        if units.contains(where: { normalized.hasSuffix($0) }) { return false }

        return true
    }

    // MARK: - Extraction de la dénomination

    /// Lignes à ignorer quand on cherche le nom du produit.
    private static let namingNoise = [
        "lot", "dlc", "ddm", "consommer", "jusqu", "avant", "exp", "peremption",
        "conserver", "poids", "net", "kg", "eur", "prix", "www", "tel",
        "ingredient", "valeurs", "energie", "matieres", "glucides", "proteines",
        "sel", "fabrique", "emballe"
    ]

    /// Devine la dénomination du produit.
    ///
    /// Sur une étiquette, le nom est la ligne la plus longue composée surtout
    /// de lettres, dans le premier tiers du texte reconnu — Vision restitue
    /// les lignes de haut en bas. Cette heuristique se trompe, d'où le
    /// pré-remplissage plutôt que la validation automatique.
    static func productName(in lines: [String]) -> String? {
        let candidates = lines.prefix(max(3, lines.count / 2))

        var best: String?
        var bestScore = 0

        for line in candidates {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4, trimmed.count <= 60 else { continue }

            let normalized = normalize(trimmed)
            if namingNoise.contains(where: { normalized.contains($0) }) { continue }

            let letters = trimmed.filter { $0.isLetter }.count
            let digits = trimmed.filter { $0.isNumber }.count

            // Une ligne majoritairement chiffrée est un code, pas un nom.
            guard letters > digits * 2 else { continue }

            if letters > bestScore {
                bestScore = letters
                best = trimmed
            }
        }

        return best.map { cleanedName($0) }
    }

    /// Une dénomination tout en majuscules se lit mal dans une liste.
    private static func cleanedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:."))
        guard trimmed == trimmed.uppercased(with: AppFormatters.locale) else { return trimmed }
        return trimmed.capitalized(with: AppFormatters.locale)
    }

    // MARK: - Extraction de la date

    /// Mots qui précèdent presque toujours une date limite sur un emballage.
    private static let dateKeywords = [
        "dlc", "ddm", "consommer", "jusqu", "avant", "exp", "peremption",
        "use by", "best before", "a consommer"
    ]

    /// Cherche une date dans les lignes reconnues. Les lignes contenant un mot
    /// clé de DLC sont examinées en premier : sur un emballage, une étiquette
    /// porte souvent plusieurs dates (fabrication, lot, DLC).
    static func expiryDate(in lines: [String], reference: Date = .now) -> Date? {
        let normalized = lines.map { normalize($0) }

        let prioritized = normalized.filter { line in
            dateKeywords.contains { line.contains($0) }
        }

        for line in prioritized {
            if let date = parseDate(from: line, reference: reference) { return date }
        }
        for line in normalized {
            if let date = parseDate(from: line, reference: reference) { return date }
        }
        return nil
    }

    /// Minuscules et sans accents : simplifie toutes les expressions régulières.
    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    /// Reconnaît « 12/03/2026 », « 12-03-26 », « 12 mars 2026 » et « fin 03/2026 ».
    static func parseDate(from line: String, reference: Date = .now) -> Date? {
        let text = normalize(line)

        if let date = matchNumericDate(in: text, reference: reference) { return date }
        if let date = matchNamedMonthDate(in: text, reference: reference) { return date }
        if let date = matchMonthAndYear(in: text, reference: reference) { return date }
        return nil
    }

    // MARK: - Motifs

    private static func matchNumericDate(in text: String, reference: Date) -> Date? {
        let pattern = #"(\d{1,2})\s*[\/\.\-\s]\s*(\d{1,2})\s*[\/\.\-\s]\s*(\d{2,4})"#
        for groups in matches(pattern: pattern, in: text) where groups.count == 3 {
            guard let first = Int(groups[0]),
                  let second = Int(groups[1]),
                  let rawYear = Int(groups[2]) else { continue }

            // Format européen par défaut (jour/mois) ; on inverse si le second
            // nombre ne peut pas être un mois.
            let day = second > 12 && first <= 12 ? second : first
            let month = second > 12 && first <= 12 ? first : second

            if let date = makeDate(day: day, month: month, year: normalizeYear(rawYear), reference: reference) {
                return date
            }
        }
        return nil
    }

    private static let monthNames = [
        "janv": 1, "fevr": 2, "mars": 3, "avr": 4, "mai": 5, "juin": 6,
        "juil": 7, "aout": 8, "sept": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static func matchNamedMonthDate(in text: String, reference: Date) -> Date? {
        let pattern = #"(\d{1,2})\s*(janv|fevr|mars|avr|mai|juin|juil|aout|sept|oct|nov|dec)[a-z.]*\s*(\d{2,4})"#
        for groups in matches(pattern: pattern, in: text) where groups.count == 3 {
            guard let day = Int(groups[0]),
                  let month = monthNames[groups[1]],
                  let rawYear = Int(groups[2]) else { continue }

            if let date = makeDate(day: day, month: month, year: normalizeYear(rawYear), reference: reference) {
                return date
            }
        }
        return nil
    }

    /// « fin 03/2026 » : une DDM sans jour. On retient le dernier jour du mois,
    /// c'est la lecture la plus favorable et la plus courante.
    private static func matchMonthAndYear(in text: String, reference: Date) -> Date? {
        let pattern = #"(\d{1,2})\s*[\/\.\-]\s*(\d{4})"#
        for groups in matches(pattern: pattern, in: text) where groups.count == 2 {
            guard let month = Int(groups[0]), let year = Int(groups[1]), (1...12).contains(month) else {
                continue
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1

            let calendar = Calendar.current
            guard let firstDay = calendar.date(from: components),
                  let range = calendar.range(of: .day, in: .month, for: firstDay),
                  let lastDay = range.last,
                  let date = makeDate(day: lastDay, month: month, year: year, reference: reference) else {
                continue
            }
            return date
        }
        return nil
    }

    // MARK: - Utilitaires

    /// Renvoie, pour chaque correspondance, la liste de ses groupes capturés.
    private static func matches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let subRange = Range(match.range(at: index), in: text) else { return nil }
                return String(text[subRange])
            }
        }
    }

    /// « 26 » devient 2026. Les emballages n'impriment jamais un millésime du
    /// siècle dernier sur une date limite.
    private static func normalizeYear(_ value: Int) -> Int {
        value < 100 ? 2000 + value : value
    }

    /// Construit la date et vérifie qu'elle est plausible pour une DLC :
    /// pas plus de 2 ans dans le passé, pas plus de 10 ans dans le futur.
    private static func makeDate(day: Int, month: Int, year: Int, reference: Date) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 23
        components.minute = 59

        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              let lowerBound = calendar.date(byAdding: .year, value: -2, to: reference),
              let upperBound = calendar.date(byAdding: .year, value: 10, to: reference),
              date >= lowerBound, date <= upperBound else {
            return nil
        }
        return date
    }
}
