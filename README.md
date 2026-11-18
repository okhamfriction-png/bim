# Bim

Backlog personnel : une tâche à la fois, et dès qu'elle est finie, bim, la suivante.

- **Maintenant** : la tâche la plus prioritaire, en grand. Terminé, Démarrer, Plus tard.
- **Backlog** : toutes les tâches, triées par priorité (échéance arrivée, urgent, important, quand je peux). Glisser pour réordonner.
- **Semaine** : seulement les rendez-vous fixes et les créneaux backlog, sur deux semaines alternées.

Appli Flutter (web + Android). Les données vivent dans `backlog.json`, dans un dépôt GitHub privé séparé (`<compte>/bim-data`) ; l'appli y accède avec un jeton GitHub saisi dans l'écran Synchronisation (icône nuage).

## Commande `bin/bim`

Pour ajouter des tâches depuis un terminal ou une session Claude Code (passe par `gh`) :

```bash
bin/bim add "Valider le montage du vlog" -p 1 -d Contenu --source "Montage vlog rue"
bin/bim add "Tourner le script du jour" -d Contenu --note-file script.md
bin/bim add "Valider ce short" -d Contenu --file ~/Movies/short.mp4   # envoyé dans bim-data/media, 95 Mo max
bin/bim list
bin/bim done "valider le montage"
bin/bim rm "valider ce short"
```

## Construire

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build apk --release
flutter build web --release --base-href /bim/
```
