#!/usr/bin/env python3
"""Génère le paquet de voix de HACCP Pocket avec Voicebox.

À lancer sur le Mac, Voicebox ouvert, depuis ~/Developer/HACCPPocket/ :

    python3 Tools/generer-voix.py

Le script lit les phrases fixes directement dans le code de l'assistant,
les fait dire par Voicebox en français, les convertit en AAC avec
l'outil `afconvert` fourni par macOS, et produit VoicePack.zip.

Rien n'est installé : tout passe par l'API locale de Voicebox
(127.0.0.1:17493) et par des outils déjà présents sur un Mac.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "http://127.0.0.1:17493"
SOURCE = "HACCPPocket/Services/AssistantConversation.swift"
OUT = "VoicePack"


def appel(chemin, charge=None, methode="GET"):
    requete = urllib.request.Request(
        API + chemin,
        data=json.dumps(charge).encode() if charge else None,
        headers={"Content-Type": "application/json"},
        method=methode,
    )
    with urllib.request.urlopen(requete, timeout=600) as reponse:
        return json.loads(reponse.read())


def phrases_du_code(fichier):
    """Les phrases fixes dites par l'assistant.

    On écarte celles qui contiennent une interpolation Swift : un nom de
    produit ou un chiffre ne peut pas être pré-généré.
    """
    code = open(fichier, encoding="utf-8").read()
    trouvees = []
    for m in re.finditer(r'"((?:[^"\\]|\\.){12,200})"', code):
        texte = m.group(1)
        if "\\(" in texte:
            continue
        if not re.search(r"[a-zéèêàçù] [a-zéèêàçù]", texte):
            continue
        if texte.startswith(("http", "haccp.", "com.apple")):
            continue
        propre = texte.replace('\\"', '"').strip()
        if propre not in trouvees:
            trouvees.append(propre)
    return trouvees


def profil():
    profils = appel("/profiles")
    if isinstance(profils, dict):
        profils = profils.get("profiles", [])
    if not profils:
        sys.exit("Aucun profil de voix dans Voicebox. Créez-en un dans l'app.")

    voulu = sys.argv[1].lower() if len(sys.argv) > 1 else None
    for p in profils:
        if voulu and voulu in (p.get("name") or "").lower():
            return p
    if voulu:
        noms = ", ".join(p.get("name", "?") for p in profils)
        sys.exit("Profil « %s » introuvable. Disponibles : %s" % (sys.argv[1], noms))
    return profils[0]


def genere(texte, profil_id):
    gen = appel("/generate", {"text": texte, "profile_id": profil_id, "language": "fr"}, "POST")
    identifiant = gen.get("id")

    for _ in range(600):                      # dix minutes au plus par phrase
        if gen.get("audio_path") and gen.get("status") in (None, "completed"):
            return gen["audio_path"]
        if gen.get("status") == "failed":
            raise RuntimeError(gen.get("error") or "échec de génération")
        time.sleep(1)
        gen = appel("/generate/%s/status" % identifiant)
    raise RuntimeError("délai dépassé")


def main():
    if not os.path.exists(SOURCE):
        sys.exit("Lancez ce script depuis ~/Developer/HACCPPocket/ (fichier %s introuvable)." % SOURCE)

    voix = profil()
    print("Voix :", voix.get("name"), "·", voix.get("id"))

    textes = phrases_du_code(SOURCE)
    print("Phrases à générer :", len(textes))

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)

    manifeste = {"version": int(time.time()), "voix": voix.get("name"), "phrases": []}

    for index, texte in enumerate(textes, 1):
        empreinte = hashlib.sha256(texte.encode("utf-8")).hexdigest()
        cible = os.path.join(OUT, empreinte + ".m4a")
        print("  [%2d/%d] %s" % (index, len(textes), texte[:58]))

        try:
            source = genere(texte, voix["id"])
        except Exception as erreur:                       # noqa: BLE001
            print("        échec :", erreur)
            continue

        # afconvert est livré avec macOS : rien à installer.
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", source, cible],
            check=True, capture_output=True,
        )
        manifeste["phrases"].append({"texte": texte, "fichier": empreinte + ".m4a"})

    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifeste, f, ensure_ascii=False, indent=2)

    shutil.make_archive("VoicePack", "zip", OUT)
    poids = os.path.getsize("VoicePack.zip") / 1024 / 1024
    print("\nVoicePack.zip — %d phrases, %.1f Mo" % (len(manifeste["phrases"]), poids))
    print("Envoyez ce fichier dans la conversation.")


if __name__ == "__main__":
    main()
