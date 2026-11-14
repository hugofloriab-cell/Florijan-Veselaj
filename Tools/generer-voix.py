#!/usr/bin/env python3
"""Génère le paquet de voix de HACCP Pocket avec Voicebox.

À lancer sur le Mac, Voicebox ouvert, depuis ~/Developer/HACCPPocket/ :

    python3 Tools/generer-voix.py "My Voice"          # tout le paquet
    python3 Tools/generer-voix.py "My Voice" --une    # une seule phrase, pour essayer

Tout passe par l'API locale de Voicebox (127.0.0.1:17493) et par
`afconvert`, livré avec macOS. Rien n'est installé.
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


def appel(chemin, charge=None, methode="GET", brut=False):
    requete = urllib.request.Request(
        API + chemin,
        data=json.dumps(charge).encode() if charge is not None else None,
        headers={"Content-Type": "application/json"},
        method=methode,
    )
    try:
        with urllib.request.urlopen(requete, timeout=900) as reponse:
            contenu = reponse.read()
            return contenu if brut else json.loads(contenu)
    except urllib.error.HTTPError as erreur:
        # Sans le corps de la réponse, un 400 ne dit rien. Avec, il dit tout.
        detail = erreur.read().decode("utf-8", "replace")[:300]
        raise RuntimeError("HTTP %s — %s" % (erreur.code, detail)) from None


# ───────────────────────────── les phrases ─────────────────────────────

def phrases_du_code(fichier):
    """Les phrases fixes dites par l'assistant.

    Trois filtres, et chacun a sa raison :

    - les blocs `\"\"\"` sont retirés d'abord, sinon l'expression régulière
      traverse les instructions du modèle et ramène du code Swift ;
    - une phrase ne tient que sur une ligne ;
    - tout ce qui porte un caractère de programmation — accolade,
      parenthèse, signe égal — n'est pas du français.
    """
    code = open(fichier, encoding="utf-8").read()
    code = re.sub(r'"""[\s\S]*?"""', " ", code)

    interdits = set('{}()[]<>=;_@\\/|&*+#$')
    trouvees = []

    for m in re.finditer(r'"([^"\n]{12,200})"', code):
        texte = m.group(1).strip()
        if any(c in interdits for c in texte):
            continue
        if not re.match(r"^[A-Za-zÀ-ÿ«]", texte):
            continue
        # Les noms de symboles SF — « thermometer.medium » — passent tous
        # les filtres précédents. Aucune phrase dite ne tient en un mot.
        if " " not in texte:
            continue
        mots = [w for w in re.split(r"[^A-Za-zÀ-ÿ']+", texte) if len(w) > 1]
        if len(mots) < 3:
            continue
        if texte not in trouvees:
            trouvees.append(texte)

    return trouvees


# ───────────────────────────── Voicebox ─────────────────────────────

def profil():
    profils = appel("/profiles")
    if isinstance(profils, dict):
        profils = profils.get("profiles", [])
    if not profils:
        sys.exit("Aucun profil de voix dans Voicebox.")

    voulu = None
    for argument in sys.argv[1:]:
        if not argument.startswith("--"):
            voulu = argument.lower()
            break

    for p in profils:
        if voulu and voulu in (p.get("name") or "").lower():
            return p
    if voulu:
        sys.exit("Profil « %s » introuvable. Disponibles : %s"
                 % (voulu, ", ".join(p.get("name", "?") for p in profils)))
    return profils[0]


def genere(texte, voix):
    """Rend les octets WAV de la phrase."""
    demande = {"text": texte, "profile_id": voix["id"], "language": "fr"}

    # Le moteur est repris du profil plutôt que laissé au serveur : c'est
    # ce désaccord qui faisait échouer toutes les demandes en 400.
    moteur = voix.get("default_engine") or voix.get("preset_engine")
    if moteur:
        demande["engine"] = moteur

    generation = appel("/generate", demande, "POST")
    identifiant = generation.get("id")
    if not identifiant:
        raise RuntimeError("réponse sans identifiant : %s" % str(generation)[:160])

    # On réclame le fichier jusqu'à ce qu'il existe. Plus simple et plus
    # sûr que de suivre un flux d'états.
    for _ in range(600):
        try:
            octets = appel("/history/%s/export-audio?format=wav" % identifiant, brut=True)
            if octets and len(octets) > 1000:
                return octets
        except RuntimeError:
            pass
        time.sleep(1)

    raise RuntimeError("délai dépassé")


# ───────────────────────────── le paquet ─────────────────────────────

def main():
    if not os.path.exists(SOURCE):
        sys.exit("Lancez ce script depuis ~/Developer/HACCPPocket/ (%s introuvable)." % SOURCE)

    voix = profil()
    print("Voix   :", voix.get("name"), "·", voix.get("id"))
    print("Moteur :", voix.get("default_engine") or voix.get("preset_engine") or "(défaut du serveur)")

    textes = phrases_du_code(SOURCE)
    if "--une" in sys.argv:
        textes = textes[:1]
    print("Phrases:", len(textes))
    print()

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    manifeste = {"version": int(time.time()), "voix": voix.get("name"), "phrases": []}
    echecs = 0

    for index, texte in enumerate(textes, 1):
        print("  [%2d/%d] %s" % (index, len(textes), texte[:60]))
        try:
            wav = genere(texte, voix)
        except Exception as erreur:                       # noqa: BLE001
            print("          échec :", erreur)
            echecs += 1
            if index == 1:
                sys.exit("\nLa première phrase échoue : inutile de continuer.")
            continue

        empreinte = hashlib.sha256(texte.encode("utf-8")).hexdigest()
        brut = os.path.join(OUT, empreinte + ".wav")
        cible = os.path.join(OUT, empreinte + ".m4a")
        with open(brut, "wb") as f:
            f.write(wav)
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", brut, cible],
            check=True, capture_output=True,
        )
        os.remove(brut)
        manifeste["phrases"].append({"texte": texte, "fichier": empreinte + ".m4a"})

    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifeste, f, ensure_ascii=False, indent=2)

    shutil.make_archive("VoicePack", "zip", OUT)
    poids = os.path.getsize("VoicePack.zip") / 1024 / 1024
    print("\nVoicePack.zip — %d phrases, %d échecs, %.1f Mo"
          % (len(manifeste["phrases"]), echecs, poids))
    print("Envoyez ce fichier dans la conversation.")


if __name__ == "__main__":
    main()
