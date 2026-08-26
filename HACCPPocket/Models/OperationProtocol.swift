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
