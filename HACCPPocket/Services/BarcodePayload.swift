//
//  BarcodePayload.swift
//  HACCPPocket
//
//  Lecture des codes-barres professionnels.
//
//  Un EAN-13 de produit grand public n'encode qu'une identité : il ne contient
//  aucune date. En revanche les GS1-128 et DataMatrix imprimés sur les cartons
//  fournisseurs portent des champs normalisés, dont la date limite et le lot.
//  C'est ce que ce fichier sait extraire — et rien d'autre : on n'invente
//  jamais une DLC.
//

import Foundation

/// Ce qu'un code-barres a réellement livré.
struct BarcodeReading: Equatable {
    /// Code brut, tel que scanné.
    var rawValue: String
    /// Identité produit : GTIN pour un GS1, code complet sinon.
    var productCode: String
    /// Date limite de consommation, présente uniquement sur les codes GS1.
    var expiryDate: Date?
    /// Date de durabilité minimale (DDM), champ GS1 distinct de la DLC.
    var bestBeforeDate: Date?
    var batchNumber: String?

    var carriesDate: Bool { expiryDate != nil || bestBeforeDate != nil }

    /// La date la plus contraignante parmi celles fournies.
    var mostRestrictiveDate: Date? {
        [expiryDate, bestBeforeDate].compactMap { $0 }.min()
    }
}

enum BarcodePayload {

    /// Séparateur de champ des codes GS1 (FNC1), transmis par les scanners
    /// comme le caractère de contrôle Group Separator.
    private static let groupSeparator: Character = "\u{1D}"

    /// Identifiants d'application à longueur fixe que nous exploitons.
    /// La valeur est la longueur des données qui suivent l'identifiant.
    private static let fixedLengthAIs: [String: Int] = [
        "00": 18,   // SSCC
        "01": 14,   // GTIN
        "11": 6,    // Date de production
        "13": 6,    // Date de conditionnement
        "15": 6,    // DDM
        "17": 6,    // Date limite de consommation
        "20": 2     // Variante produit
    ]

    /// Identifiants à longueur variable, terminés par un séparateur ou la fin.
    private static let variableLengthAIs: Set<String> = ["10", "21", "240", "30", "37"]

    // MARK: - Point d'entrée

    static func parse(_ scanned: String) -> BarcodeReading {
        let raw = scanned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Les codes GS1 commencent par un identifiant d'application ;
        // un EAN-13 nu, lui, ne fait que 8 ou 13 chiffres.
        if let gs1 = parseGS1(raw) { return gs1 }

        return BarcodeReading(rawValue: raw, productCode: raw)
    }

    // MARK: - GS1

    private static func parseGS1(_ raw: String) -> BarcodeReading? {
        // Certains scanners préfixent la chaîne d'un « ]C1 » ou « ]d2 ».
        var payload = raw
        if payload.hasPrefix("]") { payload = String(payload.dropFirst(3)) }

        var reading = BarcodeReading(rawValue: raw, productCode: raw)
        var index = payload.startIndex
        var foundAnyField = false

        while index < payload.endIndex {
            // Un séparateur isolé : on l'absorbe.
            if payload[index] == groupSeparator {
                index = payload.index(after: index)
                continue
            }

            guard let (identifier, afterIdentifier) = readIdentifier(in: payload, from: index) else {
                break
            }

            if let length = fixedLengthAIs[identifier] {
                guard let end = payload.index(afterIdentifier, offsetBy: length, limitedBy: payload.endIndex),
                      payload.distance(from: afterIdentifier, to: end) == length else {
                    break
                }
                apply(identifier: identifier, value: String(payload[afterIdentifier..<end]), to: &reading)
                index = end
                foundAnyField = true

            } else if variableLengthAIs.contains(identifier) {
                let end = payload[afterIdentifier...].firstIndex(of: groupSeparator) ?? payload.endIndex
                apply(identifier: identifier, value: String(payload[afterIdentifier..<end]), to: &reading)
                index = end
                foundAnyField = true

            } else {
                // Identifiant inconnu : on ne devine pas, on s'arrête.
                break
            }
        }

        return foundAnyField ? reading : nil
    }

    /// Lit un identifiant d'application de 2 puis 3 caractères.
    private static func readIdentifier(
        in payload: String,
        from index: String.Index
    ) -> (String, String.Index)? {
        guard let twoEnd = payload.index(index, offsetBy: 2, limitedBy: payload.endIndex) else {
            return nil
        }
        let two = String(payload[index..<twoEnd])
        guard two.allSatisfy(\.isNumber) else { return nil }

        if fixedLengthAIs[two] != nil || variableLengthAIs.contains(two) {
            return (two, twoEnd)
        }

        guard let threeEnd = payload.index(index, offsetBy: 3, limitedBy: payload.endIndex) else {
            return nil
        }
        let three = String(payload[index..<threeEnd])
        guard three.allSatisfy(\.isNumber) else { return nil }

        if fixedLengthAIs[three] != nil || variableLengthAIs.contains(three) {
            return (three, threeEnd)
        }
        return nil
    }

    private static func apply(identifier: String, value: String, to reading: inout BarcodeReading) {
        switch identifier {
        case "01":
            reading.productCode = value
        case "17":
            reading.expiryDate = decodeDate(value)
        case "15":
            reading.bestBeforeDate = decodeDate(value)
        case "10":
            reading.batchNumber = value.isEmpty ? nil : value
        default:
            break
        }
    }

    /// Décode le format GS1 `AAMMJJ`. Un jour à « 00 » signifie « fin de mois ».
    static func decodeDate(_ value: String, calendar: Calendar = .current) -> Date? {
        guard value.count == 6, value.allSatisfy(\.isNumber) else { return nil }

        let digits = Array(value)
        guard let year = Int(String(digits[0...1])),
              let month = Int(String(digits[2...3])),
              let day = Int(String(digits[4...5])),
              (1...12).contains(month) else {
            return nil
        }

        var components = DateComponents()
        components.year = 2000 + year
        components.month = month
        components.hour = 23
        components.minute = 59

        if day == 0 {
            components.day = 1
            guard let firstDay = calendar.date(from: components),
                  let range = calendar.range(of: .day, in: .month, for: firstDay) else {
                return nil
            }
            components.day = range.upperBound - 1
        } else {
            components.day = day
        }

        return calendar.date(from: components)
    }
}
