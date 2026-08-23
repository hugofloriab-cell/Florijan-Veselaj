//
//  BrandAssets.swift
//  HACCPPocket
//
//  Identité visuelle de l'application : couleur de marque et logo.
//
//  Le logo est un PNG en niveaux de gris + alpha, livré dans `Resources/`.
//  Seul son canal alpha porte le tracé : affiché en mode « template », il se
//  teinte automatiquement, et reste donc lisible en clair comme en sombre.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum BrandAssets {

    /// Bleu du logo, échantillonné sur le tracé d'origine.
    static let color = Color(red: 23 / 255, green: 80 / 255, blue: 127 / 255)

    /// Nom commercial, utilisé dans les documents produits par l'app.
    static let productName = "HACCP Pocket"

    static let logoResourceName = "BrandLogo"

    #if canImport(UIKit)
    /// Chargé une seule fois : le PDF le redessine à chaque page.
    static let logoImage: UIImage? = {
        guard let image = UIImage(named: logoResourceName) else { return nil }
        return image.withRenderingMode(.alwaysTemplate)
    }()

    /// Version teintée, pour les contextes qui ne gèrent pas le mode template
    /// — le rendu PDF, notamment.
    static func tintedLogo(_ tint: UIColor, size: CGSize) -> UIImage? {
        guard let logo = UIImage(named: logoResourceName) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            tint.setFill()
            let rect = CGRect(origin: .zero, size: size)
            logo.draw(in: rect)
            UIRectFillUsingBlendMode(rect, .sourceIn)
        }
    }
    #endif
}

// MARK: - Vue réutilisable

/// Le logo, à la taille demandée et à la couleur de marque par défaut.
struct BrandLogo: View {

    var size: CGFloat = 48
    var tint: Color = BrandAssets.color

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = BrandAssets.logoImage {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                // Repli si la ressource n'a pas été embarquée dans le bundle :
                // mieux vaut un symbole correct qu'un carré vide.
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
            }
            #else
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
            #endif
        }
        .frame(width: size, height: size)
        .foregroundStyle(tint)
        .accessibilityLabel("Logo \(BrandAssets.productName)")
    }
}

// MARK: - Raccourci de couleur

extension Color {
    /// Accent de l'application, aligné sur le logo.
    static let brand = BrandAssets.color
}
