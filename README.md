# Bim

Backlog personnel : une tâche à la fois, et dès qu'elle est finie, bim, la suivante.

- **Maintenant** : une ligne d'agenda en haut (bloc en cours avec « J'y suis », ou prochain bloc), la tâche en cours en gros plan, puis le reste du sprint par priorité (P0 à P4).
- **Backlog** : sprints d'une semaine à créer et à remplir, puis le backlog hors sprint par catégorie (Mission, Contenu, Destiny, Personnel, Parking) ou par origine. Ajout en une ligne.
- **Agenda** : vues Jour, Semaine, Mois et Année, semaines avec et sans enfants en couleurs, blocs fixes, dates ponctuelles, compte blocs tenus / prévus. Un bloc ne se supprime pas : il se déplace dans la semaine pour un entretien.
- **Widget Android** : sur l'écran d'accueil, les tâches du sprint à gauche (4/6) et l'agenda du jour à droite (2/6). Il se met à jour quand l'appli s'ouvre ou change, et toutes les 30 minutes.
- **Revue** : le dimanche, blocs tenus, tâches faites, et pour chaque tâche non touchée depuis 7 jours : garder, parking ou supprimer.

Les blocs, repères et dates ponctuelles se règlent dans `backlog.json` (clé `schedule`), pas dans l'appli.

Appli Flutter (web + Android). Les données vivent dans `backlog.json`, dans un dépôt GitHub privé séparé (`<compte>/bim-data`) ; l'appli y accède avec un jeton GitHub saisi dans l'écran Synchronisation (icône nuage).

## Installer sur Android

Télécharge l'APK : https://github.com/okhamfriction-png/bim/releases/latest/download/bim.apk

## Commande `bin/bim`

Pour ajouter des tâches depuis un terminal ou une session Claude Code (passe par `gh`) :

```bash
bin/bim add "Valider le montage du vlog" -d Contenu --source "Montage vlog rue"
bin/bim add "Rappeler le recruteur" -d Mission --call
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

## Connecteur Claude (`mcp/`)

Serveur MCP distant (Streamable HTTP + OAuth) pour piloter Bim depuis claude.ai : voir
[mcp/README.md](mcp/README.md). Il écrit par `change` de `bin/bim`, comme la ligne de commande.
L'ancien `connecteur/` (Cloudflare Workers, clé dans l'adresse) est remplacé par celui-ci.
