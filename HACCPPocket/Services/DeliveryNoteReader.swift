//
//  DeliveryNoteReader.swift
//  HACCPPocket
//
//  Tirer un contrôle à réception d'une photo de bon de livraison.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE ÇA CHANGE POUR LE CUISINIER
//  ─────────────────────────────────────────────────────────────────────────
//
//  Un contrôle à réception se saisit aujourd'hui à la main : fournisseur,
//  produit, lot, date. Quatre champs tapés sur une tablette pendant qu'un
//  livreur attend. C'est exactement le travail que personne n'a le temps de
//  faire, et qui manque ensuite au registre le jour d'un contrôle.
//
//  Le bon de livraison porte déjà tout. Il suffit de le lire.
//
//  ─────────────────────────────────────────────────────────────────────────
//  RIEN DE NOUVEAU CÔTÉ LECTURE
//  ─────────────────────────────────────────────────────────────────────────
//
//  `DateOCRService` lisait déjà les étiquettes avec Vision, hors ligne, et
//  en tire le nom, le lot et la date. Ce fichier ne refait pas ce travail :
//  il ajoute la seule pièce qui manquait pour une réception, le nom du
//  fournisseur, et met le reste en forme.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI RESTE À L'HUMAIN
//  ─────────────────────────────────────────────────────────────────────────
//
//  La décision — acceptée, refusée — et la température du produit. Une
//  photo ne dit ni l'une ni l'autre : l'état d'un carton et la température
//  à cœur se constatent sur le quai, pas sur un papier. L'assistant
//  propose donc un contrôle accepté et le dit, pour qu'un refus soit un
//  geste conscient.
//

import Foundation

enum DeliveryNoteReader {

    /// Ce qu'on a pu lire sur le bon.
    struct Reading: Equatable, Sendable {
        var supplier: String = ""
        var product: String = ""
        var batch: String = ""
        var expiry: Date?

        var isEmpty: Bool {
            supplier.isEmpty && product.isEmpty && batch.isEmpty && expiry == nil
        }

        /// Ce qui s'affiche sous le titre de la carte de confirmation.
        var summary: String {
            var parts: [String] = []
            if !supplier.isEmpty { parts.append(supplier) }
            if !product.isEmpty { parts.append(product) }
            if !batch.isEmpty { parts.append("lot \(batch)") }
            return parts.joined(separator: " · ")
        }
    }

    static func read(_ scan: LabelScanResult) -> Reading {
        Reading(
            supplier: supplier(in: scan.recognizedLines) ?? "",
            product: (scan.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            batch: (scan.batchNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            expiry: scan.expiryDate
        )
    }

    // MARK: - Le fournisseur

    /// Le nom du fournisseur, s'il se laisse reconnaître.
    ///
    /// Deux passes. La première cherche une forme juridique — SARL, SAS,
    /// EURL — qui identifie une raison sociale sans ambiguïté. La seconde,
    /// à défaut, retient la première ligne plausible : un bon de livraison
    /// porte l'expéditeur en tête, avant les mentions administratives.
    static func supplier(in lines: [String]) -> String? {
        let candidates = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let legal = candidates.first(where: hasLegalForm) {
            return cleaned(legal)
        }

        return candidates.prefix(6).first(where: isPlausibleName).map(cleaned)
    }

    private static func hasLegalForm(_ line: String) -> Bool {
        let words = normalizedWords(of: line)
        return !legalForms.isDisjoint(with: words) && isPlausibleName(line)
    }

    /// Une ligne qui peut être une raison sociale.
    ///
    /// On écarte ce qui porte trop de chiffres — un numéro de SIRET, un
    /// téléphone, une référence — et les intitulés du document lui-même.
    private static func isPlausibleName(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 46 else { return false }

        let digits = trimmed.filter(\.isNumber).count
        let letters = trimmed.filter(\.isLetter).count
        guard letters >= 3, digits <= letters / 3 else { return false }

        return noise.isDisjoint(with: normalizedWords(of: trimmed))
    }

    /// Enlève la ponctuation de bord et comprime les espaces.
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

    private static let legalForms: Set<String> = [
        "sarl", "sas", "sasu", "eurl", "sa", "scop", "snc", "sci",
        "ets", "etablissements", "etablissement", "societe", "groupe",
        "distribution", "primeurs", "boucherie", "boulangerie", "marine",
        "fromagerie", "brasserie", "metro", "transgourmet", "promocash"
    ]

    /// Les intitulés du document, qui ne nomment personne.
    private static let noise: Set<String> = [
        "bon", "livraison", "facture", "commande", "bordereau", "client",
        "adresse", "telephone", "tel", "fax", "siret", "siren", "tva",
        "page", "date", "reference", "ref", "designation", "quantite",
        "quantites", "prix", "total", "ht", "ttc", "code", "postal",
        "numero", "lot", "dlc", "dluo", "poids", "colis", "unite",
        "euro", "euros", "montant", "remise", "rue", "avenue", "boulevard"
    ]
}
