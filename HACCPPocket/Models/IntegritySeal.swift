//
//  IntegritySeal.swift
//  HACCPPocket
//
//  Scellement d'un mois de registres.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CE MÉCANISME FAIT, ET CE QU'IL NE FAIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Il ne rend pas les données infalsifiables. Aucune application installée
//  sur l'appareil de son propriétaire ne le peut : celui qui contrôle le
//  téléphone contrôle la base. Promettre l'inverse serait mentir.
//
//  Ce qu'il fait, en revanche, a une vraie valeur : il rend toute
//  modification DÉTECTABLE. À la clôture d'un mois, l'application calcule une
//  empreinte de l'ensemble des enregistrements de la période et la conserve,
//  chaînée à celle du mois précédent. Recalculer plus tard donne la même
//  empreinte si rien n'a bougé, et une empreinte différente si un seul
//  caractère a changé.
//
//  Un registre scellé chaque mois et vérifiable est infiniment plus solide
//  qu'un classeur papier — que personne n'a jamais prétendu infalsifiable
//  non plus.
//

import Foundation
import SwiftData

@Model
final class IntegritySeal {

    /// Premier jour du mois scellé, à 00:00.
    var periodStart: Date = Date.now

    /// Moment du scellement.
    var sealedAt: Date = Date.now

    /// Empreinte des enregistrements de la période.
    var digest: String = ""

    /// Empreinte du scellé précédent, qui met les mois bout à bout. Retirer
    /// un scellé du milieu casse la chaîne, et cela se voit.
    var previousDigest: String = ""

    /// Nombre d'enregistrements couverts, affiché tel quel : un scellé qui
    /// couvrait 240 lignes et n'en retrouve que 180 dit quelque chose.
    var recordCount: Int = 0

    /// Rang du scellé dans la chaîne, à partir de 1.
    var sequence: Int = 1

    /// Qui a clôturé le mois.
    var sealedBy: String = ""

    var createdAt: Date = Date.now

    init(
        periodStart: Date = .now,
        sealedAt: Date = .now,
        digest: String = "",
        previousDigest: String = "",
        recordCount: Int = 0,
        sequence: Int = 1,
        sealedBy: String = "",
        createdAt: Date = .now
    ) {
        self.periodStart = periodStart
        self.sealedAt = sealedAt
        self.digest = digest
        self.previousDigest = previousDigest
        self.recordCount = recordCount
        self.sequence = sequence
        self.sealedBy = sealedBy
        self.createdAt = createdAt
    }

    // MARK: - Affichage

    var periodLabel: String {
        AppFormatters.sentenceCased(AppFormatters.monthTitle(periodStart))
    }

    /// Les huit premiers caractères suffisent à comparer à l'œil nu, et
    /// tiennent sur une ligne de PDF.
    var shortDigest: String {
        String(digest.prefix(8)).uppercased()
    }
}
