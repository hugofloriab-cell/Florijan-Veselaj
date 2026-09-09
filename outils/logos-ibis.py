# -*- coding: utf-8 -*-
"""Remplace les logos ibis de la carte par ceux de l'identité actuelle.

Les PDF portaient encore les anciens logos — coussins en dégradé, ombre
portée, mention « HOTELS » — là où l'enseigne emploie aujourd'hui des
aplats. On échange les deux images à l'intérieur du PDF, à leur place et à
leur taille : le reste du document n'est pas touché, et la carte affichée
reste celle du restaurant.

Deux précautions, sans quoi l'échange se verrait :

  • les fichiers fournis sont détourés et leur coussin n'occupe que 67 % du
    cadre, contre 90 à 95 % pour les anciens : posés tels quels, les logos
    auraient rapetissé. On les recadre sur leur dessin, puis on rétablit la
    proportion d'origine ;

  • le PDF attend des images opaques. On aplatit donc la transparence sur
    la couleur du fond de page, relevée sur l'ancien logo lui-même — celui
    qui s'y fondait déjà.

    python3 logos-ibis.py     # écrit les PDF corrigés dans cartes/
"""
import os

import cv2
import numpy as np
import pymupdf

U = "/root/.claude/uploads/eb973e87-7c35-50ce-8874-e9267b19fddb/"
SOURCES = {
    "fr": U + "84455ab2-Carte_Les_Tilleuls_Automne_2026.pdf",
    "en": U + "200304f2-Les_Tilleuls_Autumn_Menu_2026_EN.pdf",
}
# xref de l'ancien logo dans le PDF -> fichier du nouveau
REMPLACEMENTS = {
    63: U + "2eb6af02-image.png",  # ibis, rouge
    65: U + "5730c79e-image.png",  # ibis budget, bleu
}
ICI = os.path.dirname(os.path.abspath(__file__))
SORTIE = os.path.join(ICI, "cartes")
COTE = 460  # même définition que les images remplacées


def fond_de(image_ancienne):
    """La couleur du fond de page, relevée aux quatre coins de l'ancien logo."""
    h, w = image_ancienne.shape[:2]
    coins = [image_ancienne[2, 2], image_ancienne[2, w - 3],
             image_ancienne[h - 3, 2], image_ancienne[h - 3, w - 3]]
    return np.median(np.array(coins, dtype=float), axis=0)


def part_encrée(image, fond):
    """Quelle part de la largeur le dessin occupe, fond mis à part."""
    masque = np.any(np.abs(image.astype(float) - fond) > 18, axis=2)
    xs = np.where(masque.any(axis=0))[0]
    ys = np.where(masque.any(axis=1))[0]
    if not len(xs) or not len(ys):
        return 1.0
    return max(xs.max() - xs.min(), ys.max() - ys.min()) / image.shape[1]


def preparer(chemin_neuf, fond, part_visée):
    """Le nouveau logo, recadré sur son dessin et aplati sur le fond."""
    im = cv2.imread(chemin_neuf, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("logo illisible : " + chemin_neuf)
    if im.shape[2] != 4:
        raise SystemExit("logo sans transparence : " + chemin_neuf)

    alpha = im[:, :, 3]
    ys, xs = np.where(alpha > 10)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    # Cadrage carré autour du dessin, pour ne pas le déformer
    cote = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    demi = cote // 2
    haut = np.zeros((cote, cote, 4), np.uint8)
    sx0, sy0 = max(0, cx - demi), max(0, cy - demi)
    decoupe = im[sy0:sy0 + cote, sx0:sx0 + cote]
    haut[:decoupe.shape[0], :decoupe.shape[1]] = decoupe

    # Le dessin doit occuper la même part du cadre que l'ancien logo
    utile = max(1, int(round(COTE * part_visée)))
    petit = cv2.resize(haut, (utile, utile), interpolation=cv2.INTER_AREA)

    toile = np.zeros((COTE, COTE, 4), np.uint8)
    d = (COTE - utile) // 2
    toile[d:d + utile, d:d + utile] = petit

    a = toile[:, :, 3:4].astype(float) / 255.0
    return (toile[:, :, :3].astype(float) * a + np.array(fond) * (1 - a)).astype(np.uint8)


if __name__ == "__main__":
    os.makedirs(SORTIE, exist_ok=True)
    for langue, chemin in SOURCES.items():
        doc = pymupdf.open(chemin)
        # Les deux logos ne figurent que sur la dernière page ; le
        # remplacement s'y opère, et vaut pour toutes ses occurrences.
        page = doc[7]
        for xref, neuf in REMPLACEMENTS.items():
            ancien = cv2.imdecode(
                np.frombuffer(doc.extract_image(xref)["image"], np.uint8), cv2.IMREAD_COLOR
            )
            fond = fond_de(ancien)
            part = part_encrée(ancien, fond)
            remplacant = preparer(neuf, fond, part)
            tampon = os.path.join(SORTIE, f"{langue}-logo-{xref}.png")
            cv2.imwrite(tampon, remplacant)
            page.replace_image(xref, filename=tampon)
            print(f"  {langue} xref {xref} : dessin à {part:.0%} du cadre, "
                  f"fond RVB {tuple(int(v) for v in fond[::-1])}")
        sortie = os.path.join(SORTIE, f"carte-{langue}.pdf")
        doc.save(sortie, garbage=4, deflate=True)
        print(f"{langue} → {sortie}")
