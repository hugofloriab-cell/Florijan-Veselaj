//
//  DeliveryNoteReader.swift
//  HACCPPocket
//
//  Tirer un contrôle à réception d'une photo de bon de livraison.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER NE SE CONTENTE PLUS DE `DateOCRService`
//  ─────────────────────────────────────────────────────────────────────────
//
//  Première version : on réutilisait les heuristiques d'étiquette produit.
//  À l'essai, un bon réel n'a rendu que le nom du fournisseur. C'était
//  prévisible : une étiquette porte un produit, un bon en porte dix, en
//  colonnes, avec un lot et une date par ligne. Les règles de l'étiquette
//  cherchent une valeur unique et se taisent devant une liste.
//
//  La lecture Vision reste celle de `DateOCRService` — rien ne sort de
//  l'appareil. Ce qui change, c'est l'interprétation des lignes.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QU'ON NE DEVINE PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'appariement exact d'une désignation avec son lot et sa date. Vision
//  rend souvent les colonnes comme des lignes séparées, et recoller les
//  morceaux par leur position serait une reconstruction fragile — fausse
//  une fois sur cinq, sans que rien ne le signale.
//
//  On rend donc des listes, et l'écran les montre telles quelles. Un
//  cuisinier qui lit « 5 produits, 5 lots » vérifie d'un coup d'œil ; une
//  association inventée, personne ne la vérifie.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI RESTE À L'HUMAIN
//  ─────────────────────────────────────────────────────────────────────────
//
//  La décision et la température à cœur. Une photo ne dit ni l'état d'un
//  carton ni la température d'un filet : ça se constate sur le quai.
//

import Foundation

enum DeliveryNoteReader {

    /// Ce qu'on a pu lire sur le bon.
    struct Reading: Equatable, Sendable {
        var supplier: String = ""
        /// Le numéro du bon : « BL-2026-10418 ».
        var reference: String = ""
        var products: [String] = []
        var lots: [String] = []
        var expiry: Date?

        /// Le seuil de température de la famille reconnue, tel que le
        /// formulaire de réception l'attend. `nil` vaut épicerie sèche.
        var temperatureLimit: Double?
        var familyLabel: String = "Épicerie sèche"

        var isEmpty: Bool {
            supplier.isEmpty && products.isEmpty && lots.isEmpty && expiry == nil
        }

        /// Le produit principal : celui qui ira dans la fiche.
        var mainProduct: String { products.first ?? "" }
        var mainLot: String { lots.first ?? "" }

        /// Ce qui s'affiche sous le titre de la carte de confirmation.
        var summary: String {
            var parts: [String] = []
            if !supplier.isEmpty { parts.append(supplier) }
            if !products.isEmpty {
                parts.append(products.count == 1
                    ? products[0]
                    : "\(products.count) produits")
            }
            if !lots.isEmpty {
                parts.append(lots.count == 1 ? "lot \(lots[0])" : "\(lots.count) lots")
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Lecture

    static func read(_ scan: LabelScanResult, reference referenceDate: Date = .now) -> Reading {
        let lines = scan.recognizedLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var reading = Reading()
        reading.supplier = supplier(in: lines) ?? ""
        reading.reference = noteNumber(in: lines) ?? ""
        reading.products = products(in: lines, excluding: reading.supplier)
        reading.lots = lots(in: lines)
        reading.expiry = scan.expiryDate ?? earliestFutureDate(in: lines, after: referenceDate)

        let family = self.family(for: reading.products, lines: lines)
        reading.temperatureLimit = family.limit
        reading.familyLabel = family.label

        return reading
    }

    // MARK: - Le fournisseur

    /// Deux passes. La première cherche une forme juridique — SARL, SAS,
    /// EURL — qui identifie une raison sociale sans ambiguïté. La seconde,
    /// à défaut, retient la première ligne plausible : un bon porte son
    /// expéditeur en tête, avant les mentions administratives.
    ///
    /// Les lignes de destinataire sont écartées avant tout : « Client :
    /// RESTAURANT LE COMPTOIR DU MIDI » est une raison sociale parfaitement
    /// crédible, mais c'est celle du cuisinier, pas du fournisseur.
    static func supplier(in lines: [String]) -> String? {
        let candidates = lines.filter { !isAddressedToUs($0) }

        if let legal = candidates.first(where: hasLegalForm) {
            return cleaned(legal)
        }
        return candidates.prefix(6).first(where: isPlausibleName).map(cleaned)
    }

    private static func isAddressedToUs(_ line: String) -> Bool {
        !recipientMarkers.isDisjoint(with: normalizedWords(of: line))
    }

    private static func hasLegalForm(_ line: String) -> Bool {
        !legalForms.isDisjoint(with: normalizedWords(of: line)) && isPlausibleName(line)
    }

    private static func isPlausibleName(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 46 else { return false }

        let digits = trimmed.filter(\.isNumber).count
        let letters = trimmed.filter(\.isLetter).count
        guard letters >= 3, digits <= letters / 3 else { return false }

        return noise.isDisjoint(with: normalizedWords(of: trimmed))
    }

    // MARK: - Le numéro du bon

    private static func noteNumber(in lines: [String]) -> String? {
        for line in lines {
            let words = normalizedWords(of: line)
            guard !noteMarkers.isDisjoint(with: words) else { continue }
            // Le numéro est le jeton le plus chiffré de la ligne.
            let tokens = line.split { $0 == " " || $0 == ":" }.map(String.init)
            if let best = tokens
                .filter({ $0.filter(\.isNumber).count >= 4 })
                .max(by: { $0.count < $1.count }) {
                return best.trimmingCharacters(in: CharacterSet(charactersIn: "°#:.,"))
            }
        }
        return nil
    }

    // MARK: - Les désignations

    /// Les lignes qui nomment une marchandise.
    ///
    /// Le tri est négatif : on écarte les adresses, les intitulés, les
    /// lignes trop chiffrées et les en-têtes de colonnes. Ce qui reste est
    /// presque toujours une désignation, et ce qui passe au travers se voit
    /// immédiatement puisque tout est affiché.
    private static func products(in lines: [String], excluding supplier: String) -> [String] {
        var seen = Set<String>()
        var found: [String] = []

        for line in lines {
            let trimmed = cleaned(line)
            guard trimmed != supplier else { continue }
            guard looksLikeGoods(trimmed) else { continue }

            let name = designation(from: trimmed)
            guard name.filter(\.isLetter).count >= 6 else { continue }

            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            found.append(name)
        }

        // Dix lignes suffisent : au-delà, la photo a pris autre chose que
        // le tableau, et une liste interminable ne se vérifie plus.
        return Array(found.prefix(10))
    }

    /// La désignation seule, sans la quantité, le lot ni la date.
    ///
    /// Vision rend souvent toute une ligne de tableau d'un bloc : « Filet
    /// de boeuf race normande 4,800 kg L2641A 24/10/2026 ». Inscrire cela
    /// comme nom de produit rendrait le registre illisible. On coupe au
    /// premier jeton qui n'appartient plus au nom.
    private static func designation(from line: String) -> String {
        var kept: [String] = []

        for token in line.split(separator: " ").map(String.init) {
            if endsTheName(token) { break }
            kept.append(token)
        }

        return kept.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:;,."))
    }

    private static func endsTheName(_ token: String) -> Bool {
        if token.contains("/") { return true }
        if isLotToken(token) { return true }

        let folded = token.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        if unitWords.contains(folded) { return true }

        // Un jeton purement numérique : quantité, poids, pourcentage.
        let stripped = folded.trimmingCharacters(in: CharacterSet(charactersIn: "%°"))
        if !stripped.isEmpty, stripped.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) {
            return true
        }

        return false
    }

    private static let unitWords: Set<String> = [
        "kg", "g", "gr", "mg", "l", "cl", "ml", "piece", "pieces", "unite",
        "unites", "x", "colis", "carton", "cartons", "barquette", "barquettes"
    ]

    private static func looksLikeGoods(_ line: String) -> Bool {
        let words = normalizedWords(of: line)
        guard !words.isEmpty else { return false }
        guard noise.isDisjoint(with: words) else { return false }
        guard recipientMarkers.isDisjoint(with: words) else { return false }
        guard legalForms.isDisjoint(with: words) else { return false }

        let letters = line.filter(\.isLetter).count
        guard letters >= 6, line.count <= 60 else { return false }

        // Au moins deux mots de trois lettres : « 4,800 kg » n'est pas une
        // désignation, « Filet de boeuf » en est une.
        let real = words.filter { $0.count >= 3 }
        guard real.count >= 2 else { return false }

        return true
    }

    // MARK: - Les lots

    /// Un lot ressemble à une ou trois lettres suivies de chiffres.
    ///
    /// La règle est volontairement stricte. Un faux lot inscrit au registre
    /// est pire qu'un lot absent : en cas de rappel, c'est par lui qu'on
    /// retrouve la marchandise.
    private static func lots(in lines: [String]) -> [String] {
        var seen = Set<String>()
        var found: [String] = []

        for line in lines {
            for token in line.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "," }) {
                let candidate = String(token).trimmingCharacters(
                    in: CharacterSet(charactersIn: ".;()[]")
                )
                guard isLotToken(candidate), !seen.contains(candidate) else { continue }
                seen.insert(candidate)
                found.append(candidate)
            }
        }
        return Array(found.prefix(10))
    }

    private static func isLotToken(_ token: String) -> Bool {
        guard token.count >= 4, token.count <= 12 else { return false }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }

        let digits = token.filter(\.isNumber).count
        let letters = token.filter(\.isLetter).count
        guard digits >= 3, letters >= 1, letters <= 3 else { return false }

        // La première doit être une lettre : « 13002 » est un code postal,
        // « L2641A » est un lot.
        guard let first = token.first, first.isLetter else { return false }
        return true
    }

    // MARK: - La date

    /// La plus proche des dates à venir trouvées sur le bon.
    ///
    /// On ne garde que le futur : une date passée est la date d'édition ou
    /// une référence, jamais une limite de consommation.
    private static func earliestFutureDate(in lines: [String], after reference: Date) -> Date? {
        lines
            .compactMap { DateOCRService.parseDate(from: $0, reference: reference) }
            .filter { $0 > reference }
            .min()
    }

    // MARK: - La famille

    /// La famille de marchandise, et le seuil qui va avec.
    ///
    /// Le formulaire de réception déduit la famille du seuil : sans seuil,
    /// il affiche « épicerie sèche ». Ne rien renseigner revenait donc à
    /// classer une livraison de viande en épicerie, ce qui supprime
    /// l'exigence de température — exactement le contraire du but.
    private static func family(for products: [String], lines: [String]) -> (limit: Double?, label: String) {
        let haystack = normalizedWords(of: (products + lines).joined(separator: " "))

        if !frozenWords.isDisjoint(with: haystack) {
            return (-18, "Surgelé")
        }
        if !veryPerishableWords.isDisjoint(with: haystack) {
            return (2, "Très périssable")
        }
        if !chilledWords.isDisjoint(with: haystack) {
            return (4, "Frais")
        }
        return (nil, "Épicerie sèche")
    }

    // MARK: - Le tableau affiché

    /// Ce qui a été lu, ligne par ligne, pour être vérifié d'un coup d'œil.
    static func rows(for reading: Reading) -> [AssistantReport.Row] {
        var rows: [AssistantReport.Row] = []

        rows.append(AssistantReport.Row(
            label: "Fournisseur",
            detail: reading.reference.isEmpty ? "Bon de livraison" : "Bon \(reading.reference)",
            value: reading.supplier.isEmpty ? "—" : reading.supplier,
            isAlert: reading.supplier.isEmpty
        ))

        rows.append(AssistantReport.Row(
            label: "Famille",
            detail: reading.temperatureLimit == nil
                ? "Aucun seuil de température"
                : "Seuil \(AppFormatters.temperature(reading.temperatureLimit ?? 0))",
            value: reading.familyLabel,
            isAlert: false
        ))

        for (index, product) in reading.products.enumerated() {
            rows.append(AssistantReport.Row(
                label: product,
                detail: "Produit \(index + 1)",
                value: index < reading.lots.count ? reading.lots[index] : "—",
                isAlert: false
            ))
        }

        if reading.products.isEmpty, !reading.lots.isEmpty {
            rows.append(AssistantReport.Row(
                label: "Lots lus",
                detail: "Aucune désignation reconnue",
                value: reading.lots.joined(separator: ", "),
                isAlert: true
            ))
        }

        if let expiry = reading.expiry {
            rows.append(AssistantReport.Row(
                label: "DLC la plus proche",
                detail: "Lue sur le bon",
                value: AppFormatters.shortDate(expiry),
                isAlert: false
            ))
        }

        return rows
    }

    // MARK: - Outils

    private static func cleaned(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:;,.*|"))
        return trimmed.split(separator: " ").joined(separator: " ")
    }

    private static func normalizedWords(of text: String) -> Set<String> {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        return Set(folded.split { !$0.isLetter }.map(String.init))
    }

    // MARK: - Vocabulaire

    private static let legalForms: Set<String> = [
        "sarl", "sas", "sasu", "eurl", "scop", "snc", "sci",
        "ets", "etablissements", "etablissement", "societe", "groupe",
        "distribution", "primeurs", "marine", "metro", "transgourmet",
        "promocash", "pomona", "sysco"
    ]

    /// Ce qui désigne le destinataire : à écarter du fournisseur.
    private static let recipientMarkers: Set<String> = [
        "client", "destinataire", "livre", "livrer", "restaurant", "chez"
    ]

    private static let noteMarkers: Set<String> = [
        "bon", "livraison", "bl", "bordereau", "numero", "reference"
    ]

    /// Les intitulés du document, qui ne nomment aucune marchandise.
    private static let noise: Set<String> = [
        "bon", "livraison", "facture", "commande", "bordereau", "client",
        "adresse", "telephone", "tel", "fax", "siret", "siren", "tva",
        "page", "date", "reference", "ref", "designation", "quantite",
        "quantites", "prix", "total", "ht", "ttc", "code", "postal",
        "numero", "poids", "colis", "unite", "euro", "euros", "montant",
        "remise", "rue", "avenue", "boulevard", "quai", "place", "chemin",
        "signature", "livreur", "transport", "document", "fictif",
        "societe", "inexistante", "usage", "test", "uniquement",
        "marchandise", "effectuer", "controle", "reception", "principal"
    ]

    private static let frozenWords: Set<String> = [
        "surgele", "surgeles", "surgelee", "surgelees", "congele", "congeles",
        "glace", "glaces", "iqf"
    ]

    private static let veryPerishableWords: Set<String> = [
        "hache", "hachee", "hachis", "steak", "tartare", "poisson", "saumon",
        "cabillaud", "truite", "thon", "crevette", "crevettes", "moule",
        "moules", "huitre", "huitres", "volaille", "poulet", "abats",
        "boeuf", "veau", "agneau", "porc", "viande", "filet", "escalope"
    ]

    private static let chilledWords: Set<String> = [
        "frais", "fraiche", "creme", "lait", "beurre", "yaourt", "fromage",
        "charcuterie", "jambon", "saucisson", "oeuf", "oeufs", "salade",
        "legume", "legumes", "fruit", "fruits", "pate", "pates", "traiteur",
        "refrigere", "refrigeree"
    ]
}
