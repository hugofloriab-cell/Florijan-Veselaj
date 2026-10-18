//
//  SpokenProduct.swift
//  HACCPPocket
//
//  Isoler le nom d'un aliment dans une phrase dictée.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI LE CODE S'EN MÊLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Quand l'assistant demande « quel produit ? » et qu'on répond « du
//  sucre », la réponse ne doit pas dépendre d'un modèle. Elle tient en une
//  règle : enlever les mots qui ne nomment rien — les articles, les verbes,
//  les quantités, les emballages — et garder le reste.
//
//  C'est ce qui empêche la question de revenir une troisième fois. Le
//  modèle reste utile pour comprendre une phrase entière ; pour cueillir un
//  mot derrière « du », il ne sert à rien et il peut échouer.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA CASSE ET LES ACCENTS SONT PRÉSERVÉS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le tri se fait sur une version repliée du texte, mais ce qui est rendu
//  vient du texte d'origine : « de la Crème fraîche » donne « Crème
//  fraîche », et non « creme fraiche ». Ce nom finit dans un registre que
//  l'on imprime.
//

import Foundation

enum SpokenProduct {

    /// Le nom de l'aliment contenu dans une phrase, ou une chaîne vide.
    ///
    /// Quatre mots au plus : au-delà, ce n'est plus un nom de produit mais
    /// une phrase, et mieux vaut ne rien proposer que proposer n'importe
    /// quoi.
    static func name(in text: String) -> String {
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "-" }

        let kept = words.filter { word in
            let folded = String(word).folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
            guard folded.count > 1 else { return false }
            guard !ignored.contains(folded) else { return false }
            // Un nombre n'est jamais un nom d'aliment.
            guard Double(folded.replacingOccurrences(of: ",", with: ".")) == nil else { return false }
            return true
        }

        guard !kept.isEmpty, kept.count <= 4 else { return "" }
        return kept.map(String.init).joined(separator: " ")
    }

    /// Tout ce qui, dans une phrase de cuisine, ne nomme pas l'aliment.
    ///
    /// Les unités et les emballages y figurent : ils sont déjà lus par
    /// `SpokenQuantity`, et les laisser ici produirait « sachet sucre ».
    private static let ignored: Set<String> = [
        // La langue
        "je", "jai", "ai", "tu", "il", "elle", "on", "nous", "vous",
        "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux",
        "ce", "cet", "cette", "mon", "ma", "mes", "et", "ou",
        "dans", "sur", "pour", "avec", "sans", "cest", "qui", "que",
        "viens", "vient", "bien", "alors", "voila", "merci", "bonjour",
        "oui", "non", "ok", "donc", "aussi", "tout", "tous", "toute",

        // Ce qu'on fait
        "entame", "entamer", "entamee", "entames", "entamees",
        "ouvert", "ouverte", "ouvrir", "ouvre", "ouvres",
        "commence", "commencer", "attaque", "attaquer", "sors", "sorti",
        "ajoute", "ajouter", "noter", "note", "mettre", "mets", "met",
        "veux", "voudrais", "faut", "besoin", "peux", "peut", "fait",
        "nouveau", "nouvelle", "produit", "produits", "aliment", "aliments",
        "assistant", "fiche", "registre",

        // Ce que SpokenQuantity lit déjà
        "kg", "kilo", "kilos", "kilogramme", "kilogrammes",
        "gr", "gramme", "grammes", "mg", "litre", "litres", "cl", "ml",
        "sachet", "sachets", "boite", "boites", "barquette", "barquettes",
        "bouteille", "bouteilles", "pot", "pots", "bidon", "bidons",
        "sac", "sacs", "carton", "cartons", "paquet", "paquets",
        "brique", "briques", "plaque", "plaques", "seau", "seaux",
        "bac", "bacs", "poche", "poches", "conserve", "conserves",
        "filet", "filets", "botte", "bottes", "caisse", "caisses",
        "cageot", "cageots", "flacon", "flacons",

        // Les nombres écrits
        "zero", "un", "deux", "trois", "quatre", "cinq", "six", "sept",
        "huit", "neuf", "dix", "onze", "douze", "treize", "quatorze",
        "quinze", "seize", "vingt", "vingts", "trente", "quarante",
        "cinquante", "soixante", "cent", "cents", "mille", "demi", "demie"
    ]
}
