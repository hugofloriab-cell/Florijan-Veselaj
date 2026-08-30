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

import CoreGraphics
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

        // La géométrie est conservée : sur un emballage, la dénomination est
        // le texte le plus grand. Sans cette information il ne reste que la
        // longueur de la ligne, et la ligne la plus longue d'une étiquette
        // est presque toujours une mention nutritionnelle.
        var observed: [RecognizedLine] = []

        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            observed.append(
                RecognizedLine(
                    text: candidate.string,
                    height: observation.boundingBox.height,
                    verticalPosition: observation.boundingBox.midY
                )
            )
        }

        let lines = observed.map(\.text)

        let barcode = (barcodeRequest.results ?? [])
            .compactMap(\.payloadStringValue)
            .first

        return LabelScanResult(
            productName: productName(in: observed),
            batchNumber: batchNumber(in: lines, barcode: barcode),
            expiryDate: expiryDate(in: lines, reference: reference),
            barcode: barcode,
            recognizedLines: lines
        )
    }

    /// Une ligne reconnue, avec ce qu'il faut pour la juger.
    struct RecognizedLine: Sendable {
        let text: String
        /// Hauteur du texte, rapportée à celle de l'image.
        let height: CGFloat
        /// 1 en haut de l'image, 0 en bas.
        let verticalPosition: CGFloat
    }

    // MARK: - Extraction du numéro de lot

    /// Cherche le numéro de lot.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// CE QUI A ÉTÉ CORRIGÉ LE 30 AOÛT 2026
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// La première version cherchait « lot », « l. » ou « l: » n'importe où
    /// dans la ligne, y compris au milieu d'un mot. Sur un sachet de thé
    /// matcha, elle a rendu le code-barres — 3560467100042 — comme numéro de
    /// lot. Un code-barres identifie une référence commerciale, jamais un
    /// lot de fabrication : les confondre rendrait un retrait impossible.
    ///
    /// Le mot clé doit désormais être un mot entier, le code-barres déjà lu
    /// est refusé, et une suite de 12 à 14 chiffres — la forme d'un EAN — est
    /// écartée même sans code-barres détecté.
    static func batchNumber(in lines: [String], barcode: String? = nil) -> String? {
        for line in lines {
            guard hasBatchKeyword(line) else { continue }
            guard let candidate = trailingToken(of: line) else { continue }
            guard isPlausibleBatch(candidate, barcode: barcode) else { continue }
            return candidate
        }
        return nil
    }

    /// Le mot clé doit être isolé : « lot » dans « pilotage » n'annonce rien.
    private static func hasBatchKeyword(_ line: String) -> Bool {
        let normalized = normalize(line)
        let patterns = [
            "\\blot\\b",
            "\\bbatch\\b",
            "\\bl\\s*[:.]",
            "\\bn\\s*lot\\b"
        ]
        return patterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Renvoie la valeur qui suit le mot clé.
    ///
    /// Découper sur les tirets couperait « L24-0917 » en deux et ne garderait
    /// que « 0917 » : beaucoup de lots portent un tiret, et un lot tronqué ne
    /// permet aucun retrait.
    private static func trailingToken(of line: String) -> String? {
        let normalized = normalize(line)
        let patterns = ["\\blot\\b", "\\bbatch\\b", "\\bn\\s*lot\\b", "\\bl\\s*[:.]"]

        var cut: String.Index?
        for pattern in patterns {
            if let range = normalized.range(of: pattern, options: .regularExpression) {
                cut = range.upperBound
                break
            }
        }

        guard let cut else { return nil }

        // `normalize` conserve le nombre de caractères : la position trouvée
        // sur la version normalisée vaut pour la ligne d'origine, dont on a
        // besoin car un lot contient des majuscules qui font sa valeur.
        guard normalized.count == line.count else { return nil }
        let offset = normalized.distance(from: normalized.startIndex, to: cut)
        let start = line.index(line.startIndex, offsetBy: offset)

        let remainder = line[start...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " :.-—#°"))

        // « LOT N° AB-2024-117 » : sans ce saut, on renverrait « N° ».
        let markers: Set<String> = ["n", "no", "n°", "num", "numero", "num."]
        let tokens = remainder
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ":.-—#°")) }
            .filter { !$0.isEmpty }

        for token in tokens where !markers.contains(normalize(token)) {
            return token
        }
        return nil
    }

    /// Écarte les faux positifs : code-barres, date, masse, prix.
    private static func isPlausibleBatch(_ token: String, barcode: String?) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 24 else { return false }

        // Le code-barres déjà reconnu n'est pas un lot.
        if let barcode, trimmed == barcode { return false }

        // Une suite de 12 à 14 chiffres est un code article, pas un lot.
        let digitsOnly = trimmed.allSatisfy { $0.isNumber }
        if digitsOnly && trimmed.count >= 12 { return false }

        // Une date déguisée en lot : on la laisse à l'extracteur de dates.
        if trimmed.contains("/") { return false }

        guard trimmed.contains(where: { $0.isNumber }) else { return false }

        let normalized = normalize(trimmed)
        let units = ["kg", "g", "ml", "cl", "l", "eur", "€", "%"]
        if units.contains(where: { normalized.hasSuffix($0) }) { return false }

        return true
    }

    // MARK: - Extraction de la dénomination

    /// Mentions longues et sans ambiguïté : leur simple présence dans la
    /// ligne suffit à l'écarter.
    private static let strongNoise = [
        "consommer", "peremption", "conservation", "apres ouverture",
        "ingredient", "nutritionnel", "valeurs nutrition", "energie",
        "matieres grasses", "glucides", "carbohydrate", "proteines", "protein",
        "lipides", "sucres", "sugar", "fibres", "sodium", "including",
        "portion", "fabrique", "emballe", "distribue", "agriculture biologique",
        "www", "@"
    ]

    /// Mots courts qui n'écartent la ligne que s'ils y figurent seuls.
    ///
    /// « eur » cherché en sous-chaîne rejetait « Beurre doux », et « sel »
    /// rejetait « Sel de Guérande » — deux produits parfaitement ordinaires.
    /// Le classement se faisant désormais sur la taille du texte, ce filtre
    /// n'a plus besoin d'être agressif : il ne sert qu'à départager.
    private static let wordNoise = [
        "lot", "dlc", "ddm", "exp", "net", "poids", "contenance", "volume",
        "eur", "prix", "tel", "kcal", "kj", "dont", "traces", "origine",
        "importe", "certifie", "organisme"
    ]

    /// Devine la dénomination du produit.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// CE QUI A ÉTÉ CORRIGÉ LE 30 AOÛT 2026
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// La première version prenait la ligne la plus longue du haut du texte.
    /// Sur un sachet de matcha, elle a rendu :
    ///
    ///     « de ras situres/including saturated (atty acids »
    ///
    /// c'est-à-dire une ligne du tableau nutritionnel, mal lue. Une ligne de
    /// tableau nutritionnel est longue par nature : la longueur était le
    /// mauvais critère depuis le début.
    ///
    /// Le bon critère est la TAILLE du texte. Sur un emballage, la
    /// dénomination est ce qui est écrit en plus gros — c'est même la seule
    /// règle typographique que tous les conditionnements respectent.
    ///
    /// À défaut de candidat convaincant, la fonction ne rend rien. Sur un
    /// registre sanitaire, un champ vide se remarque et se corrige ; une
    /// dénomination fausse est recopiée telle quelle et fait foi.
    static func productName(in lines: [RecognizedLine]) -> String? {
        let candidates = lines.filter { isPlausibleName($0.text) }
        guard !candidates.isEmpty else { return nil }

        // À taille comparable, la ligne la plus haute l'emporte : une
        // dénomination est en tête de l'emballage, les mentions de service
        // sont en bas. Le seuil de 15 % évite de départager sur du bruit de
        // mesure.
        let best = candidates.max { left, right in
            if abs(left.height - right.height) > max(left.height, right.height) * 0.15 {
                return left.height < right.height
            }
            return left.verticalPosition < right.verticalPosition
        }

        guard let best else { return nil }

        // Un texte minuscule n'est jamais une dénomination : sous ce seuil,
        // c'est du texte de tableau, et mieux vaut ne rien proposer.
        guard best.height >= 0.02 else { return nil }

        return cleanedName(best.text)
    }

    private static func isPlausibleName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 48 else { return false }

        // Une ligne bilingue séparée par une barre oblique vient du tableau
        // nutritionnel, jamais de la dénomination.
        if trimmed.contains("/") { return false }

        let normalized = normalize(trimmed)
        if strongNoise.contains(where: { normalized.contains($0) }) { return false }
        if wordNoise.contains(where: { containsWord($0, in: normalized) }) { return false }

        let letters = trimmed.filter(\.isLetter).count
        let digits = trimmed.filter(\.isNumber).count
        guard letters >= 3, letters > digits * 2 else { return false }

        // Trop de caractères qui ne sont ni lettre, ni chiffre, ni espace :
        // la ligne est mal lue, et la recopier serait pire que rien.
        let noise = trimmed.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }.count
        guard noise * 4 <= trimmed.count else { return false }

        return true
    }

    /// Le mot figure-t-il seul, et non au milieu d'un autre ?
    private static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: "\\b" + word + "\\b", options: .regularExpression) != nil
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
