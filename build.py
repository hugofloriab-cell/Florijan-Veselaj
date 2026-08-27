#!/usr/bin/env python3
"""Génère les deux versions dérivées à partir de la fiche source.

    python3 build.py

Source          : checklist-petit-dejeuner.html  (le fichier à copier sur une tablette)
Sorties         :
  docs/index.html                       version installable, publiée sur le web
  .artifact/checklist-petit-dejeuner.html  version publication en ligne
"""
import pathlib
import re

RACINE = pathlib.Path(__file__).parent
SOURCE = RACINE / "checklist-petit-dejeuner.html"

# Balises ajoutées à la seule version web : icône, couleur de barre système,
# et enregistrement du service worker qui rend la fiche utilisable hors connexion.
TETE_PWA = """<link rel="manifest" href="manifest.webmanifest">
<meta name="theme-color" content="#12336B">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Check-list PDJ">
<link rel="apple-touch-icon" href="icone-192.png">
<link rel="icon" href="icone-192.png">
"""

PIED_PWA = """<script>
/* Rend la fiche disponible hors connexion une fois installée. Sans effet
   lorsqu'elle est ouverte depuis un fichier local. */
if (window.isSecureContext && "serviceWorker" in navigator) {
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("sw.js").catch(function () {});
  });
}
</script>
"""


def corps(source: str) -> str:
    """Contenu situé entre les deux repères, sans l'enveloppe du document."""
    fragment = source.split("<!--ARTIFACT-START-->")[1].split("<!--ARTIFACT-END-->")[0]
    return "\n".join(
        l for l in fragment.split("\n") if l.strip() not in ("</head>", "<body>")
    ).strip()


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    # Version publication en ligne : fragment nu, l'hôte fournit l'enveloppe.
    cible = RACINE / ".artifact" / "checklist-petit-dejeuner.html"
    cible.parent.mkdir(exist_ok=True)
    cible.write_text(corps(source) + "\n", encoding="utf-8")

    # Version web installable : document complet enrichi des balises PWA.
    web = source.replace("<title>", TETE_PWA + "<title>", 1)
    web = web.replace("</body>", PIED_PWA + "</body>", 1)
    web = re.sub(r"<!--/?ARTIFACT-(START|END)-->\n?", "", web)
    (RACINE / "docs" / "index.html").write_text(web, encoding="utf-8")

    print("docs/index.html et .artifact/ régénérés depuis", SOURCE.name)


if __name__ == "__main__":
    main()
