# Spike n°1 — lecture de 4 stems synchronisés

**Prototype jetable.** Il ne deviendra pas le lecteur de production : son rôle est de
produire des mesures sur iPhone physique **avant** qu'on construise l'éditeur de la
Phase 3 autour d'hypothèses non vérifiées.

La question à trancher : l'UX prévue pour l'éditeur — quatre pistes qui jouent
ensemble, mute/solo/gain manipulés en cours de lecture, seek, puis export rendu sur
l'appareil — tient-elle sur un vrai téléphone ? Si la réponse est non, c'est toute la
Phase 3 qui change de forme, et il vaut mieux l'apprendre maintenant.

## Lancer les mesures

```
Xcode → File ▸ Open… → ios/StemPlayerSpike/Package.swift
Sélectionner votre iPhone comme destination (pas un simulateur)
⌘U
```

> ⚠️ **Le simulateur ne compte pas.** Il partage l'horloge audio du Mac et dispose de
> sa mémoire : les deux chiffres qui nous intéressent y sont faux. Une mesure faite au
> simulateur n'a aucune valeur pour cette décision.

Passe courte par défaut (30 s). Pour la mesure longue, celle qui alimente l'ADR :

```
MELODIX_SPIKE_DURATION=180 ⌘U
```

(Product ▸ Scheme ▸ Edit Scheme… ▸ Test ▸ Arguments ▸ Environment Variables.)

Aucun fichier audio n'est nécessaire : le harnais génère quatre pistes de test. Chacune
porte un timbre distinct **et le même clic bref à chaque seconde pleine**. Les clics
étant simultanés par construction, la moindre désynchronisation s'entend comme un flam —
la mesure est chiffrée, mais l'oreille reste le juge d'appel. Branchez un casque et
écoutez pendant que la passe tourne.

## Ce qui est mesuré, et pourquoi

| Mesure | Ce qu'elle décide |
|---|---|
| **Dérive entre pistes** | Les quatre nœuds partagent une horloge de rendu : le résultat attendu est **zéro**. Une valeur non nulle invaliderait l'hypothèse sur laquelle repose tout l'éditeur. |
| **Dérive après seek** | Le seek est le seul moment où la synchronisation est reconstruite. C'est là qu'une implémentation naïve se trahit. |
| **Mémoire, flux disque vs décodé** | Un morceau stéréo de 3 min en Float32 pèse ~63 Mo. Quatre pistes décodées = ~250 Mo, de quoi se faire tuer par le système. Le mode fichier est le défaut ; ce spike chiffre l'écart. |
| **Mixdown hors-ligne** | Vérifie l'affirmation de l'[ADR 000](../../docs/adr/000-stack-mobile.md) : l'export peut être rendu sur l'appareil, plus vite que le temps réel, donc à coût cloud nul. Un facteur proche de 1× fait tomber l'argument et renvoie l'export côté serveur, avec la facture. |

Le mixage est manipulé **pendant** la lecture (mute, solo, gain), parce que c'est le
geste réel de l'éditeur — et parce qu'une implémentation qui muterait par `stop()` au
lieu d'un gain à zéro passerait un test statique et casserait ici.

## Seuils de décision

Fixés **avant** de voir les résultats, pour ne pas les rationaliser après coup :

| Critère | Seuil | Si dépassé |
|---|---|---|
| Dérive après 3 min | < 1 ms | L'éditeur ne peut pas reposer sur `AVAudioEngine` seul — étudier un rendu par graphe unique |
| Dérive après seek | 0 frame | Reprogrammer le seek autour d'un `AVAudioTime` commun explicite |
| Mémoire crête, mode fichier | < 150 Mo | Limiter le nombre de pistes chargées simultanément, ou passer en lecture partielle |
| Mixdown hors-ligne | > 5× temps réel | Rebasculer l'export côté serveur et réviser le modèle de coût du Lot 5 |

`SpikeReport.verdict` applique ces seuils et affiche `PASSE` ou `ÉCHEC` avec le détail.

## Après la passe

1. Recopier la sortie de `SpikeReport.formatted` dans
   [`docs/adr/002-lecture-multipiste.md`](../../docs/adr/002-lecture-multipiste.md).
2. Noter le modèle d'iPhone et la version d'iOS : ces chiffres n'ont de sens que
   rapportés à un appareil.
3. Trancher, puis **jeter ce paquet**. Le lecteur de production sera réécrit avec ce
   qu'on aura appris ici ; garder le prototype ne ferait que faire vivre du code que
   personne n'a conçu pour durer.

## Ce qui n'est pas couvert

Interruptions (appel entrant), changements de route (débranchement du casque), lecture
en arrière-plan, waveforms. Tout cela compte pour le produit, mais aucun de ces points
n'invalide l'architecture de l'éditeur — ils relèvent de la Phase 3, pas d'un
dérisquage de Phase 1.
