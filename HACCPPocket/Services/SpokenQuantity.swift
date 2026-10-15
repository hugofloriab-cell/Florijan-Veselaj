//
//  SpokenQuantity.swift
//  HACCPPocket
//
//  Lire une quantité dans une phrase dictée, sans modèle de langage.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER EXISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  La quantité était auparavant remplie par le modèle. Le schéma portait un
//  exemple — « par exemple 1 kg » — et le modèle le recopiait : 10 kg de
//  farine devenaient 1 kg, 1,55 kg de sucre devenaient 1 kg. L'ancrage sur
//  un exemple est un défaut connu des modèles contraints, et retirer
//  l'exemple n'aurait fait que le rendre moins visible.
//
//  La correction est ailleurs. Un nombre qui finit dans un registre
//  d'hygiène ne doit pas sortir d'un modèle de langage : il doit être lu
//  dans le texte dicté, par du code, de la même façon aujourd'hui et dans
//  six mois. C'est la même règle que pour les dates, pour la même raison.
//
//  Le modèle garde ce qu'il sait faire : reconnaître une intention, isoler
//  un nom d'aliment, poser une question. Il lui est même interdit de
//  prononcer un nombre, pour qu'un chiffre mal entendu ne puisse pas se
//  glisser dans une phrase de confirmation.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE ÇA SAIT LIRE
//  ─────────────────────────────────────────────────────────────────────────
//
//      « 1,55 kg de sucre »        →  1,55 kg
//      « 10 kg de farine »         →  10 kg
//      « 500g »                    →  500 g        (sans espace)
//      « un kilo et demi »         →  1,5 kg
//      « vingt-cinq litres »       →  25 L
//      « quatre-vingts kilos »     →  80 kg
//      « une boîte de 5 kg »       →  boîte de 5 kg
//      « deux sachets »            →  2 sachets
//
//  Et surtout ce que ça refuse de lire : une unité sans nombre devant elle.
//  Sans cette règle, « de l'huile » donnerait des litres, puisque la dictée
//  sépare « l' » du mot suivant.
//

import Foundation

struct SpokenQuantity: Equatable {

    /// Le nombre attaché à l'unité : 1,55 dans « 1,55 kg ».
    let value: Double?

    /// L'unité normalisée : « kg », « g », « mg », « L », « cl », « ml ».
    let unit: String?

    /// Le nombre attaché au conditionnement : 2 dans « deux sachets ».
    let count: Double?

    /// Le conditionnement cité : « sachet », « boîte », « bidon »…
    let packaging: String?

    static let none = SpokenQuantity(value: nil, unit: nil, count: nil, packaging: nil)

    var isEmpty: Bool {
        value == nil && unit == nil && count == nil && packaging == nil
    }

    // MARK: - Lecture

    static func parse(_ text: String) -> SpokenQuantity {
        let tokens = tokenize(text)

        var value: Double?
        var unit: String?
        var count: Double?
        var packaging: String?

        for (index, token) in tokens.enumerated() {

            if let measured = units[token] {
                // Une unité ne compte que si un nombre la précède.
                //
                // La dictée écrit « de l'huile » en séparant l'apostrophe :
                // le « l » resté seul passerait pour des litres. Exiger un
                // nombre devant élimine ce faux positif, et tous ceux de la
                // même famille.
                guard unit == nil, var amount = number(before: index, in: tokens) else { continue }
                if isHalf(after: index, in: tokens) { amount += 0.5 }
                unit = measured
                value = amount
                continue
            }

            if let container = packagings[token], packaging == nil {
                packaging = container
                count = number(before: index, in: tokens)
            }
        }

        return SpokenQuantity(value: value, unit: unit, count: count, packaging: packaging)
    }

    // MARK: - Ce qui s'écrit

    /// Pour l'écran et pour le registre : « 1,55 kg », « boîte de 5 kg ».
    var written: String {
        var pieces: [String] = []

        if let packaging {
            if let count, count != 1 {
                pieces.append("\(Self.formatted(count)) \(Self.plural(packaging))")
            } else {
                pieces.append(packaging)
            }
        }

        if let unit {
            let measure = value.map { "\(Self.formatted($0)) \(unit)" } ?? unit
            pieces.append(pieces.isEmpty ? measure : "de \(measure)")
        }

        return pieces.joined(separator: " ")
    }

    // MARK: - Ce qui se prononce

    /// Pour la voix : « un virgule 55 kilos », « boîte de 5 kilos ».
    ///
    /// Les abréviations sont développées, et la virgule décimale devient le
    /// mot. « 1,55 kg » lu tel quel donnerait au mieux une hésitation, au
    /// pire une suite de lettres.
    var spoken: String {
        var pieces: [String] = []

        if let packaging {
            if let count, count != 1 {
                pieces.append("\(Self.spokenNumber(count)) \(Self.plural(packaging))")
            } else {
                pieces.append(packaging)
            }
        }

        if let unit {
            let measure = value.map { "\(Self.spokenNumber($0)) \(Self.spokenUnit(unit, value: $0))" }
                ?? Self.spokenUnit(unit, value: nil)
            pieces.append(pieces.isEmpty ? measure : "de \(measure)")
        }

        return pieces.joined(separator: " ")
    }

    // MARK: - Découpage

    /// Minuscules, sans accents, coupé aux changements chiffres/lettres.
    ///
    /// La coupure aux transitions traite « 500g » dicté sans espace, cas
    /// fréquent quand on parle vite.
    private static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )

        var tokens: [String] = []
        var current = ""
        var currentIsNumeric = false

        func flush() {
            let cleaned = current.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if !cleaned.isEmpty { tokens.append(cleaned) }
            current = ""
        }

        for character in folded {
            let isNumeric = character.isNumber || character == "," || character == "."
            let isLetter = character.isLetter

            guard isNumeric || isLetter else { flush(); continue }

            if !current.isEmpty && isNumeric != currentIsNumeric {
                flush()
            }
            current.append(character)
            currentIsNumeric = isNumeric
        }
        flush()

        return tokens
    }

    // MARK: - Nombres

    /// Le nombre qui précède immédiatement une position, s'il y en a un.
    ///
    /// Les chiffres se lisent seuls et sans ambiguïté. Les nombres écrits en
    /// toutes lettres demandent plus de précautions, le français ayant deux
    /// irrégularités — soixante-dix et quatre-vingts s'écrivent en deux mots
    /// — et des composés de trois mots qu'on ne peut pas lire en regardant
    /// seulement les deux précédents.
    ///
    /// Dans ce dernier cas on renonce et on rend `nil`. L'assistant
    /// redemandera la quantité, ce qui est fastidieux ; lire « quatre-vingt
    /// cinq » comme vingt-cinq serait pire, parce que personne ne le
    /// verrait.
    private static func number(before index: Int, in tokens: [String]) -> Double? {
        guard index > 0 else { return nil }
        let previous = tokens[index - 1]

        // Un nombre en chiffres se suffit à lui-même.
        if let digits = Double(previous.replacingOccurrences(of: ",", with: ".")) {
            return digits
        }

        guard let immediate = numberWords[previous] else { return nil }
        guard index > 1 else { return immediate }

        let before = tokens[index - 2]

        // Les deux irrégularités du français.
        if before == "quatre", previous == "vingt" || previous == "vingts" { return 80 }
        if before == "soixante", immediate == 10 { return 70 }

        guard let tens = numberWords[before] else { return immediate }

        // « deux cents », « trois mille » : ici le mot multiplie.
        if immediate >= 100, tens < 100 { return tens * immediate }

        // « vingt cinq », « cinquante trois » : ici il s'ajoute.
        if tens >= 20, tens < 70, immediate < 10 {
            // Un troisième mot-nombre devant, et la lecture à deux jetons ne
            // vaut plus rien : « quatre vingt cinq » donnerait vingt-cinq.
            if index > 2, numberWords[tokens[index - 3]] != nil { return nil }
            return tens + immediate
        }

        return immediate
    }

    /// « et demi » après l'unité : « un kilo et demi ».
    private static func isHalf(after index: Int, in tokens: [String]) -> Bool {
        if index + 1 < tokens.count, half.contains(tokens[index + 1]) { return true }
        if index + 2 < tokens.count, tokens[index + 1] == "et", half.contains(tokens[index + 2]) { return true }
        return false
    }

    private static func number(from token: String) -> Double? {
        if let written = numberWords[token] { return written }
        // La dictée française écrit la décimale avec une virgule.
        return Double(token.replacingOccurrences(of: ",", with: "."))
    }

    private static let half: Set<String> = ["demi", "demie"]

    private static let numberWords: [String: Double] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
        "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15,
        "seize": 16, "vingt": 20, "vingts": 20, "trente": 30, "quarante": 40,
        "cinquante": 50, "soixante": 60, "cent": 100, "cents": 100, "mille": 1000,
        "demi": 0.5, "demie": 0.5
    ]

    // MARK: - Vocabulaire

    /// Les clés sont sans accent : le texte est replié avant comparaison.
    private static let units: [String: String] = [
        "kg": "kg", "kilo": "kg", "kilos": "kg",
        "kilogramme": "kg", "kilogrammes": "kg",
        "g": "g", "gr": "g", "gramme": "g", "grammes": "g",
        "mg": "mg", "milligramme": "mg", "milligrammes": "mg",
        "l": "L", "litre": "L", "litres": "L",
        "cl": "cl", "centilitre": "cl", "centilitres": "cl",
        "ml": "ml", "millilitre": "ml", "millilitres": "ml"
    ]

    private static let packagings: [String: String] = [
        "sachet": "sachet", "sachets": "sachet",
        "boite": "boîte", "boites": "boîte",
        "barquette": "barquette", "barquettes": "barquette",
        "bouteille": "bouteille", "bouteilles": "bouteille",
        "pot": "pot", "pots": "pot",
        "bidon": "bidon", "bidons": "bidon",
        "sac": "sac", "sacs": "sac",
        "carton": "carton", "cartons": "carton",
        "paquet": "paquet", "paquets": "paquet",
        "brique": "brique", "briques": "brique",
        "plaque": "plaque", "plaques": "plaque",
        "seau": "seau", "seaux": "seau",
        "bac": "bac", "bacs": "bac",
        "poche": "poche", "poches": "poche",
        "conserve": "conserve", "conserves": "conserve",
        "filet": "filet", "filets": "filet",
        "botte": "botte", "bottes": "botte",
        "caisse": "caisse", "caisses": "caisse",
        "cageot": "cageot", "cageots": "cageot",
        "flacon": "flacon", "flacons": "flacon"
    ]

    // MARK: - Mise en forme

    private static func plural(_ word: String) -> String {
        // « seau » fait « seaux », pas « seaus ».
        word.hasSuffix("au") ? word + "x" : word + "s"
    }

    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    private static func formatted(_ number: Double) -> String {
        decimal.string(from: NSNumber(value: number)) ?? String(number)
    }

    private static func spokenNumber(_ number: Double) -> String {
        formatted(number).replacingOccurrences(of: ",", with: " virgule ")
    }

    private static func spokenUnit(_ unit: String, value: Double?) -> String {
        let many = (value ?? 2) > 1
        switch unit {
        case "kg": return many ? "kilos" : "kilo"
        case "g":  return many ? "grammes" : "gramme"
        case "mg": return many ? "milligrammes" : "milligramme"
        case "L":  return many ? "litres" : "litre"
        case "cl": return many ? "centilitres" : "centilitre"
        case "ml": return many ? "millilitres" : "millilitre"
        default:   return unit
        }
    }
}
