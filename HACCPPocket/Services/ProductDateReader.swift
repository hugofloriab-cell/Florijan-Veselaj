//
//  ProductDateReader.swift
//  HACCPPocket
//
//  DLC ou DDM : deux dates qui ne disent pas du tout la même chose.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA DISTINCTION QUE L'APPLICATION NE FAISAIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  « À consommer jusqu'au » est une **DLC** : passée cette date, le produit
//  présente un danger. C'est de la sécurité, et c'est opposable.
//
//  « À consommer de préférence avant » est une **DDM** — l'ancienne DLUO.
//  Passée cette date, le produit perd des qualités : du goût, de la
//  texture, des vitamines. Il ne devient pas dangereux. Le règlement
//  (UE) n° 1169/2011 distingue explicitement les deux mentions.
//
//  Traiter une DDM comme une DLC fait jeter des marchandises saines. La
//  traiter comme rien du tout fait perdre la traçabilité. D'où ce fichier.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA RÈGLE QUI NE PLIE PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  On ne prolonge jamais un produit au-delà de la DLC imprimée par le
//  fournisseur. Une durée de vie après ouverture se compte à partir de
//  l'ouverture, mais elle est toujours bornée par la date du fabricant.
//
//  Le cas inverse — du sucre, de la farine, du sel — se gouverne autrement.
//  Un produit sec et stable ne devient pas dangereux après sa DDM, et
//  recompter trente jours à partir de l'ouverture serait plus sévère que
//  l'emballage lui-même. On garde donc la date du fabricant, et ce qui
//  compte pour la traçabilité devient la **date d'ouverture**, inscrite sur
//  l'étiquette.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI EST PROPOSÉ, ET CE QUI EST DÉCIDÉ
//  ─────────────────────────────────────────────────────────────────────────
//
//  Les durées après ouverture de `FoodCategory` sont des usages
//  professionnels, pas la loi : le règlement 852/2004 demande à l'exploitant
//  de fixer ses propres durées et de pouvoir les justifier. L'assistant dit
//  donc toujours d'où vient la date qu'il propose, pour qu'elle puisse être
//  contestée en connaissance de cause.
//

import Foundation

/// La nature de la date imprimée sur l'emballage.
enum PrintedDateKind: String, Equatable, Sendable {
    /// « À consommer jusqu'au » — sécurité.
    case useBy
    /// « À consommer de préférence avant » — qualité.
    case bestBefore
    /// Rien de lisible, ou rien d'explicite.
    case unknown

    var label: String {
        switch self {
        case .useBy:      "DLC"
        case .bestBefore: "DDM"
        case .unknown:    "Date non lue"
        }
    }

    var spoken: String {
        switch self {
        case .useBy:      "date limite de consommation"
        case .bestBefore: "date de durabilité minimale"
        case .unknown:    "date non lue"
        }
    }
}

/// Une fiche produit en cours de constitution.
struct ProductDraft: Equatable, Sendable {
    var name: String
    var quantity: String = ""
    var photo: Data?

    var batchNumber: String = ""
    var supplier: String = ""

    /// La date lue sur l'emballage, quelle que soit sa nature.
    var printedDate: Date?
    var printedKind: PrintedDateKind = .unknown

    var category: FoodCategory?
    var allergens: Set<Allergen> = []
    var sawIngredientList = false

    var openedAt: Date = .now
    var secondaryLimit: Date = .now

    /// Pourquoi cette date, en une phrase dite à voix haute.
    var explanation: String = ""

    /// Vrai quand c'est la date d'ouverture qui fait foi sur l'étiquette,
    /// la date du fabricant restant celle de l'emballage.
    var openingDateGoverns = false

    var storage: StorageZone { category?.suggestedStorage ?? .positiveCold }
}

enum ProductDateReader {

    // MARK: - Construction

    static func draft(
        name: String,
        quantity: String,
        scan: LabelScanResult?,
        photo: Data?,
        openedAt: Date = .now,
        calendar: Calendar = .current
    ) -> ProductDraft {

        var draft = ProductDraft(name: name, quantity: quantity, photo: photo)
        draft.openedAt = openedAt

        if let scan {
            // Le nom lu sur l'étiquette l'emporte sur le nom dicté : il est
            // écrit par le fabricant, pas entendu dans une cuisine bruyante.
            let read = (scan.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !read.isEmpty { draft.name = read }

            draft.batchNumber = (scan.batchNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            draft.printedDate = scan.expiryDate
            draft.printedKind = kind(in: scan.recognizedLines)
            draft.category = scan.category
            draft.allergens = scan.allergens
            draft.sawIngredientList = scan.sawIngredientList
        }

        let decision = limit(
            printed: draft.printedDate,
            kind: draft.printedKind,
            category: draft.category,
            openedAt: openedAt,
            calendar: calendar
        )

        draft.secondaryLimit = decision.date
        draft.explanation = decision.explanation
        draft.openingDateGoverns = decision.openingDateGoverns

        return draft
    }

    // MARK: - La nature de la date

    /// Lit la mention qui accompagne la date.
    ///
    /// L'ordre compte : « à consommer de préférence avant » contient « à
    /// consommer », donc la DDM se teste avant la DLC, sans quoi toute DDM
    /// passerait pour une DLC — l'erreur qui fait jeter des produits sains.
    static func kind(in lines: [String]) -> PrintedDateKind {
        let text = lines
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))

        if bestBeforeMarkers.contains(where: text.contains) { return .bestBefore }
        if useByMarkers.contains(where: text.contains) { return .useBy }
        return .unknown
    }

    private static let bestBeforeMarkers = [
        "de preference avant", "preference avant", "ddm", "dluo",
        "best before", "a consommer de pref"
    ]

    private static let useByMarkers = [
        "a consommer jusqu", "consommer jusqu", "dlc", "use by",
        "a utiliser jusqu", "date limite de consommation"
    ]

    // MARK: - La date retenue

    struct Decision: Equatable, Sendable {
        var date: Date
        var explanation: String
        var openingDateGoverns: Bool
    }

    static func limit(
        printed: Date?,
        kind: PrintedDateKind,
        category: FoodCategory?,
        openedAt: Date,
        calendar: Calendar = .current
    ) -> Decision {

        let days = category?.shelfLifeDays ?? 3
        let afterOpening = calendar.date(byAdding: .day, value: days, to: openedAt) ?? openedAt
        let family = category?.label ?? "cette famille"

        switch kind {

        case .useBy:
            guard let printed else { break }

            // La règle intangible : jamais au-delà de la DLC du fabricant.
            if printed < afterOpening {
                return Decision(
                    date: printed,
                    explanation: "La DLC du fournisseur est le \(AppFormatters.shortDate(printed)). "
                        + "L'usage pour \(family.lowercased()) donnerait \(days) jours après ouverture, "
                        + "soit plus tard : on ne prolonge jamais au-delà de la date du fournisseur.",
                    openingDateGoverns: false
                )
            }

            return Decision(
                date: afterOpening,
                explanation: "DLC du fournisseur le \(AppFormatters.shortDate(printed)). "
                    + "Après ouverture, l'usage pour \(family.lowercased()) est de \(days) jours, "
                    + "soit le \(AppFormatters.shortDate(afterOpening)), qui tombe avant.",
                openingDateGoverns: false
            )

        case .bestBefore:
            guard let printed else { break }

            // Une denrée sèche et stable ne devient pas dangereuse après sa
            // DDM. Recompter une durée après ouverture serait plus sévère
            // que l'emballage, et ferait jeter des produits sains.
            if category == .dryGoods || category == nil {
                return Decision(
                    date: printed,
                    explanation: "C'est une DDM, pas une DLC : passée cette date le produit perd "
                        + "des qualités, il ne devient pas dangereux. Je garde celle de l'emballage, "
                        + "le \(AppFormatters.shortDate(printed)), et j'inscris la date d'ouverture "
                        + "sur l'étiquette.",
                    openingDateGoverns: true
                )
            }

            let kept = min(afterOpening, printed)
            return Decision(
                date: kept,
                explanation: "DDM de l'emballage le \(AppFormatters.shortDate(printed)). "
                    + "Le produit étant ouvert, je retiens le plus proche entre cette date et "
                    + "\(days) jours d'usage pour \(family.lowercased()).",
                openingDateGoverns: false
            )

        case .unknown:
            break
        }

        return Decision(
            date: afterOpening,
            explanation: "Aucune date lisible sur l'emballage. Je compte \(days) jours après "
                + "ouverture, usage courant pour \(family.lowercased()) — à ajuster si votre plan "
                + "de maîtrise sanitaire dit autre chose.",
            openingDateGoverns: false
        )
    }

    // MARK: - Le tableau affiché

    static func rows(for draft: ProductDraft) -> [AssistantReport.Row] {
        var rows: [AssistantReport.Row] = []

        rows.append(AssistantReport.Row(
            label: "Produit",
            detail: draft.quantity.isEmpty ? "Quantité non dite" : draft.quantity,
            value: draft.name.isEmpty ? "—" : draft.name,
            isAlert: draft.name.isEmpty
        ))

        if let category = draft.category {
            rows.append(AssistantReport.Row(
                label: "Famille",
                detail: "\(category.shelfLifeDays) jours après ouverture, usage courant",
                value: category.label,
                isAlert: false
            ))
        }

        if let printed = draft.printedDate {
            rows.append(AssistantReport.Row(
                label: draft.printedKind.label,
                detail: "Lue sur l'emballage",
                value: AppFormatters.shortDate(printed),
                isAlert: false
            ))
        } else {
            rows.append(AssistantReport.Row(
                label: "Date de l'emballage",
                detail: "Rien de lisible sur la photo",
                value: "—",
                isAlert: true
            ))
        }

        rows.append(AssistantReport.Row(
            label: "Ouvert le",
            detail: draft.openingDateGoverns ? "C'est la mention qui fait foi" : "Début de la durée de vie",
            value: AppFormatters.shortDate(draft.openedAt),
            isAlert: false
        ))

        rows.append(AssistantReport.Row(
            label: "À retirer le",
            detail: "Date retenue pour le registre",
            value: AppFormatters.shortDate(draft.secondaryLimit),
            isAlert: false
        ))

        if !draft.batchNumber.isEmpty {
            rows.append(AssistantReport.Row(
                label: "Lot",
                detail: "Lu sur l'emballage",
                value: draft.batchNumber,
                isAlert: false
            ))
        }

        if !draft.allergens.isEmpty {
            let names = draft.allergens.map(\.label).sorted().joined(separator: ", ")
            rows.append(AssistantReport.Row(
                label: "Allergènes",
                detail: "Lus dans la liste d'ingrédients",
                value: names,
                isAlert: false
            ))
        }

        return rows
    }
}
