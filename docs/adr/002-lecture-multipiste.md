# ADR 002 — Lecture multipiste sur iOS

**Statut :** ⏳ en attente de mesure · **Spike :** [`ios/StemPlayerSpike`](../../ios/StemPlayerSpike)

## Contexte

Toute l'UX de l'éditeur (Phase 3) repose sur une hypothèse non vérifiée : qu'un iPhone
sait jouer quatre pistes séparées parfaitement synchronisées, pendant qu'on manipule
mute, solo et gain en cours de lecture, et qu'il sait ensuite en produire un mixdown
localement plus vite que le temps réel.

Si cette hypothèse est fausse, ce n'est pas un détail d'implémentation : c'est la forme
de l'éditeur qui change, et l'[ADR 000](000-stack-mobile.md) — qui a justifié le choix
de Swift natif précisément par `AVAudioEngine` — perd son argument principal. D'où la
place de ce spike en Phase 1, avant d'écrire l'éditeur, et non pendant.

## Seuils de décision

**Fixés avant la mesure**, pour ne pas les rationaliser après coup. `SpikeReport.verdict`
les applique automatiquement.

| Critère | Seuil | Conséquence si dépassé |
|---|---|---|
| Dérive entre pistes après 3 min | < 1 ms | `AVAudioEngine` seul ne suffit pas — étudier un rendu par graphe unique |
| Dérive après seek | 0 frame | Reprogrammer le seek autour d'un `AVAudioTime` commun explicite |
| Mémoire crête, mode flux disque | < 150 Mo | Limiter le nombre de pistes chargées, ou passer en lecture partielle |
| Mixdown hors-ligne | > 5× temps réel | Rebasculer l'export côté serveur, et réviser le modèle de coût du Lot 5 |

## Mesures

> À remplir en recopiant la sortie de `SpikeReport.formatted`. Les chiffres n'ont de sens
> que rapportés à un appareil : noter le modèle et la version d'iOS.

**Appareil :** _(à compléter — ex. iPhone 14, iOS 18.4)_

### Mode flux disque (`.file`)

```
(coller ici la sortie de testPlaybackInFileMode)
```

### Mode décodé en mémoire (`.buffer`)

```
(coller ici la sortie de testPlaybackInBufferMode)
```

### Mixdown hors-ligne

```
(coller ici la sortie de testOfflineMixdownIsFasterThanRealtime)
```

### Écoute

Les quatre pistes de test portent un clic simultané à chaque seconde pleine : toute
désynchronisation s'entend comme un flam. _(À compléter : flam perçu ou non, au casque.)_

## Décision

_(À compléter après la mesure.)_

## Conséquences

_(À compléter : ce que le résultat change pour l'éditeur de la Phase 3, pour l'export,
et pour le modèle de coût.)_

---

## Ce que le spike a déjà tranché en le construisant

Trois choix se sont imposés à l'écriture, indépendamment des chiffres à venir :

- **Le mute est un gain à zéro, jamais un `stop()`.** Arrêter un nœud le sort du cycle
  de rendu ; le relancer le ferait repartir désynchronisé. C'est le piège le plus
  évident de cette architecture, et il ne se voit pas sur un test statique.
- **Le gain passe par un `AVAudioUnitEQ`, pas par `AVAudioPlayerNode.volume`.** Ce
  dernier est borné à 0…1 et ne sait donc pas monter au-dessus de l'unité, alors que le
  schéma autorise jusqu'à +12 dB. `globalGain` couvre -96…+24 dB.
- **Les pistes sont lues en flux depuis le disque par défaut.** Un morceau stéréo de
  3 min en Float32 pèse ~63 Mo décodé ; quatre pistes en mémoire approchent les 250 Mo.
  Le mode `.buffer` reste implémenté, mais comme point de comparaison, pas comme cible.

Un contrôle a par ailleurs été ajouté au chargement : les quatre pistes doivent partager
fréquence d'échantillonnage et nombre de canaux. Un écart y serait une source de
désynchronisation silencieuse — il échoue désormais bruyamment.
