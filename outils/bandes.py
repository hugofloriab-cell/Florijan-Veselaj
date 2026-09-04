# -*- coding: utf-8 -*-
"""Bande de lecture, page par page.

Quand le client touche « Agrandir », l'application ne zoome pas au hasard :
elle cadre la colonne de texte de la page. La maquette de la carte alterne
(photos à gauche page 2, à droite page 3, deux colonnes page 4) ; un cadrage
unique couperait un nom de plat sur deux. On lit donc les boîtes de texte du
PDF lui-même, ce qui suit la maquette du restaurant au lieu de la deviner.

Règle : la fenêtre est la boîte du texte, plafonnée à PART_MAX de la largeur
de page — au-delà, on la cale à gauche, là où commence la lecture, et le
client fait glisser pour la fin de la ligne.
"""
import json
import pymupdf

U = "/root/.claude/uploads/eb973e87-7c35-50ce-8874-e9267b19fddb/"
SOURCES = {
    "fr": U + "3cae6e3c-Carte_Les_Tilleuls_Automne_2026.pdf",
    "en": U + "561411c6-Les_Tilleuls_Autumn_Menu_2026_EN.pdf",
}
MARGE = 14.0     # respiration de chaque côté, en points
PART_MAX = 0.62  # au moins 1,6x d'agrandissement : les prix passent à 11 px

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
        part = (x1 - x0) / L
        if part <= PART_MAX:
            bandes.append({"part": round(part, 3), "centre": round((x0 + x1) / 2 / L, 3)})
        else:
            bandes.append({"part": PART_MAX, "centre": round((x0 / L) + PART_MAX / 2, 3)})
    print('"%s": %s' % (langue, json.dumps(bandes)))
