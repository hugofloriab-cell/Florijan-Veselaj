//
//  OperationProtocol.swift
//  HACCPPocket
//
//  Les modes opératoires : la marche à suivre, pas à pas, pour les gestes
//  qu'on croit connaître.
//
//  Un refroidissement raté ne se voit pas. Une réception bâclée non plus. Ce
//  sont des gestes qu'on exécute vite, souvent seul, et dont personne ne
//  vérifie l'ordre — jusqu'au jour où une analyse revient mauvaise. Ces
//  protocoles remplacent l'affiche jaunie derrière la porte de la réserve.
//
//  Ils ne s'enregistrent pas : ce sont des aide-mémoire consultables à tout
//  moment, pas un registre de plus à remplir.
//

import Foundation

// MARK: - Étape

struct ProtocolStep: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    /// Le « pourquoi », quand l'étape cache une raison qu'on oublie.
    let note: RegulatoryNote?

    init(id: String, title: String, detail: String, note: RegulatoryNote? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.note = note
    }
}

// MARK: - Protocole

struct OperationProtocol: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let steps: [ProtocolStep]
    /// L'erreur classique. Celle que tout le monde commet une fois.
    let commonMistake: String?
}

// MARK: - Catalogue

extension OperationProtocol {

    // MARK: Réception

    static let delivery = OperationProtocol(
        id: "protocol.delivery",
        title: "Contrôle à réception",
        subtitle: "Six gestes, dans cet ordre, avant de signer",
        systemImage: "shippingbox",
        steps: [
            ProtocolStep(
                id: "delivery.1",
                title: "Contrôlez le véhicule avant de décharger",
                detail: "Propreté de la caisse, absence d'odeur, température affichée du groupe froid. Un camion sale contamine la marchandise avant même qu'elle n'entre chez vous.",
                note: RegulatoryNote(
                    title: "Pourquoi contrôler avant de décharger ?",
                    explanation: "Tant que la marchandise est dans le camion, elle relève du transporteur. Dès que vous l'acceptez, elle devient la vôtre, avec la responsabilité qui va avec. Le contrôle se fait donc porte ouverte, pas une fois les palettes en réserve.",
                    origin: .regulation("Règlement (CE) n° 178/2002, article 19")
                )
            ),
            ProtocolStep(
                id: "delivery.2",
                title: "Vérifiez l'étiquetage et les dates",
                detail: "Dénomination, lot, DLC ou DDM, numéro d'agrément sanitaire. Sans lot lisible, la traçabilité est rompue et le produit se refuse.",
                note: RegulatoryNote(
                    title: "La règle du tiers",
                    explanation: "Beaucoup d'établissements refusent une denrée dont il reste moins d'un tiers de la durée de vie. Ce n'est pas une obligation légale, mais une clause commerciale courante : elle évite de recevoir des produits invendables et de les jeter à vos frais.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "delivery.3",
                title: "Contrôlez l'intégrité des emballages",
                detail: "Un emballage percé, déchiré, souillé ou une boîte de conserve bombée se refusent sans discussion. Un carton mouillé signale une rupture de chaîne du froid ou un dégât des eaux.",
                note: nil
            ),
            ProtocolStep(
                id: "delivery.4",
                title: "Prenez la température",
                detail: "Glissez la sonde entre deux produits, ou dans le carton, sans percer l'emballage. Percez uniquement un produit sacrifié, prévu pour ça.",
                note: RegulatoryNote(
                    title: "Pourquoi ne pas piquer les produits ?",
                    explanation: "Percer l'emballage rompt la protection du produit et y introduit ce que la sonde transporte. La température entre deux produits serrés est suffisamment représentative — et si elle est limite, on sacrifie une unité pour mesurer à cœur.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "delivery.5",
                title: "Décidez et tracez",
                detail: "Acceptation, acceptation partielle ou refus. Un refus se note sur le bon de livraison, contresigné par le chauffeur : c'est ce document qui vous couvre en cas de litige.",
                note: nil
            ),
            ProtocolStep(
                id: "delivery.6",
                title: "Rangez immédiatement",
                detail: "Le froid n'attend pas la fin du service. Les surgelés d'abord, puis le frais, l'épicerie en dernier.",
                note: RegulatoryNote(
                    title: "Combien de temps sur le quai ?",
                    explanation: "Une denrée réfrigérée laissée à température ambiante remonte vite : deux heures suffisent à consommer toute la marge de sécurité. Ranger prend deux minutes ; laisser traîner coûte une palette.",
                    origin: .practice
                )
            )
        ],
        commonMistake: "Signer le bon de livraison d'abord et contrôler ensuite. Une fois signé, le refus devient une négociation commerciale au lieu d'un droit."
    )

    // MARK: Refroidissement rapide

    static let rapidCooling = OperationProtocol(
        id: "protocol.cooling",
        title: "Refroidissement rapide",
        subtitle: "De +63 à +10 °C en moins de 2 heures",
        systemImage: "snowflake.circle",
        steps: [
            ProtocolStep(
                id: "cooling.1",
                title: "Démarrez le chrono à +63 °C",
                detail: "Le compte à rebours ne commence pas à la sortie du four, mais quand la préparation passe sous +63 °C.",
                note: nil
            ),
            ProtocolStep(
                id: "cooling.2",
                title: "Fractionnez en couches minces",
                detail: "Cinq centimètres d'épaisseur au maximum, dans des bacs larges et peu profonds. Retirez les gros morceaux d'un bloc.",
                note: RegulatoryNote(
                    title: "L'épaisseur décide, pas la puissance",
                    explanation: "Le froid progresse de l'extérieur vers le cœur. Doubler l'épaisseur quadruple le temps de refroidissement : une cellule de 10 000 € ne rattrapera jamais un bac trop rempli. C'est le geste, pas le matériel, qui fait tenir les deux heures.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "cooling.3",
                title: "Ne fermez pas hermétiquement pendant la descente",
                detail: "Un couvercle emprisonne la vapeur et isole la préparation. Couvrez sans sceller, ou laissez à découvert dans une cellule propre.",
                note: nil
            ),
            ProtocolStep(
                id: "cooling.4",
                title: "Contrôlez à cœur, jamais en surface",
                detail: "Sonde au centre de la masse la plus épaisse. La surface est toujours en avance de plusieurs degrés.",
                note: nil
            ),
            ProtocolStep(
                id: "cooling.5",
                title: "Objectif atteint : +10 °C en moins de 2 heures",
                detail: "Si la préparation n'y est pas, elle a passé trop de temps en zone de danger. L'application vous fera consigner l'écart et la conduite tenue.",
                note: RegulatoryNote(
                    title: "Pourquoi 2 heures ?",
                    explanation: "Entre +63 et +10 °C se trouve la zone où les bactéries se multiplient le plus vite, et où les spores survivantes de la cuisson se réveillent. Deux heures est la durée au-delà de laquelle leur nombre devient incompatible avec la conservation.",
                    origin: .regulation("Arrêté du 21 décembre 2009, article 12")
                )
            ),
            ProtocolStep(
                id: "cooling.6",
                title: "Filmez, étiquetez, datez, rangez",
                detail: "Nom de la préparation, date et heure de fabrication, date de retrait. Conservation à +3 °C.",
                note: nil
            )
        ],
        commonMistake: "Mettre le bac encore tiède directement au frigo. Il réchauffe toute l'enceinte et fait passer les denrées voisines en zone de danger — un seul geste, deux non-conformités."
    )

    // MARK: Remise en température

    static let reheating = OperationProtocol(
        id: "protocol.reheating",
        title: "Remise en température",
        subtitle: "Atteindre +63 °C en moins d'une heure",
        systemImage: "flame.circle",
        steps: [
            ProtocolStep(
                id: "reheating.1",
                title: "Sortez la quantité nécessaire, pas plus",
                detail: "Ce qui est remis en température ne retourne jamais au froid.",
                note: nil
            ),
            ProtocolStep(
                id: "reheating.2",
                title: "Montez vite et fort",
                detail: "Four, sauteuse ou bain-marie à pleine puissance. Une remise en température lente est exactement l'inverse de ce qu'on cherche.",
                note: nil
            ),
            ProtocolStep(
                id: "reheating.3",
                title: "Contrôlez à cœur avec une sonde désinfectée",
                detail: "Désinfectez la sonde entre chaque préparation : elle passe d'un bac à l'autre et transporte ce qu'elle trouve.",
                note: nil
            ),
            ProtocolStep(
                id: "reheating.4",
                title: "Servez, ou maintenez au-dessus de +63 °C",
                detail: "Sans interruption jusqu'au service. Le maintien au chaud conserve, il ne rattrape rien.",
                note: RegulatoryNote(
                    title: "Jamais deux fois",
                    explanation: "Chaque cycle chaud–froid–chaud fait retraverser la zone de danger et sélectionne les bactéries qui résistent. Une préparation remise en température se sert ou se jette : elle ne se remet pas au froid pour le lendemain.",
                    origin: .practice
                )
            )
        ],
        commonMistake: "Remettre en température au bain-marie doux pendant une heure et demie. La préparation passe tout ce temps dans la zone de danger avant d'en sortir."
    )

    // MARK: Décongélation

    static let thawing = OperationProtocol(
        id: "protocol.thawing",
        title: "Décongélation",
        subtitle: "En enceinte froide, jamais sur le plan de travail",
        systemImage: "snowflake.slash",
        steps: [
            ProtocolStep(
                id: "thawing.1",
                title: "En enceinte froide, à +3 °C",
                detail: "Comptez 24 heures pour 2 kg. Anticipez : une décongélation ne se rattrape pas au dernier moment.",
                note: RegulatoryNote(
                    title: "Pourquoi jamais à l'air libre ?",
                    explanation: "À température ambiante, la surface du produit atteint la zone de danger et y reste des heures pendant que le cœur est encore gelé. Les bactéries s'y multiplient sans que rien ne se voie : le produit paraît intact, sa charge bactérienne ne l'est plus.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "thawing.2",
                title: "Sur grille, avec un bac de récupération",
                detail: "L'exsudat qui s'écoule est chargé en bactéries. Il ne doit toucher ni le produit lui-même, ni ce qui est rangé en dessous.",
                note: nil
            ),
            ProtocolStep(
                id: "thawing.3",
                title: "En bas de l'enceinte, jamais au-dessus d'un produit prêt",
                detail: "Un produit en décongélation se range sous les produits cuits ou prêts à consommer, jamais au-dessus.",
                note: nil
            ),
            ProtocolStep(
                id: "thawing.4",
                title: "Étiquetez avec la nouvelle date de retrait",
                detail: "La DLC d'origine ne s'applique plus. Un produit décongelé se consomme sous 24 heures pour une viande ou un poisson.",
                note: RegulatoryNote(
                    title: "Pourquoi la DLC d'origine ne vaut plus rien",
                    explanation: "La DLC imprimée vaut pour le produit conservé congelé. La décongélation libère l'eau du produit et réveille les bactéries : le compteur repart, bien plus vite qu'avant congélation.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "thawing.5",
                title: "Ne recongelez jamais",
                detail: "Un produit décongelé se cuit ou se jette. Recongeler fige la population bactérienne sans la détruire.",
                note: nil
            )
        ],
        commonMistake: "Sortir la pièce le matin pour le service du soir, posée sur le plan de travail « pour aller plus vite ». C'est le geste qui produit le plus d'intoxications en restauration."
    )

    // MARK: Traitement assainissant

    static let sanitizingFreeze = OperationProtocol(
        id: "protocol.sanitizing",
        title: "Traitement assainissant du poisson",
        subtitle: "−20 °C pendant 24 h avant toute consommation crue",
        systemImage: "fish",
        steps: [
            ProtocolStep(
                id: "sanitizing.1",
                title: "Identifiez ce qui est concerné",
                detail: "Tout poisson destiné à être servi cru ou peu cuit : tartare, carpaccio, sushi, ceviche, marinade, fumage à froid, hareng au sel.",
                note: RegulatoryNote(
                    title: "Pourquoi ce traitement ?",
                    explanation: "Il détruit les larves d'anisakis, un parasite présent dans de nombreux poissons de mer. Vivantes, elles provoquent des douleurs abdominales violentes et des réactions allergiques. Ni le sel, ni le citron, ni le vinaigre ne les tuent.",
                    origin: .regulation("Règlement (CE) n° 853/2004, annexe III, section VIII")
                )
            ),
            ProtocolStep(
                id: "sanitizing.2",
                title: "Appliquez le barème, à cœur",
                detail: "−20 °C pendant au moins 24 heures, ou −35 °C pendant au moins 15 heures. La température se mesure au cœur du produit, pas dans l'air de l'enceinte.",
                note: nil
            ),
            ProtocolStep(
                id: "sanitizing.3",
                title: "Lancez le chronomètre et ne le clôturez pas trop tôt",
                detail: "Le barème court à partir du moment où le cœur atteint la température, pas de la mise au congélateur.",
                note: nil
            ),
            ProtocolStep(
                id: "sanitizing.4",
                title: "Consignez le lot",
                detail: "Produit, lot, fournisseur, destination, durée et température atteinte. C'est le premier document demandé dès qu'un établissement affiche du poisson cru.",
                note: nil
            )
        ],
        commonMistake: "Croire que le poisson livré surgelé dispense du traitement. Il en dispense seulement si le fournisseur atteste par écrit que le barème assainissant a été appliqué — sinon, c'est à vous de le faire."
    )

    // MARK: Plats témoins

    static let foodSample = OperationProtocol(
        id: "protocol.sample",
        title: "Plats témoins",
        subtitle: "100 g par plat, conservés 5 jours à +0/+3 °C",
        systemImage: "takeoutbag.and.cup.and.straw",
        steps: [
            ProtocolStep(
                id: "sample.1",
                title: "Prélevez au moment du service",
                detail: "Environ 100 g de chaque plat servi, prélevés dans ce qui part réellement en salle — pas dans la casserole restée en cuisine.",
                note: nil
            ),
            ProtocolStep(
                id: "sample.2",
                title: "Conditionnez et identifiez",
                detail: "Sachet ou barquette à usage unique, fermé hermétiquement. Étiquette : nom du plat, date et service.",
                note: nil
            ),
            ProtocolStep(
                id: "sample.3",
                title: "Conservez à +0/+3 °C, séparément",
                detail: "Dans un bac dédié, à l'écart des denrées en cours d'utilisation, pour que personne ne les consomme par erreur.",
                note: nil
            ),
            ProtocolStep(
                id: "sample.4",
                title: "Gardez cinq jours après la dernière présentation",
                detail: "Le délai court à partir du dernier service du plat, pas de sa fabrication.",
                note: RegulatoryNote(
                    title: "À quoi ça sert vraiment ?",
                    explanation: "À rien, tant que tout va bien. Le jour où un convive se déclare malade, c'est la seule pièce qui permet d'analyser ce qui a réellement été servi. Sans plat témoin, l'établissement est présumé responsable : il n'a aucun moyen de démontrer que son plat était conforme.",
                    origin: .regulation("Arrêté du 21 décembre 2009, article 32")
                )
            ),
            ProtocolStep(
                id: "sample.5",
                title: "Éliminez au terme du délai",
                detail: "Un échantillon périmé ne prouve plus rien et prend la place des suivants.",
                note: nil
            )
        ],
        commonMistake: "Prélever avant le service, dans la préparation d'origine. Le plat témoin doit refléter ce que le client a mangé, dressage compris."
    )

    // MARK: Nettoyage

    static let cleaning = OperationProtocol(
        id: "protocol.cleaning",
        title: "Nettoyage et désinfection",
        subtitle: "Six étapes — en sauter une annule les autres",
        systemImage: "sparkles",
        steps: [
            ProtocolStep(
                id: "cleaning.1",
                title: "Débarrassez et prélavez",
                detail: "Retirez les déchets et les résidus solides à l'eau tiède. Un détergent posé sur des restes ne nettoie rien : il les décolle, c'est tout.",
                note: nil
            ),
            ProtocolStep(
                id: "cleaning.2",
                title: "Lavez avec le détergent",
                detail: "Respectez la dilution indiquée sur le bidon et frottez. Le détergent décolle les graisses ; il ne tue pas les bactéries.",
                note: RegulatoryNote(
                    title: "Le cercle de Sinner",
                    explanation: "Un nettoyage efficace combine quatre facteurs : Température, Action mécanique, Concentration du produit et Temps de contact. Baisser l'un impose de monter les autres. C'est pourquoi diluer davantage « pour économiser » ne fonctionne pas : il faudrait frotter deux fois plus longtemps.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "cleaning.3",
                title: "Rincez",
                detail: "Le détergent restant neutraliserait le désinfectant. Cette étape n'est pas optionnelle.",
                note: nil
            ),
            ProtocolStep(
                id: "cleaning.4",
                title: "Désinfectez, et respectez le temps de contact",
                detail: "Lisez l'étiquette : la plupart des désinfectants demandent 5 à 15 minutes. Essuyer aussitôt revient à ne pas désinfecter.",
                note: RegulatoryNote(
                    title: "Le temps de contact",
                    explanation: "Un désinfectant agit par contact prolongé avec la surface. Le vaporiser puis passer le chiffon dans la foulée retire le produit avant qu'il n'ait agi : la surface est mouillée, pas désinfectée. C'est l'erreur la plus répandue en cuisine.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "cleaning.5",
                title: "Rincez à l'eau potable si le produit l'exige",
                detail: "Obligatoire sur toute surface en contact avec les aliments, sauf mention « sans rinçage » sur le bidon.",
                note: nil
            ),
            ProtocolStep(
                id: "cleaning.6",
                title: "Séchez à l'air libre",
                detail: "Un torchon recontamine ce qui vient d'être désinfecté. Laissez sécher, ou utilisez un papier à usage unique.",
                note: nil
            )
        ],
        commonMistake: "Vaporiser le désinfectant et essuyer tout de suite. Le geste rassure, le résultat est nul."
    )

    // MARK: Huiles de friture

    static let oilCheck = OperationProtocol(
        id: "protocol.oil",
        title: "Contrôle du bain de friture",
        subtitle: "Composés polaires : 25 % maximum",
        systemImage: "drop.triangle",
        steps: [
            ProtocolStep(
                id: "oil.1",
                title: "Filtrez le bain à froid",
                detail: "Les particules carbonisées accélèrent la dégradation de l'huile. Filtrer chaque jour double la durée de vie du bain.",
                note: nil
            ),
            ProtocolStep(
                id: "oil.2",
                title: "Mesurez avec le testeur, huile refroidie",
                detail: "Suivez la température de mesure indiquée par le fabricant du testeur : une mesure prise à chaud est fausse.",
                note: nil
            ),
            ProtocolStep(
                id: "oil.3",
                title: "Au-delà de 25 %, le bain se change",
                detail: "Sans testeur, fiez-vous aux signes : huile foncée, fumée à température normale, mousse persistante, odeur âcre.",
                note: RegulatoryNote(
                    title: "Pourquoi 25 % ?",
                    explanation: "En chauffant, l'huile se dégrade et forme des composés polaires. Au-delà de 25 %, la teneur est jugée impropre à la consommation humaine : l'huile n'est plus un corps gras mais un mélange de produits de dégradation.",
                    origin: .regulation("Arrêté du 8 janvier 2021 relatif aux huiles et graisses de friture")
                )
            ),
            ProtocolStep(
                id: "oil.4",
                title: "Consignez le contrôle",
                detail: "Date, friteuse, valeur mesurée, action menée. Le registre des huiles est demandé en contrôle au même titre que les températures.",
                note: nil
            )
        ],
        commonMistake: "Compléter un bain fatigué avec de l'huile neuve. La dilution fait baisser la mesure sans rien réparer : les composés polaires restent, et ils contaminent l'huile fraîche."
    )
}
