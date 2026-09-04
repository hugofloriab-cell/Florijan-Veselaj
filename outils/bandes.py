# -*- coding: utf-8 -*-
"""Bande de lecture, page par page.

Quand le client touche « Agrandir », l'application ne zoome pas au hasard :
elle cadre la colonne de texte de la page. La maquette de la carte alterne
(photos à gauche page 2, à droite page 3, deux colonnes page 4) ; un cadrage
unique couperait un nom de plat sur deux. On lit donc les boîtes de texte du
PDF lui-même, ce qui suit la maquette du restaurant au lieu de la deviner.

Règle : la fenêtre est la boîte du texte de la page, bornée. Un nom de plat
et son prix doivent tenir ensemble à l'écran — un prix qu'on ne peut pas
rattacher à un plat ne sert à rien — donc on ne cadre jamais plus serré que
la ligne la plus large. Les pages à colonne étroite (les entrées, les plats)
y gagnent un fort agrandissement ; celles qui étalent leurs lignes d'un bord
à l'autre (les vins, les bières) en gagnent un plus modeste, mais gardent
leurs prix à l'écran.
"""
import json
import os

import pymupdf

U = "/root/.claude/uploads/eb973e87-7c35-50ce-8874-e9267b19fddb/"
SOURCES = {
    "fr": U + "84455ab2-Carte_Les_Tilleuls_Automne_2026.pdf",
    "en": U + "200304f2-Les_Tilleuls_Autumn_Menu_2026_EN.pdf",
}
MARGE = 14.0     # respiration de chaque côté, en points
PART_MIN = 0.50  # au plus 2x : au-delà, on ne lit plus qu'un mot à la fois
PART_MAX = 0.90  # en deçà de 1,1x, l'agrandissement ne vaudrait pas le geste

for langue, chemin in SOURCES.items():
    bandes = []
    for page in pymupdf.open(chemin):
        L = page.rect.width
        boites = [s["bbox"] for b in page.get_text("dict")["blocks"]
                  for l in b.get("lines", []) for s in l["spans"] if s["text"].strip()]
        if not boites:
            bandes.append({"part": PART_MAX, "centre": 0.5})
            continue
        x0 = max(0.0, min(b[0] for b in boites) - MARGE)
        x1 = min(L, max(b[2] for b in boites) + MARGE)
        part = min(PART_MAX, max(PART_MIN, (x1 - x0) / L))
        bandes.append({"part": round(part, 3), "centre": round((x0 + x1) / 2 / L, 3)})
    print('"%s": %s' % (langue, json.dumps(bandes)))
