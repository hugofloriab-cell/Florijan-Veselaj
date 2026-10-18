//
//  SpokenIntentGuess.swift
//  HACCPPocket
//
//  Reconnaître une demande évidente sans déranger le modèle.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER EXISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  « Montre-moi les températures d'aujourd'hui » est reparti vers le modèle
//  embarqué, qui a répondu qu'il ne comprenait pas. La phrase ne laisse
//  pourtant aucune place au doute : un verbe de consultation, un sujet.
//
//  C'est la même erreur que celle déjà corrigée ailleurs : confier à un
//  modèle de langage ce que trois mots suffisent à décider. Un modèle
//  embarqué se trompe parfois, et quand il se trompe sur une phrase aussi
//  nette, l'assistant paraît bête.
//
//  L'aiguillage par mots-clés passe donc en premier. Le modèle reste pour
//  tout ce qui est formulé autrement — et il reste indispensable : aucune
//  liste de mots ne couvre la langue parlée.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI DÉCIDE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Deux dimensions, jamais une seule. Un verbe — consulter, inscrire — et
//  un sujet — les températures, le nettoyage. « Relever une température »
//  et « montrer les températures » partagent le sujet et s'opposent par le
//  verbe ; les confondre serait pire que de ne rien reconnaître.
//
//  En cas d'ambiguïté, on rend `nil` et le modèle tranche.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SpokenIntentGuess {

    /// Les familles de mots. Sans accents : le texte est replié avant.
    private static let showing: Set<String> = [
        "montre", "montres", "montrer", "affiche", "affiches", "afficher",
        "voir", "vois", "consulte", "consulter", "recap", "recapitulatif",
        "bilan", "resume", "liste", "lister", "donne", "sors", "sortir",
        "quelles", "quels", "combien", "etat"
    ]

    private static let recording: Set<String> = [
        "releve", "relever", "releves", "note", "noter", "enregistre",
        "enregistrer", "inscris", "inscrire", "saisir", "saisis", "ajoute"
    ]

    private static let temperature: Set<String> = [
        "temperature", "temperatures", "frigo", "frigos", "congelateur",
        "congelateurs", "congel", "congelo", "chambre", "froide",
        "enceinte", "enceintes", "degre", "degres"
    ]

    private static let product: Set<String> = [
        "produit", "produits", "entame", "entamer", "entames", "entamee",
        "aliment", "aliments", "ouvert", "ouverte", "denree", "denrees"
    ]

    private static let cleaning: Set<String> = [
        "nettoyage", "nettoie", "nettoyer", "nettoye", "menage", "desinfection",
        "desinfecte", "plonge"
    ]

    private static let sample: Set<String> = ["temoin", "temoins", "echantillon"]

    private static let delivery: Set<String> = [
        "reception", "receptions", "livraison", "livraisons", "marchandise",
        "marchandises", "fournisseur", "fournisseurs", "camion"
    ]

    #if canImport(FoundationModels)

    /// L'intention lue dans la phrase, ou `nil` s'il y a le moindre doute.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func intent(in text: String) -> SpokenIntent? {
        let words = Self.words(in: text)
        guard !words.isEmpty else { return nil }

        let wantsToSee = !showing.isDisjoint(with: words)
        let wantsToWrite = !recording.isDisjoint(with: words)

        // Températures : le verbe tranche entre consulter et inscrire.
        if !temperature.isDisjoint(with: words) {
            if wantsToSee && !wantsToWrite { return .recapTemperatures }
            if wantsToWrite { return .enregistrerTemperature }
            // Ni l'un ni l'autre, mais un chiffre : « le frigo est à 3 ».
            if SpokenTemperature.parse(text) != nil { return .enregistrerTemperature }
            return nil
        }

        if !product.isDisjoint(with: words) { return .produitEntame }
        if !cleaning.isDisjoint(with: words) { return .nettoyage }
        if !sample.isDisjoint(with: words) { return .platTemoin }
        if !delivery.isDisjoint(with: words) { return .controleReception }

        return nil
    }

    #endif

    private static func words(in text: String) -> Set<String> {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        return Set(folded.split { !$0.isLetter }.map(String.init))
    }
}
