//
//  SpokenTemperature.swift
//  HACCPPocket
//
//  Lire une température dans une phrase dictée.
//
//  ─────────────────────────────────────────────────────────────────────────
//  MÊME RÈGLE QUE POUR LES QUANTITÉS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Une température part dans un registre opposable à un contrôleur. Elle ne
//  sort donc pas d'un modèle de langage : elle est lue dans le texte dicté,
//  par du code.
//
//  Le signe compte plus qu'ailleurs. Un congélateur relevé à 18 au lieu de
//  −18 est une non-conformité grave inscrite à l'envers : le registre
//  affirmerait une rupture de chaîne du froid qui n'a pas eu lieu, ou
//  masquerait l'inverse. « moins dix-huit », « moins 18 » et « −18 » sont
//  donc tous reconnus.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE ÇA SAIT LIRE
//  ─────────────────────────────────────────────────────────────────────────
//
//      « 3 °C »                    →   3
//      « trois degrés »            →   3
//      « moins 18 »                →  −18
//      « −18,5 degrés »            →  −18,5
//      « il fait 4,5 »             →  4,5   (si on parle déjà température)
//
//  Hors contexte de température, un nombre seul n'est jamais pris pour une
//  température : « frigo numéro 2 » ne vaut pas deux degrés.
//

import Foundation

enum SpokenTemperature {

    /// Lit une température en degrés Celsius.
    ///
    /// - Parameters:
    ///   - text: la phrase dictée, telle quelle.
    ///   - assumingTemperature: `true` quand la conversation porte déjà sur
    ///     un relevé. Un nombre seul, sans « degrés » ni « °C », n'est
    ///     accepté que dans ce cas — et seulement s'il est le seul de la
    ///     phrase, pour que « frigo 2 à 4 degrés » ne devienne pas 2.
    static func parse(_ text: String, assumingTemperature: Bool = false) -> Double? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }

        var numbers: [(end: Int, value: Double)] = []
        var index = 0

        while index < tokens.count {
            guard let found = number(at: index, in: tokens) else {
                index += 1
                continue
            }
            numbers.append((index + found.consumed, found.value))
            // Les jetons avalés par un nombre composé ne sont pas relus :
            // sans cela « moins dix sept » produirait aussi un 7 isolé, et
            // la phrase paraîtrait en contenir deux.
            index += found.consumed
        }

        guard !numbers.isEmpty else { return nil }

        // Priorité au nombre suivi d'une marque de degré : c'est le seul
        // signal explicite, et il tranche quand la phrase en contient
        // plusieurs.
        for candidate in numbers where hasDegreeMarker(at: candidate.end, in: tokens) {
            return candidate.value
        }

        guard assumingTemperature, numbers.count == 1 else { return nil }
        return numbers[0].value
    }

    // MARK: - Nombres

    /// Le nombre qui commence à cette position : sa valeur signée, et le
    /// nombre de jetons qu'il occupe.
    private static func number(at index: Int, in tokens: [Token]) -> (value: Double, consumed: Int)? {
        // « frigo numéro 2 » ne donne pas deux degrés.
        if index > 0, ordinals.contains(tokens[index - 1].text) { return nil }

        guard let found = magnitude(at: index, in: tokens) else { return nil }
        let signed = isNegated(at: index, in: tokens) ? -found.value : found.value
        return (signed, found.consumed)
    }

    /// La valeur absolue, en chiffres ou en lettres.
    private static func magnitude(at index: Int, in tokens: [Token]) -> (value: Double, consumed: Int)? {
        let text = tokens[index].text

        if let digits = Double(text.replacingOccurrences(of: ",", with: ".")) {
            return (digits, 1)
        }

        guard let written = numberWords[text] else { return nil }

        // Les composés que la dictée écrit en plusieurs mots. Au-delà de
        // soixante-dix-neuf, une température de cuisine n'existe pas : on
        // s'arrête là plutôt que d'ouvrir la boîte des quatre-vingts.
        func word(_ offset: Int) -> String? {
            let position = index + offset
            return position < tokens.count ? tokens[position].text : nil
        }

        // « vingt et un », « soixante et onze ».
        if word(1) == "et", let joined = word(2).flatMap({ numberWords[$0] }),
           written >= 20, written < 70,
           joined < 10 || (written == 60 && joined == 11) {
            return (written + joined, 3)
        }

        if let next = word(1).flatMap({ numberWords[$0] }) {
            if written == 10, next < 10 { return (written + next, 2) }
            if written == 60, next == 10 { return (70, 2) }
            if written >= 20, written < 70, next < 10 { return (written + next, 2) }
        }

        return (written, 1)
    }

    /// Signe négatif : le tiret collé au nombre, ou le mot « moins ».
    private static func isNegated(at index: Int, in tokens: [Token]) -> Bool {
        if tokens[index].precededByHyphen { return true }
        guard index > 0 else { return false }
        return tokens[index - 1].text == "moins" || tokens[index - 1].text == "negatif"
    }

    // MARK: - Marque de degré

    /// « 3 °C », « 3 degrés », « 3 degrés Celsius ».
    ///
    /// Le « C » seul ne compte jamais : la dictée coupe « c'est » en deux et
    /// produirait un faux positif à chaque phrase.
    private static func hasDegreeMarker(at end: Int, in tokens: [Token]) -> Bool {
        for offset in 0...1 where end + offset < tokens.count {
            if degreeMarkers.contains(tokens[end + offset].text) { return true }
        }
        return false
    }

    private static let ordinals: Set<String> = ["numero", "numeros", "no", "n"]

    private static let degreeMarkers: Set<String> = ["°", "degre", "degres", "celsius"]

    private static let numberWords: [String: Double] = [
        "zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4,
        "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15,
        "seize": 16, "vingt": 20, "vingts": 20, "trente": 30, "quarante": 40,
        "cinquante": 50, "soixante": 60
    ]

    // MARK: - Découpage

    private struct Token {
        let text: String
        /// Un tiret collé devant, comme dans « −18 ».
        let precededByHyphen: Bool
    }

    private static func tokenize(_ text: String) -> [Token] {
        // Le signe moins existe en plusieurs caractères selon le clavier et
        // la dictée : tiret, tiret cadratin, vrai signe moins typographique.
        let hyphens: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"]

        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )

        var tokens: [Token] = []
        var current = ""
        var currentIsNumeric = false
        var pendingHyphen = false
        var currentHyphen = false

        func flush() {
            let cleaned = current.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if !cleaned.isEmpty {
                tokens.append(Token(text: cleaned, precededByHyphen: currentHyphen))
            }
            current = ""
            currentHyphen = false
        }

        for character in folded {
            if character == "°" {
                flush()
                tokens.append(Token(text: "°", precededByHyphen: false))
                pendingHyphen = false
                continue
            }

            let isNumeric = character.isNumber || character == "," || character == "."
            let isLetter = character.isLetter

            guard isNumeric || isLetter else {
                flush()
                // Un tiret ne compte comme signe que s'il touche le nombre :
                // « frigo-cuisine » ne doit pas produire un négatif.
                pendingHyphen = hyphens.contains(character)
                continue
            }

            if !current.isEmpty && isNumeric != currentIsNumeric {
                flush()
            }
            if current.isEmpty {
                currentHyphen = pendingHyphen
                pendingHyphen = false
            }
            current.append(character)
            currentIsNumeric = isNumeric
        }
        flush()

        return tokens
    }
}
