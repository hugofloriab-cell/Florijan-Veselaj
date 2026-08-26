//
//  CorrectiveActionGuide.swift
//  HACCPPocket
//
//  L'arbre de décision qui remplace le champ « action corrective » vide.
//
//  Un écart de température sans action corrective écrite rend le registre
//  incomplet. Mais demander à un commis de rédiger cette action à 22 h, en
//  coup de feu, produit invariablement « RAS » ou « vu avec le chef ». Ce
//  fichier remplace la page blanche par des questions fermées, dont la
//  réponse rédige elle-même la ligne du registre.
//
//  Les conduites à tenir suivent les règles constantes de la chaîne du froid :
//  la zone +10 / +63 °C est la zone de danger, deux heures au-dessus de
//  +4 °C imposent de trancher, et une denrée décongelée ne se recongèle
//  jamais.
//

import Foundation

// MARK: - Gravité

enum CorrectiveSeverity: Sendable, Equatable {
    /// Situation rattrapable, l'enceinte revient en température.
    case recoverable
    /// Denrées à surveiller ou à écouler en priorité.
    case watch
    /// Retrait des denrées : on ne discute pas.
    case discard

    var systemImage: String {
        switch self {
        case .recoverable: "arrow.clockwise.circle.fill"
        case .watch:       "exclamationmark.circle.fill"
        case .discard:     "trash.circle.fill"
        }
    }
}

// MARK: - Conclusion

/// Ce que l'utilisateur doit faire, et la phrase qui part au registre.
struct CorrectiveConclusion: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    /// Marche à suivre, dans l'ordre.
    let instructions: [String]
    /// Texte inscrit au registre. Rédigé au passé : au moment où
    /// l'utilisateur valide, le geste est fait.
    let recordedAction: String
    let severity: CorrectiveSeverity
    /// Précision réglementaire, quand elle éclaire la consigne.
    let note: RegulatoryNote?
}

// MARK: - Options et étapes

indirect enum CorrectiveOutcome: Sendable, Equatable {
    case next(CorrectiveStep)
    case conclusion(CorrectiveConclusion)
}

struct CorrectiveOption: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let detail: String
    let systemImage: String
    let outcome: CorrectiveOutcome
}

struct CorrectiveStep: Identifiable, Sendable, Equatable {
    let id: String
    let question: String
    /// Une phrase pour aider à répondre, quand la question mérite un cadrage.
    let help: String?
    let options: [CorrectiveOption]
}

// MARK: - Catalogue

enum CorrectiveActionGuide {

    /// L'arbre à dérouler pour une enceinte donnée.
    ///
    /// Trois familles seulement : le froid positif, le froid négatif et le
    /// maintien au chaud. Les conduites à tenir y sont radicalement
    /// différentes, alors qu'elles se ressemblent à l'intérieur de chacune.
    static func tree(for equipment: Equipment, measured: Double) -> CorrectiveStep {
        switch equipment.type {
        case .negativeCold:
            return freezerTree
        case .hotHolding:
            return hotHoldingTree
        case .positiveCold, .coldRoom, .displayCase, .blastChiller:
            return coldStorageTree(tooCold: measured < equipment.acceptedRange.lowerBound)
        }
    }

    // MARK: Froid positif

    private static func coldStorageTree(tooCold: Bool) -> CorrectiveStep {
        // Une enceinte trop froide ne présente pas de risque microbiologique :
        // le problème est la qualité des denrées, pas leur salubrité. Inutile
        // de dérouler tout l'arbre pour ça.
        if tooCold {
            return CorrectiveStep(
                id: "cold.tooCold",
                question: "L'enceinte est plus froide que prévu. Qu'avez-vous constaté ?",
                help: "Une température trop basse n'est pas un danger sanitaire, mais elle abîme les denrées et fait givrer l'enceinte.",
                options: [
                    CorrectiveOption(
                        id: "cold.tooCold.thermostat",
                        label: "Thermostat déréglé",
                        detail: "Quelqu'un a modifié le réglage",
                        systemImage: "dial.medium",
                        outcome: .conclusion(
                            CorrectiveConclusion(
                                id: "cold.tooCold.thermostat.done",
                                title: "Thermostat remis au bon réglage",
                                instructions: [
                                    "Remettez le thermostat à la consigne de l'enceinte.",
                                    "Vérifiez que les denrées les plus sensibles ne sont pas gelées.",
                                    "Refaites un relevé dans 2 heures."
                                ],
                                recordedAction: "Thermostat déréglé, remis à la consigne. Denrées contrôlées, nouveau relevé programmé.",
                                severity: .recoverable,
                                note: nil
                            )
                        )
                    ),
                    CorrectiveOption(
                        id: "cold.tooCold.frozen",
                        label: "Des denrées ont gelé",
                        detail: "Légumes, produits laitiers, œufs",
                        systemImage: "snowflake",
                        outcome: .conclusion(
                            CorrectiveConclusion(
                                id: "cold.tooCold.frozen.done",
                                title: "Denrées gelées à écarter",
                                instructions: [
                                    "Écartez les denrées gelées : leur texture est perdue et l'emballage a pu se fissurer.",
                                    "Remettez le thermostat à la consigne.",
                                    "Refaites un relevé dans 2 heures."
                                ],
                                recordedAction: "Enceinte trop froide, denrées gelées écartées. Thermostat remis à la consigne.",
                                severity: .watch,
                                note: nil
                            )
                        )
                    )
                ]
            )
        }

        return CorrectiveStep(
            id: "cold.start",
            question: "Depuis quand l'écart dure-t-il ?",
            help: "C'est la durée passée au-dessus de la température, bien plus que l'écart lui-même, qui décide du sort des denrées.",
            options: [
                CorrectiveOption(
                    id: "cold.start.recent",
                    label: "Je viens de le constater",
                    detail: "Dernier relevé conforme, écart récent",
                    systemImage: "clock",
                    outcome: .next(coldQuickCheckStep)
                ),
                CorrectiveOption(
                    id: "cold.start.prolonged",
                    label: "Plusieurs heures, ou depuis hier",
                    detail: "Nuit, week-end, retour de fermeture",
                    systemImage: "moon.zzz",
                    outcome: .next(coldCoreTemperatureStep)
                )
            ]
        )
    }

    private static var coldQuickCheckStep: CorrectiveStep {
        CorrectiveStep(
            id: "cold.quickCheck",
            question: "Regardez l'enceinte. Que voyez-vous ?",
            help: "Neuf écarts sur dix ont une cause matérielle et immédiate.",
            options: [
                CorrectiveOption(
                    id: "cold.quickCheck.door",
                    label: "Porte mal fermée ou restée ouverte",
                    detail: "Joint pris, bac qui dépasse",
                    systemImage: "door.left.hand.open",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.quickCheck.door.done",
                            title: "Porte refermée, retour en température à vérifier",
                            instructions: [
                                "Refermez la porte et dégagez ce qui gênait le joint.",
                                "Refaites un relevé dans 1 heure.",
                                "Si la température n'est pas redescendue, revenez ici et choisissez « l'enceinte semble en panne »."
                            ],
                            recordedAction: "Porte mal fermée, refermée immédiatement. Nouveau relevé programmé à 1 heure.",
                            severity: .recoverable,
                            note: nil
                        )
                    )
                ),
                CorrectiveOption(
                    id: "cold.quickCheck.overloaded",
                    label: "Enceinte surchargée ou arrivage récent",
                    detail: "Marchandise chaude rentrée, circulation d'air bloquée",
                    systemImage: "shippingbox.fill",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.quickCheck.overloaded.done",
                            title: "Chargement allégé",
                            instructions: [
                                "Répartissez la marchandise, dégagez la grille de ventilation.",
                                "Ne remettez jamais un plat encore tiède dans une enceinte de conservation : il doit passer par un refroidissement rapide.",
                                "Refaites un relevé dans 1 heure."
                            ],
                            recordedAction: "Enceinte surchargée, chargement réparti et ventilation dégagée. Nouveau relevé programmé à 1 heure.",
                            severity: .recoverable,
                            note: RegulatoryNote(
                                title: "Pourquoi ne pas y mettre un plat tiède ?",
                                explanation: "Un plat chaud réchauffe toute l'enceinte et fait passer les denrées voisines en zone de danger. Un plat cuisiné doit descendre de +63 à +10 °C en moins de 2 heures, dans une cellule ou un bain d'eau glacée — pas dans le frigo.",
                                origin: .regulation("Arrêté du 21 décembre 2009, article 12")
                            )
                        )
                    )
                ),
                CorrectiveOption(
                    id: "cold.quickCheck.breakdown",
                    label: "Rien d'anormal, l'enceinte semble en panne",
                    detail: "Groupe silencieux, givre anormal, afficheur éteint",
                    systemImage: "bolt.trianglebadge.exclamationmark",
                    outcome: .next(coldBreakdownStep)
                )
            ]
        )
    }

    private static var coldCoreTemperatureStep: CorrectiveStep {
        CorrectiveStep(
            id: "cold.coreTemperature",
            question: "Sondez une denrée à cœur. Quelle température lisez-vous ?",
            help: "C'est la température de la denrée qui compte, pas celle de l'air. Une enceinte à +9 °C depuis une heure peut contenir des produits encore à +4 °C.",
            options: [
                CorrectiveOption(
                    id: "cold.core.safe",
                    label: "+4 °C ou moins",
                    detail: "Les denrées sont restées froides",
                    systemImage: "checkmark.circle",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.core.safe.done",
                            title: "Denrées à transférer et à écouler en priorité",
                            instructions: [
                                "Transférez les denrées dans une enceinte conforme.",
                                "Écoulez-les en priorité, sans attendre leur DLC.",
                                "Faites intervenir sur l'enceinte avant de la recharger."
                            ],
                            recordedAction: "Écart prolongé constaté. Température à cœur des denrées ≤ +4 °C, denrées transférées en enceinte conforme et écoulées en priorité.",
                            severity: .watch,
                            note: nil
                        )
                    )
                ),
                CorrectiveOption(
                    id: "cold.core.above",
                    label: "Plus de +4 °C",
                    detail: "Les denrées sont montées",
                    systemImage: "thermometer.high",
                    outcome: .next(coldDurationStep)
                ),
                CorrectiveOption(
                    id: "cold.core.unknown",
                    label: "Je n'ai pas de sonde",
                    detail: "Impossible de mesurer à cœur",
                    systemImage: "questionmark.circle",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.core.unknown.done",
                            title: "Sans mesure, on tranche par la prudence",
                            instructions: [
                                "Retirez les denrées les plus sensibles : viandes, poissons, produits laitiers ouverts, plats cuisinés.",
                                "Notez ce retrait dans le registre des non-conformités.",
                                "Équipez la cuisine d'un thermomètre sonde : sans lui, aucun écart ne peut être tranché autrement que par la destruction."
                            ],
                            recordedAction: "Écart prolongé, température à cœur non mesurable faute de sonde. Denrées sensibles retirées par précaution.",
                            severity: .discard,
                            note: RegulatoryNote(
                                title: "Pourquoi une sonde est indispensable",
                                explanation: "Le règlement impose de disposer des instruments de mesure nécessaires à la maîtrise des températures. Sans thermomètre sonde, un écart ne peut jamais être levé : la seule décision défendable devient le retrait.",
                                origin: .regulation("Règlement (CE) n° 852/2004, annexe II, chapitre IX")
                            )
                        )
                    )
                )
            ]
        )
    }

    private static var coldDurationStep: CorrectiveStep {
        CorrectiveStep(
            id: "cold.duration",
            question: "Depuis combien de temps les denrées sont-elles au-dessus de +4 °C ?",
            help: "Deux heures : c'est la durée au-delà de laquelle la multiplication bactérienne n'est plus rattrapable.",
            options: [
                CorrectiveOption(
                    id: "cold.duration.short",
                    label: "Moins de 2 heures",
                    detail: "Écart court et daté avec certitude",
                    systemImage: "timer",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.duration.short.done",
                            title: "Transfert immédiat et consommation sous 24 heures",
                            instructions: [
                                "Transférez immédiatement les denrées dans une enceinte conforme.",
                                "Consommez-les dans les 24 heures, quelle que soit leur DLC d'origine.",
                                "Ne les recongelez pas, ne les reconditionnez pas."
                            ],
                            recordedAction: "Denrées au-dessus de +4 °C moins de 2 heures. Transfert immédiat en enceinte conforme, consommation imposée sous 24 heures.",
                            severity: .watch,
                            note: nil
                        )
                    )
                ),
                CorrectiveOption(
                    id: "cold.duration.long",
                    label: "Plus de 2 heures, ou je ne sais pas",
                    detail: "Nuit, week-end, durée incertaine",
                    systemImage: "exclamationmark.triangle",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.duration.long.done",
                            title: "Retrait des denrées",
                            instructions: [
                                "Retirez les denrées de la consommation et rendez-les impropres à l'usage.",
                                "Notez la nature, les lots et les quantités détruites.",
                                "Ne les reversez pas au personnel : la même règle vaut pour tout le monde.",
                                "Faites intervenir sur l'enceinte avant de la recharger."
                            ],
                            recordedAction: "Denrées au-dessus de +4 °C plus de 2 heures ou durée indéterminée. Retrait et destruction, nature et lots consignés.",
                            severity: .discard,
                            note: RegulatoryNote(
                                title: "Pourquoi 2 heures ?",
                                explanation: "Entre +10 et +63 °C, une population bactérienne peut doubler toutes les vingt minutes. Deux heures suffisent à franchir le seuil où le froid ne rattrape plus rien : refroidir de nouveau stoppe la multiplication mais ne détruit ni les bactéries déjà présentes, ni les toxines qu'elles ont produites.",
                                origin: .practice
                            )
                        )
                    )
                )
            ]
        )
    }

    private static var coldBreakdownStep: CorrectiveStep {
        CorrectiveStep(
            id: "cold.breakdown",
            question: "Avez-vous une autre enceinte disponible ?",
            help: nil,
            options: [
                CorrectiveOption(
                    id: "cold.breakdown.transfer",
                    label: "Oui, j'ai transféré les denrées",
                    detail: "Autre enceinte, camion frigo, voisin",
                    systemImage: "arrow.left.arrow.right",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.breakdown.transfer.done",
                            title: "Denrées sauvées, dépannage à déclencher",
                            instructions: [
                                "Appelez le frigoriste et notez l'heure de l'appel.",
                                "Signalez l'enceinte hors service pour que personne ne la recharge.",
                                "Contrôlez la température de l'enceinte d'accueil : elle vient de recevoir une charge."
                            ],
                            recordedAction: "Enceinte en panne. Denrées transférées en enceinte conforme, frigoriste contacté, enceinte signalée hors service.",
                            severity: .watch,
                            note: nil
                        )
                    )
                ),
                CorrectiveOption(
                    id: "cold.breakdown.none",
                    label: "Non, aucune solution de repli",
                    detail: "Rien d'autre où stocker",
                    systemImage: "xmark.octagon",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "cold.breakdown.none.done",
                            title: "Denrées à retirer",
                            instructions: [
                                "Appelez le frigoriste immédiatement et notez l'heure.",
                                "Sondez ce qui peut l'être : ce qui est encore à +4 °C ou moins doit être consommé dans les 24 heures.",
                                "Retirez le reste et consignez la destruction.",
                                "Envisagez une location de matériel froid si la panne dure."
                            ],
                            recordedAction: "Enceinte en panne, aucune solution de repli. Frigoriste contacté, denrées triées à la sonde, retrait consigné.",
                            severity: .discard,
                            note: nil
                        )
                    )
                )
            ]
        )
    }

    // MARK: Froid négatif

    private static var freezerTree: CorrectiveStep {
        CorrectiveStep(
            id: "freezer.start",
            question: "Regardez les produits. Dans quel état sont-ils ?",
            help: "Sur du congelé, c'est l'état du produit qui décide, pas la température de l'air.",
            options: [
                CorrectiveOption(
                    id: "freezer.hard",
                    label: "Encore durs, toujours givrés",
                    detail: "Aucun signe de décongélation",
                    systemImage: "cube.fill",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "freezer.hard.done",
                            title: "Produits conservés, retour en température à vérifier",
                            instructions: [
                                "Refermez, dégagez le joint et n'ouvrez plus la porte.",
                                "Vérifiez que le givre ne bloque pas la ventilation.",
                                "Refaites un relevé dans 2 heures."
                            ],
                            recordedAction: "Écart constaté, produits encore durs et givrés, aucun signe de décongélation. Enceinte refermée, nouveau relevé programmé à 2 heures.",
                            severity: .recoverable,
                            note: nil
                        )
                    )
                ),
                CorrectiveOption(
                    id: "freezer.partial",
                    label: "Mous en surface, emballages humides",
                    detail: "Décongélation commencée",
                    systemImage: "drop.degreesign",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "freezer.partial.done",
                            title: "Ne jamais recongeler",
                            instructions: [
                                "Ne remettez pas ces produits au congélateur.",
                                "Placez-les en froid positif et cuisez-les à cœur dans les 24 heures, ou retirez-les.",
                                "Notez les lots concernés.",
                                "Faites intervenir sur l'enceinte avant de la recharger."
                            ],
                            recordedAction: "Décongélation partielle constatée. Produits basculés en froid positif pour cuisson sous 24 heures, recongélation exclue, lots consignés.",
                            severity: .discard,
                            note: RegulatoryNote(
                                title: "Pourquoi ne jamais recongeler ?",
                                explanation: "La décongélation libère l'eau du produit et réveille les bactéries, qui se multiplient d'autant plus vite que les cristaux ont déchiré les cellules. Recongeler fige cette population sans la détruire : au dégel suivant, on repart d'une charge bactérienne bien plus élevée, invisible et sans signe d'altération.",
                                origin: .practice
                            )
                        )
                    )
                ),
                CorrectiveOption(
                    id: "freezer.thawed",
                    label: "Complètement décongelés",
                    detail: "Souples, jus au fond du bac",
                    systemImage: "trash",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "freezer.thawed.done",
                            title: "Retrait des produits",
                            instructions: [
                                "Retirez les produits de la consommation.",
                                "Notez la nature, les lots et les quantités.",
                                "Appelez le frigoriste et notez l'heure.",
                                "Ne rechargez pas l'enceinte avant remise en service."
                            ],
                            recordedAction: "Produits entièrement décongelés, durée d'exposition indéterminée. Retrait et destruction, lots consignés, frigoriste contacté.",
                            severity: .discard,
                            note: nil
                        )
                    )
                )
            ]
        )
    }

    // MARK: Maintien au chaud

    private static var hotHoldingTree: CorrectiveStep {
        CorrectiveStep(
            id: "hot.start",
            question: "Depuis combien de temps la préparation est-elle sous +63 °C ?",
            help: "Sous +63 °C, la préparation est entrée dans la zone de danger. Seule la durée décide.",
            options: [
                CorrectiveOption(
                    id: "hot.short",
                    label: "Moins de 2 heures",
                    detail: "Service en cours, durée connue",
                    systemImage: "timer",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "hot.short.done",
                            title: "Remise en température immédiate",
                            instructions: [
                                "Remontez la préparation au-dessus de +63 °C sans attendre.",
                                "La remise en température doit atteindre +63 °C en moins d'une heure.",
                                "Contrôlez à la sonde avant de remettre au service.",
                                "Réglez le bain-marie ou l'étuve, ou faites-le vérifier."
                            ],
                            recordedAction: "Maintien au chaud sous +63 °C moins de 2 heures. Remise en température immédiate, contrôle à la sonde avant remise au service.",
                            severity: .recoverable,
                            note: RegulatoryNote(
                                title: "Pourquoi +63 °C ?",
                                explanation: "C'est la borne haute de la zone de danger. Au-dessus, les bactéries ne se multiplient plus. Le maintien au chaud n'est pas une cuisson : il conserve, il ne rattrape rien.",
                                origin: .regulation("Arrêté du 21 décembre 2009, article 13")
                            )
                        )
                    )
                ),
                CorrectiveOption(
                    id: "hot.long",
                    label: "Plus de 2 heures, ou je ne sais pas",
                    detail: "Service prolongé, durée incertaine",
                    systemImage: "exclamationmark.triangle",
                    outcome: .conclusion(
                        CorrectiveConclusion(
                            id: "hot.long.done",
                            title: "Retrait de la préparation",
                            instructions: [
                                "Retirez la préparation du service.",
                                "Ne la refroidissez pas pour la resservir : la durée passée en zone de danger est déjà consommée.",
                                "Notez la nature et les quantités détruites.",
                                "Faites vérifier le matériel de maintien au chaud."
                            ],
                            recordedAction: "Maintien au chaud sous +63 °C plus de 2 heures ou durée indéterminée. Préparation retirée du service et détruite, quantités consignées.",
                            severity: .discard,
                            note: nil
                        )
                    )
                )
            ]
        )
    }
}
