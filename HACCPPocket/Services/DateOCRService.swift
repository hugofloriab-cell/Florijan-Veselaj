//
//  DateOCRService.swift
//  HACCPPocket
//
//  Lecture d'une étiquette produit avec Vision : reconnaissance de la DLC/DDM
//  et du code-barres. Tout le traitement est fait sur l'appareil, aucune image
//  n'est envoyée nulle part.
//

import Foundation
import Vision

/// Résultat d'un scan d'étiquette. `Sendable` pour traverser proprement les
/// frontières de concurrence entre le traitement Vision et la vue.
struct LabelScanResult: Sendable, Equatable {
    var expiryDate: Date?
    var barcode: String?
    var recognizedLines: [String]

    var isEmpty: Bool {
        expiryDate == nil && barcode == nil
    }

    static let empty = LabelScanResult(expiryDate: nil, barcode: nil, recognizedLines: [])
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
            expiryDate: expiryDate(in: lines, reference: reference),
            barcode: barcode,
            recognizedLines: lines
        )
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
