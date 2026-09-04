# -*- coding: utf-8 -*-
"""Rend les pages du PDF du restaurant, telles quelles.

Aucune recomposition : chaque page est photographiée à haute définition.
La mise en page, les photos, les couleurs et les polices du document
d'origine sont conservées à l'identique. C'est la carte du restaurant,
pas une interprétation.

1800 px de large : lisible jusqu'au zoom d'un téléphone, pour un poids
qui reste supportable en 4G.
"""
import os
import sys

import cv2
import fitz
import numpy as np

ICI = os.path.dirname(os.path.abspath(__file__))
U = "/root/.claude/uploads/eb973e87-7c35-50ce-8874-e9267b19fddb/"
SOURCES = {
    "fr": U + "84455ab2-Carte_Les_Tilleuls_Automne_2026.pdf",
    "en": U + "200304f2-Les_Tilleuls_Autumn_Menu_2026_EN.pdf",
}
OUT = os.path.join(os.path.dirname(ICI), "assets", "menu")
LARGEUR = 1800
QUALITE = 82

langue = sys.argv[1] if len(sys.argv) > 1 else "fr"
doc = fitz.open(SOURCES[langue])
total = 0
for i, page in enumerate(doc, 1):
    zoom = LARGEUR / page.rect.width
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom))
    img = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, pix.n)
    img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR if pix.n == 3 else cv2.COLOR_RGBA2BGR)
    nom = os.path.join(OUT, f"carte-{langue}-{i}.webp")
    cv2.imwrite(nom, img, [cv2.IMWRITE_WEBP_QUALITY, QUALITE])
    total += os.path.getsize(nom)
    print(f"  carte-{langue}-{i}.webp  {pix.width}×{pix.height}  {os.path.getsize(nom)/1024:.0f} Ko")
print(f"{doc.page_count} pages · {total/1048576:.2f} Mo au total")
