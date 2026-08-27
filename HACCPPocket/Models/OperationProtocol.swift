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

    // MARK: Relevé de température

    static let temperatureReading = OperationProtocol(
        id: "protocol.temperature",
        title: "Relevé de température",
        subtitle: "Deux fois par jour, et à la sonde de temps en temps",
        systemImage: "thermometer.medium",
        steps: [
            ProtocolStep(
                id: "temp.1",
                title: "Relevez à l'ouverture et à la fermeture",
                detail: "Deux relevés par jour et par enceinte. Celui du matin dit ce qui s'est passé la nuit, celui du soir engage la nuit qui vient.",
                note: nil
            ),
            ProtocolStep(
                id: "temp.2",
                title: "Ne vous fiez pas qu'à l'afficheur",
                detail: "Contrôlez à la sonde au moins une fois par semaine, et comparez avec l'afficheur. L'écart entre les deux est l'information la plus utile du registre.",
                note: RegulatoryNote(
                    title: "Un afficheur dérive",
                    explanation: "Le thermomètre intégré d'une enceinte mesure l'air à un seul endroit, souvent près de l'évaporateur, là où il fait le plus froid. Il dérive aussi avec le temps. Un afficheur qui indique +2 °C pendant qu'une sonde lit +7 °C au milieu de la chambre n'est pas rare, et c'est la sonde qui a raison.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "temp.3",
                title: "Sondez entre deux produits",
                detail: "Au milieu de l'enceinte, entre deux denrées serrées, sans percer les emballages. Pas devant la porte, pas contre la paroi du fond.",
                note: nil
            ),
            ProtocolStep(
                id: "temp.4",
                title: "Désinfectez la sonde entre deux enceintes",
                detail: "Elle passe du cru au cuit, du poisson à la crème. Lingette désinfectante à chaque changement.",
                note: nil
            ),
            ProtocolStep(
                id: "temp.5",
                title: "N'ouvrez pas la porte plus que nécessaire",
                detail: "Préparez le carnet ou le téléphone avant d'ouvrir. Une porte ouverte deux minutes fait remonter une chambre froide de plusieurs degrés.",
                note: nil
            ),
            ProtocolStep(
                id: "temp.6",
                title: "Vérifiez votre sonde une fois par mois",
                detail: "Plongez-la dans un verre d'eau et de glace fondante, remué : elle doit indiquer 0 °C, à un demi-degré près. Sinon, faites-la étalonner ou remplacez-la.",
                note: RegulatoryNote(
                    title: "Le test du verre de glace",
                    explanation: "Un mélange d'eau et de glace en train de fondre est à 0 °C, toujours, quelle que soit la pièce. C'est un point de référence gratuit, disponible dans n'importe quelle cuisine, et il permet de vérifier une sonde en trois minutes. Une sonde fausse rend tout le registre faux.",
                    origin: .practice
                )
            )
        ],
        commonMistake: "Recopier le chiffre de l'afficheur pendant des mois sans jamais le confronter à une sonde. Le jour où l'écart se révèle, tout le registre devient contestable."
    )

    // MARK: Lavage des mains

    static let handWashing = OperationProtocol(
        id: "protocol.handwashing",
        title: "Lavage des mains",
        subtitle: "Trente secondes, et à chaque changement de tâche",
        systemImage: "hands.and.sparkles",
        steps: [
            ProtocolStep(
                id: "hands.1",
                title: "Mouillez à l'eau tiède",
                detail: "Tiède, pas brûlante : l'eau chaude abîme la peau sans tuer davantage de bactéries.",
                note: nil
            ),
            ProtocolStep(
                id: "hands.2",
                title: "Savonnez 30 secondes",
                detail: "Paumes, dos des mains, entre les doigts, pouces, bouts des ongles, et jusqu'aux poignets. Les pouces et les ongles sont les zones systématiquement oubliées.",
                note: RegulatoryNote(
                    title: "Pourquoi 30 secondes",
                    explanation: "En dessous, le savon n'a pas le temps de décoller le film gras sous lequel les bactéries sont protégées. C'est la durée et le frottement qui font le travail, pas la température de l'eau.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "hands.3",
                title: "Rincez abondamment",
                detail: "Du bout des doigts vers les poignets, pour ne pas ramener l'eau souillée sur les mains propres.",
                note: nil
            ),
            ProtocolStep(
                id: "hands.4",
                title: "Séchez avec du papier à usage unique",
                detail: "Des mains humides transfèrent bien plus de bactéries que des mains sèches.",
                note: RegulatoryNote(
                    title: "Jamais le torchon de service",
                    explanation: "Un torchon utilisé toute la journée est l'un des objets les plus contaminés de la cuisine. S'essuyer les mains dessus après les avoir lavées annule tout ce qui vient d'être fait.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "hands.5",
                title: "Fermez le robinet avec le papier",
                detail: "La poignée a été touchée par des mains sales. Le lave-mains à commande non manuelle règle le problème définitivement.",
                note: nil
            ),
            ProtocolStep(
                id: "hands.6",
                title: "Recommencez à chaque changement de tâche",
                detail: "En arrivant, après les toilettes, après avoir manipulé du cru, des déchets, de l'argent, un téléphone, après s'être mouché, et avant de passer au propre.",
                note: nil
            )
        ],
        commonMistake: "Croire que les gants dispensent du lavage. Un gant se contamine exactement comme une main, et il donne en plus le sentiment d'être protégé : on se surveille moins."
    )

    // MARK: Étiquetage et DLC secondaire

    static let productLabelling = OperationProtocol(
        id: "protocol.labelling",
        title: "Étiquetage des produits entamés",
        subtitle: "Nom, date d'ouverture, date de retrait",
        systemImage: "tag",
        steps: [
            ProtocolStep(
                id: "label.1",
                title: "Étiquetez au moment d'ouvrir",
                detail: "Pas plus tard. Une heure après, personne ne se souviendra si le bac a été ouvert aujourd'hui ou avant-hier.",
                note: nil
            ),
            ProtocolStep(
                id: "label.2",
                title: "Trois mentions minimum",
                detail: "Désignation du produit, date d'ouverture, date de retrait. Le lot en plus, si vous l'avez.",
                note: nil
            ),
            ProtocolStep(
                id: "label.3",
                title: "Ne dépassez jamais la DLC du fournisseur",
                detail: "La durée après ouverture s'arrête à la DLC imprimée, jamais après. C'est le plus court des deux qui s'applique.",
                note: RegulatoryNote(
                    title: "Qui fixe la durée après ouverture ?",
                    explanation: "Vous. Aucun texte ne donne de tableau de DLC secondaires : le règlement 852/2004 met cette responsabilité sur l'exploitant, qui doit pouvoir justifier ses durées — par son guide de bonnes pratiques, par des analyses, ou par son plan de maîtrise sanitaire.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "label.4",
                title: "Transvasez les conserves",
                detail: "Une boîte ouverte n'est plus un conditionnement alimentaire : le métal nu s'oxyde au contact de l'air. Bac alimentaire, filmé, étiqueté.",
                note: nil
            ),
            ProtocolStep(
                id: "label.5",
                title: "Premier entré, premier sorti",
                detail: "Rangez les nouveaux arrivages derrière, jamais devant. C'est la règle qui évite l'essentiel du gaspillage.",
                note: nil
            )
        ],
        commonMistake: "Réétiqueter un produit dont la date approche pour « gagner » deux jours. C'est une falsification de registre, et c'est ce que cherche un contrôleur quand il compare vos étiquettes à vos bons de livraison."
    )

    // MARK: Allergènes

    static let allergens = OperationProtocol(
        id: "protocol.allergens",
        title: "Renseigner les allergènes",
        subtitle: "Plat par plat, sauces comprises",
        systemImage: "shield.lefthalf.filled",
        steps: [
            ProtocolStep(
                id: "allergen.1",
                title: "Reprenez les étiquettes de tous les ingrédients",
                detail: "Y compris ceux que vous n'achetez pas pour eux-mêmes : bouillons, fonds, sauces industrielles, panures, pâtes feuilletées.",
                note: nil
            ),
            ProtocolStep(
                id: "allergen.2",
                title: "N'oubliez pas ce qui ne se voit pas",
                detail: "Le céleri dans les bouillons, le poisson dans la sauce Worcestershire, le soja dans les panures, le lait dans certaines charcuteries.",
                note: RegulatoryNote(
                    title: "Les oublis les plus fréquents",
                    explanation: "Les allergènes cachés sont ceux qui envoient des clients à l'hôpital : ils ne sont pas dans l'ingrédient principal mais dans un produit d'assemblage qu'on ne pense pas à retourner. Un fond de veau du commerce contient très souvent du céleri.",
                    origin: .practice
                )
            ),
            ProtocolStep(
                id: "allergen.3",
                title: "Pensez aux contaminations croisées",
                detail: "Même friteuse, même planche, même pince : un plat sans gluten frit dans l'huile des beignets n'est plus sans gluten. Signalez-le au client plutôt que de le taire.",
                note: nil
            ),
            ProtocolStep(
                id: "allergen.4",
                title: "Mettez à jour à chaque changement de recette",
                detail: "Changer de fournisseur de sauce suffit à changer la liste. Une fiche qui date de six mois ne vaut rien.",
                note: nil
            ),
            ProtocolStep(
                id: "allergen.5",
                title: "Rendez l'information disponible",
                detail: "Affichage en salle, mention sur la carte, ou indication écrite que l'information est disponible sur demande — mais alors le document doit exister et être accessible immédiatement.",
                note: RegulatoryNote(
                    title: "Ce que la loi impose exactement",
                    explanation: "L'information sur les quatorze allergènes doit être disponible pour tous les plats non préemballés, par écrit et sans que le client ait à la demander deux fois. Un affichage, un classeur au comptoir ou une mention sur la carte conviennent — l'oral seul ne suffit pas.",
                    origin: .regulation("Règlement (UE) n° 1169/2011 et décret n° 2015-447")
                )
            ),
            ProtocolStep(
                id: "allergen.6",
                title: "En cas de doute, ne servez pas",
                detail: "Dites-le au client. Une réponse honnête vaut infiniment mieux qu'une approximation.",
                note: nil
            )
        ],
        commonMistake: "Remplir les fiches de mémoire, sans reprendre les emballages. C'est ainsi qu'on oublie le céleri du bouillon et le soja de la panure."
    )

    // MARK: Lutte contre les nuisibles

    static let pestControl = OperationProtocol(
        id: "protocol.pest",
        title: "Lutte contre les nuisibles",
        subtitle: "Ce qui se fait entre deux visites du prestataire",
        systemImage: "ant",
        steps: [
            ProtocolStep(
                id: "pest.1",
                title: "Fermez les accès",
                detail: "Bas de portes, grilles d'aération, siphons, passages de gaines. Une souris passe où un stylo passe.",
                note: nil
            ),
            ProtocolStep(
                id: "pest.2",
                title: "Ne laissez rien au sol",
                detail: "Stockage sur étagères ou palettes, à distance des murs, pour pouvoir voir et nettoyer derrière.",
                note: nil
            ),
            ProtocolStep(
                id: "pest.3",
                title: "Sortez les déchets tous les jours",
                detail: "Poubelles à couvercle, local à déchets fermé et nettoyé. C'est la première source de nourriture d'une infestation.",
                note: nil
            ),
            ProtocolStep(
                id: "pest.4",
                title: "Relevez les postes d'appâtage",
                detail: "Notez ce que vous constatez, même quand il n'y a rien : un registre qui ne dit rien pendant six mois puis signale une infestation n'est pas crédible.",
                note: nil
            ),
            ProtocolStep(
                id: "pest.5",
                title: "Gardez le plan et les rapports",
                detail: "Plan de localisation des postes, contrat du prestataire, et chaque rapport d'intervention. C'est l'ensemble qui est demandé, pas seulement le dernier passage.",
                note: nil
            ),
            ProtocolStep(
                id: "pest.6",
                title: "Ne traitez jamais vous-même",
                detail: "Les produits grand public n'ont rien à faire dans une cuisine professionnelle, et leur présence est une non-conformité à elle seule.",
                note: RegulatoryNote(
                    title: "Pourquoi passer par un professionnel",
                    explanation: "Les biocides utilisables en milieu alimentaire sont réglementés, et leur emploi suppose une localisation, un suivi et une traçabilité. Un raticide de supermarché posé derrière un frigo contamine la cuisine et n'apporte aucune preuve de maîtrise.",
                    origin: .practice
                )
            )
        ],
        commonMistake: "Attendre de voir un nuisible pour agir. Quand on en voit un en journée, la population est déjà installée depuis longtemps."
    )

    // MARK: Origine des viandes

    static let beefOrigin = OperationProtocol(
        id: "protocol.beef",
        title: "Origine des viandes",
        subtitle: "Toutes les viandes de la carte, trois pays chacune",
        systemImage: "text.badge.checkmark",
        steps: [
            ProtocolStep(
                id: "beef.0",
                title: "Listez toutes les viandes de votre carte",
                detail: "Bœuf, porc, agneau, volaille : chaque viande proposée doit figurer sur l'affichage. Si vous en servez dix, les dix sont listées, une par une.",
                note: RegulatoryNote(
                    title: "Ce n'est plus seulement le bœuf",
                    explanation: "L'obligation ne visait que la viande bovine jusqu'en 2022. Le décret n° 2022-65 du 26 janvier 2022 l'a étendue aux viandes porcine, ovine et de volaille servies en restauration. Un établissement qui n'affiche que l'origine de son bœuf n'est plus à jour.",
                    origin: .regulation("Décret n° 2022-65 modifiant le décret n° 2002-1455")
                )
            ),
            ProtocolStep(
                id: "beef.1",
                title: "Cherchez les trois pays sur l'étiquette",
                detail: "Naissance, élevage, abattage. Ils figurent obligatoirement sur le document du fournisseur.",
                note: nil
            ),
            ProtocolStep(
                id: "beef.2",
                title: "Photographiez l'étiquette",
                detail: "C'est elle qui fait foi. La mention affichée en salle doit pouvoir être rattachée au document d'origine, lot par lot.",
                note: nil
            ),
            ProtocolStep(
                id: "beef.3",
                title: "Affichez la mention exacte",
                detail: "Trois pays identiques : « Origine : France ». Sinon, les trois doivent être cités.",
                note: RegulatoryNote(
                    title: "Pourquoi trois pays et pas un",
                    explanation: "Un animal peut naître dans un pays, être engraissé dans un autre et abattu dans un troisième. Écrire « Origine France » parce que l'abattoir est français, quand l'animal est né et élevé ailleurs, est une information trompeuse au sens du droit de la consommation.",
                    origin: .regulation("Décret n° 2002-1455 relatif à l'étiquetage des viandes en restauration")
                )
            ),
            ProtocolStep(
                id: "beef.4",
                title: "Mettez à jour à chaque lot",
                detail: "L'origine change d'un arrivage à l'autre. L'affichage aussi.",
                note: nil
            ),
            ProtocolStep(
                id: "beef.5",
                title: "Éditez le document et affichez-le",
                detail: "Le registre produit un document daté reprenant toutes les viandes à la carte avec leurs trois pays. Imprimez-le et affichez-le en salle, ou reportez les mentions sur vos cartes et menus.",
                note: nil
            )
        ],
        commonMistake: "Afficher « Origine France » de façon permanente parce que c'est le cas la plupart du temps. Le jour où le fournisseur dépanne avec un autre lot, l'affichage devient faux."
    )

    // MARK: Formation du personnel

    static let staffTraining = OperationProtocol(
        id: "protocol.training",
        title: "Formation à l'hygiène alimentaire",
        subtitle: "Au moins une personne formée dans l'établissement",
        systemImage: "graduationcap",
        steps: [
            ProtocolStep(
                id: "training.1",
                title: "Une personne formée au minimum",
                detail: "Tout établissement de restauration commerciale doit compter au moins une personne ayant suivi une formation spécifique en hygiène alimentaire.",
                note: RegulatoryNote(
                    title: "Ce que dit le texte",
                    explanation: "La formation dure quatorze heures et se suit auprès d'un organisme déclaré. Elle n'est pas exigée de tous : une seule personne formée dans l'établissement suffit à satisfaire l'obligation.",
                    origin: .regulation("Décret n° 2011-731 et arrêté du 5 octobre 2011")
                )
            ),
            ProtocolStep(
                id: "training.2",
                title: "Vérifiez les équivalences avant de payer",
                detail: "Certains diplômes du secteur alimentaire dispensent de la formation, de même qu'une expérience professionnelle suffisante comme gestionnaire ou exploitant. Vérifiez avant d'inscrire quelqu'un.",
                note: nil
            ),
            ProtocolStep(
                id: "training.3",
                title: "Formez aussi en interne",
                detail: "Le reste de l'équipe doit être instruit des règles d'hygiène adaptées à son poste. Une demi-heure à l'embauche, tracée, vaut mieux qu'un rappel improvisé après un incident.",
                note: RegulatoryNote(
                    title: "L'obligation qui vise tout le monde",
                    explanation: "Au-delà de la formation certifiante, le règlement impose que toute personne manipulant des denrées soit encadrée et instruite en matière d'hygiène, à un niveau adapté à son activité. C'est à l'exploitant de le démontrer.",
                    origin: .regulation("Règlement (CE) n° 852/2004, annexe II, chapitre XII")
                )
            ),
            ProtocolStep(
                id: "training.4",
                title: "Archivez les attestations",
                detail: "L'attestation de l'organisme, et la trace des formations internes : qui, quand, sur quoi.",
                note: nil
            )
        ],
        commonMistake: "Croire que la formation du gérant dispense d'instruire l'équipe. Ce sont deux obligations distinctes, et c'est la seconde qu'on oublie de tracer."
    )

    // MARK: Prélèvement de surface

    static let surfaceSampling = OperationProtocol(
        id: "protocol.sampling",
        title: "Prélèvement de surface",
        subtitle: "Après nettoyage : c'est lui qu'on évalue",
        systemImage: "square.grid.3x3",
        steps: [
            ProtocolStep(
                id: "sampling.1",
                title: "Prélevez après nettoyage et désinfection",
                detail: "Sur une surface sèche et prête à l'emploi. Prélever sur une planche sale ne mesure rien : c'est l'efficacité du nettoyage que l'analyse évalue, pas la saleté.",
                note: nil
            ),
            ProtocolStep(
                id: "sampling.2",
                title: "Choisissez les endroits qui posent problème",
                detail: "Trancheuse, joints, poignées de chambre froide, planches entaillées, robots. Prélever au milieu d'un plan de travail neuf donnera toujours un bon résultat, et n'apprendra rien.",
                note: nil
            ),
            ProtocolStep(
                id: "sampling.3",
                title: "Respectez la surface indiquée par le kit",
                detail: "En général dix centimètres sur dix. Un résultat s'exprime par unité de surface : changer la surface change le résultat.",
                note: nil
            ),
            ProtocolStep(
                id: "sampling.4",
                title: "Identifiez et acheminez au froid",
                detail: "Nom du point, date, heure. Le délai et la température de transport font partie de la validité de l'analyse.",
                note: nil
            ),
            ProtocolStep(
                id: "sampling.5",
                title: "Un mauvais résultat appelle une suite écrite",
                detail: "Revoir le protocole, la dilution, le temps de contact, ou remplacer un matériel devenu impossible à nettoyer. Puis re-prélever pour vérifier.",
                note: RegulatoryNote(
                    title: "À quelle fréquence analyser ?",
                    explanation: "Aucun texte n'impose de périodicité à un restaurant. Le règlement 2073/2005 fixe les seuils, pas les fréquences : c'est à vous de prévoir dans votre plan de maîtrise sanitaire les analyses que vous jugez nécessaires, et de pouvoir justifier ce choix. Ne jamais rien analyser, en revanche, revient à ne pas pouvoir démontrer que vos procédures fonctionnent.",
                    origin: .practice
                )
            )
        ],
        commonMistake: "Prélever toujours au même endroit facile, pour avoir de bons résultats. L'analyse devient un rituel décoratif au lieu d'un outil de contrôle."
    )

    // MARK: Huiles usagées

    static let wasteOil = OperationProtocol(
        id: "protocol.wasteoil",
        title: "Huiles usagées",
        subtitle: "Un déchet, pas un rebut",
        systemImage: "arrow.3.trianglepath",
        steps: [
            ProtocolStep(
                id: "wasteoil.1",
                title: "Ne jetez jamais à l'évier",
                detail: "L'huile fige dans les canalisations, bouche le réseau et perturbe le traitement des eaux usées. C'est interdit, et c'est aussi le meilleur moyen de payer un débouchage.",
                note: nil
            ),
            ProtocolStep(
                id: "wasteoil.2",
                title: "Stockez à froid, dans des bidons fermés",
                detail: "Contenants dédiés, étiquetés, dans un local à l'abri. L'huile chaude déforme les bidons et attire les nuisibles.",
                note: nil
            ),
            ProtocolStep(
                id: "wasteoil.3",
                title: "Faites enlever par un collecteur",
                detail: "La collecte est généralement gratuite : l'huile usagée est valorisée. Demandez le numéro d'agrément du collecteur avant le premier enlèvement.",
                note: nil
            ),
            ProtocolStep(
                id: "wasteoil.4",
                title: "Conservez chaque bordereau",
                detail: "Date, quantité, collecteur, numéro de bon. C'est cette suite de documents qui constitue votre registre des déchets.",
                note: RegulatoryNote(
                    title: "Le registre des déchets",
                    explanation: "Tout producteur de déchets tient un registre chronologique de leur production, de leur expédition et de leur traitement, et le conserve au moins trois ans. Pour un restaurant, la suite des bons d'enlèvement d'huiles en constitue l'essentiel.",
                    origin: .regulation("Code de l'environnement, article R. 541-43")
                )
            ),
            ProtocolStep(
                id: "wasteoil.5",
                title: "Confrontez les volumes à votre registre de friture",
                detail: "Des bains changés toutes les semaines et aucun enlèvement depuis six mois : la contradiction se voit tout de suite, et elle se verra aussi de l'autre côté.",
                note: nil
            )
        ],
        commonMistake: "Laisser partir l'huile avec « quelqu'un qui passe » sans bordereau ni agrément. Sans document, vous restez responsable du devenir du déchet."
    )

    // MARK: Retrait et rappel

    static let productRecall = OperationProtocol(
        id: "protocol.recall",
        title: "Retrait ou rappel d'un produit",
        subtitle: "Les six gestes des premières heures",
        systemImage: "exclamationmark.octagon",
        steps: [
            ProtocolStep(
                id: "recall.1",
                title: "Isolez le lot immédiatement",
                detail: "Sortez-le du circuit, mettez-le à part, étiquetez-le « NE PAS UTILISER ». Avant toute autre démarche : pendant que vous téléphonez, quelqu'un peut l'attraper.",
                note: nil
            ),
            ProtocolStep(
                id: "recall.2",
                title: "Cherchez partout, pas seulement en réserve",
                detail: "Frigos, congélateurs, préparations en cours, plats déjà cuisinés contenant l'ingrédient, plats témoins. Un lot rappelé se cache souvent dans une sauce faite la veille.",
                note: nil
            ),
            ProtocolStep(
                id: "recall.3",
                title: "Déterminez si le produit a été servi",
                detail: "C'est cette réponse qui fait la différence entre un retrait et un rappel. Retrait : le produit est encore chez vous. Rappel : il est parti chez le consommateur.",
                note: RegulatoryNote(
                    title: "Retrait ou rappel ?",
                    explanation: "Le retrait consiste à empêcher la distribution d'un produit encore sous votre contrôle. Le rappel va plus loin : il vise à récupérer un produit déjà remis au consommateur, et impose de l'informer. Les deux relèvent de la même obligation de fond — un exploitant qui a des raisons de penser qu'une denrée est dangereuse doit engager immédiatement les procédures de retrait et en informer les autorités.",
                    origin: .regulation("Règlement (CE) n° 178/2002, article 19")
                )
            ),
            ProtocolStep(
                id: "recall.4",
                title: "Remontez au fournisseur, par écrit",
                detail: "Demandez la fiche d'alerte, la procédure de retour et le sort réservé au lot. Un échange écrit vaut mieux qu'un appel dont il ne reste rien.",
                note: nil
            ),
            ProtocolStep(
                id: "recall.5",
                title: "Déclarez à la DDPP si le produit a été servi",
                detail: "La direction départementale de la protection des populations de votre département. Notez la date, l'heure et l'interlocuteur.",
                note: RegulatoryNote(
                    title: "Le délai qui compte",
                    explanation: "Le texte parle d'action immédiate, sans fixer d'heures. Dans les faits, c'est le délai entre le moment où vous avez su et le moment où vous avez agi qui sera examiné. Un registre qui montre l'isolement dans l'heure et la déclaration dans la journée est une défense ; un registre muet ne l'est pas.",
                    origin: .regulation("Règlement (CE) n° 178/2002, article 19")
                )
            ),
            ProtocolStep(
                id: "recall.6",
                title: "Détruisez ou retournez, avec une preuve",
                detail: "Bon de retour signé, bordereau de destruction, ou photo du produit rendu impropre à la consommation. Sans preuve, la destruction n'a pas eu lieu.",
                note: nil
            )
        ],
        commonMistake: "Jeter le lot à la poubelle et passer à autre chose. Le geste est le bon, mais sans trace il ne prouve rien — et il fait perdre l'information sur les quantités, indispensable si l'alerte s'élargit."
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
