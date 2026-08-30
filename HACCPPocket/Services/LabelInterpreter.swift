//
//  LabelInterpreter.swift
//  HACCPPocket
//
//  Ce qu'on peut tirer du texte d'un emballage, au-delà des dates.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI SE LIT, CE QUI SE DÉDUIT, CE QUI SE CALCULE
//  ─────────────────────────────────────────────────────────────────────────
//
//  La distinction est importante, et l'écran doit la montrer : toutes les
//  informations d'une fiche produit n'ont pas la même valeur de preuve.
//
//  SE LIT sur l'emballage — la machine recopie, elle n'invente pas :
//    • la dénomination
//    • le code-barres
//    • les allergènes, mis en avant dans la liste d'ingrédients
//    • la date limite imprimée par le fournisseur
//
//  SE DÉDUIT — proposition à confirmer, jamais une certitude :
//    • la famille de denrée, devinée d'après la dénomination et les
//      ingrédients
//    • la zone de stockage, qui découle de la famille
//
//  SE CALCULE — aucune photo ne les porte :
//    • la date d'ouverture : c'est aujourd'hui, par définition
//    • la durée de vie secondaire : c'est VOTRE décision, au titre du plan
//      de maîtrise sanitaire. Aucun texte ne la fixe et aucune étiquette ne
//      la porte. L'application propose l'usage de la profession.
//    • la date de retrait : ouverture + durée de vie, plafonnée par la date
//      limite du fournisseur — on ne prolonge jamais un produit au-delà.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI LES ALLERGÈNES SE LISENT VRAIMENT
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le règlement (UE) n° 1169/2011 impose que les quatorze allergènes soient
//  mis en évidence dans la liste d'ingrédients — en gras, en majuscules ou
//  soulignés. Ils y figurent donc toujours, écrits en toutes lettres, ce qui
//  les rend repérables par simple correspondance de mots.
//
//  ⚠️ La reconnaissance ne remplace pas la lecture. Un ingrédient composé
//  peut masquer un allergène sous un nom commercial, et une photo floue peut
//  faire manquer une ligne. Ce que l'application propose doit être vérifié
//  sur l'emballage — l'écran le dit, et la fiche allergènes que vous
//  produirez engage votre responsabilité, pas la sienne.
//

import Foundation

enum LabelInterpreter {

    // MARK: - Allergènes

    /// Mots qui trahissent chaque allergène dans une liste d'ingrédients.
    ///
    /// Les racines sont volontairement courtes — « glut » attrape « gluten »
    /// et « glutineux » — mais jamais au point d'être ambiguës : « ble »
    /// seul attraperait « ensemble » ou « faible », d'où la forme accordée.
    private static let allergenKeywords: [Allergen: [String]] = [
        .gluten: ["gluten", "ble ", "ble,", "ble.", "froment", "seigle", "orge",
                  "avoine", "epeautre", "kamut", "malt", "semoule", "farine de ble",
                  "chapelure", "couscous", "boulgour"],
        .crustaceans: ["crustac", "crevette", "langoustine", "homard", "crabe",
                       "ecrevisse", "langouste", "tourteau"],
        .eggs: ["oeuf", "œuf", "ovoproduit", "albumine", "lysozyme", "jaune d'oeuf",
                "blanc d'oeuf", "lecithine d'oeuf"],
        .fish: ["poisson", "cabillaud", "saumon", "thon", "anchois", "hareng",
                "sardine", "colin", "merlu", "truite", "maquereau", "surimi",
                "garum", "nuoc-mam"],
        .peanuts: ["arachide", "cacahuete", "cacahouete"],
        .soybeans: ["soja", "soya", "tofu", "edamame", "tamari", "miso"],
        .milk: ["lait", "lactose", "lactoserum", "petit-lait", "beurre", "creme",
                "fromage", "caseine", "caseinate", "yaourt", "yogourt", "ricotta",
                "mascarpone", "babeurre", "ghee"],
        .nuts: ["fruits a coque", "amande", "noisette", "noix", "cajou", "pecan",
                "pistache", "macadamia", "noix du bresil", "praline"],
        .celery: ["celeri", "céleri"],
        .mustard: ["moutarde", "senev"],
        .sesame: ["sesame", "tahin", "tahini", "gomasio"],
        .sulphites: ["sulfite", "anhydride sulfureux", "so2", "e220", "e221",
                     "e222", "e223", "e224", "e226", "e227", "e228", "metabisulfite"],
        .lupin: ["lupin"],
        .molluscs: ["mollusque", "moule", "huitre", "huître", "calamar", "calmar",
                    "seiche", "poulpe", "escargot", "coquille saint-jacques",
                    "palourde", "bulot", "encornet"]
    ]

    /// Cherche les allergènes déclarés dans le texte reconnu.
    ///
    /// Le texte entier est examiné, pas seulement la ligne d'ingrédients : la
    /// reconnaissance découpe souvent la liste sur plusieurs lignes, et une
    /// mention « peut contenir » vit parfois à l'écart.
    static func allergens(in lines: [String]) -> Set<Allergen> {
        let haystack = normalize(lines.joined(separator: " "))
        guard haystack.count > 12 else { return [] }

        var found: Set<Allergen> = []

        for (allergen, keywords) in allergenKeywords {
            for keyword in keywords where haystack.contains(normalize(keyword)) {
                found.insert(allergen)
                break
            }
        }

        return found
    }

    /// La photo montre-t-elle une liste d'ingrédients ?
    ///
    /// Sans elle, une absence d'allergène ne veut rien dire : il faut le
    /// distinguer d'une liste lue qui n'en contient réellement aucun.
    static func containsIngredientList(_ lines: [String]) -> Bool {
        let haystack = normalize(lines.joined(separator: " "))
        return haystack.contains("ingredient")
            || haystack.contains("composition")
            || haystack.contains("peut contenir")
    }

    // MARK: - Famille de denrée

    /// Mots qui rattachent un produit à une famille.
    ///
    /// L'ordre du tableau compte : la première famille dont un mot apparaît
    /// l'emporte, et les familles les plus spécifiques sont donc placées
    /// avant les plus générales.
    private static let categoryKeywords: [(FoodCategory, [String])] = [
        (.rawFish, ["poisson cru", "saumon", "thon", "cabillaud", "truite",
                    "filet de poisson", "tartare de poisson", "sashimi", "crevette",
                    "gambas", "saint-jacques", "moule", "huitre"]),
        (.rawMeat, ["viande", "boeuf", "bœuf", "veau", "agneau", "porc", "volaille",
                    "poulet", "dinde", "canard", "steak", "entrecote", "bavette",
                    "escalope", "hache", "tartare"]),
        (.charcuterie, ["jambon", "saucisson", "chorizo", "lardon", "pate",
                        "rillette", "terrine", "coppa", "bacon", "mortadelle"]),
        (.cheese, ["fromage", "comte", "gruyere", "emmental", "mozzarella",
                   "chevre", "roquefort", "brie", "camembert", "parmesan",
                   "feta", "raclette"]),
        (.openedDairy, ["lait", "creme", "beurre", "yaourt", "fromage blanc",
                        "mascarpone", "ricotta", "faisselle"]),
        (.pastry, ["patisserie", "gateau", "tarte", "creme patissiere",
                   "chantilly", "mousse", "entremets", "eclair"]),
        (.sauce, ["sauce", "fond de", "bouillon", "coulis", "vinaigrette",
                  "mayonnaise", "beurre blanc", "veloute"]),
        (.cutVegetables, ["salade", "legume", "carotte", "tomate", "courgette",
                          "poireau", "oignon", "champignon", "epinard", "mesclun",
                          "roquette", "concombre"]),
        (.openedCan, ["conserve", "boite de", "bocal", "en boite"]),
        (.vacuumPacked, ["sous vide", "sous-vide"]),
        (.cookedDish, ["plat cuisine", "gratin", "lasagne", "hachis", "curry",
                       "risotto", "blanquette", "ragout", "soupe", "potage"]),
        (.dryGoods, ["farine", "sucre", "riz", "pate", "semoule", "lentille",
                     "haricot sec", "epice", "the", "cafe", "cacao", "matcha",
                     "poudre", "biscuit", "cereale", "huile", "vinaigre", "sel"])
    ]

    /// Devine la famille de denrée.
    ///
    /// La dénomination est examinée d'abord : c'est elle qui dit ce qu'est le
    /// produit. Les ingrédients ne servent qu'en second recours, parce qu'une
    /// sauce contenant du lait n'est pas un produit laitier.
    static func category(name: String?, lines: [String]) -> FoodCategory? {
        if let name, let match = matchCategory(in: name) { return match }
        return matchCategory(in: lines.prefix(6).joined(separator: " "))
    }

    private static func matchCategory(in text: String) -> FoodCategory? {
        let haystack = normalize(text)
        guard !haystack.isEmpty else { return nil }

        for (category, keywords) in categoryKeywords {
            for keyword in keywords where haystack.contains(normalize(keyword)) {
                return category
            }
        }
        return nil
    }

    // MARK: - Outils

    /// Minuscules, sans accents : simplifie toutes les correspondances.
    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)
            .lowercased()
    }
}
