# Bim

Backlog personnel : une tâche à la fois, et dès qu'elle est finie, bim, la suivante.

- **Maintenant** : à l'heure d'un bloc fixe, seulement ce bloc et le bouton « J'y suis » (tenu dans les 15 minutes, sinon manqué). Hors bloc, un appel ou un entretien de mission d'abord, sinon la première des 3 tâches choisies le matin.
- **Backlog** : tâches sans horaire, par catégorie dans l'ordre de priorité (Mission, Contenu, Destiny, Personnel), plus un Parking qui n'apparaît jamais dans Maintenant. Ajout en une ligne.
- **Semaine** : les blocs fixes de la semaine (A ou B), les dates ponctuelles, les repères, et le compte blocs tenus / prévus. Un bloc ne se supprime pas : il se déplace dans la semaine pour un entretien.
- **Revue** : le dimanche, blocs tenus, tâches faites, et pour chaque tâche non touchée depuis 7 jours : garder, parking ou supprimer.

Les blocs, repères et dates ponctuelles se règlent dans `backlog.json` (clé `schedule`), pas dans l'appli.

Appli Flutter (web + Android). Les données vivent dans `backlog.json`, dans un dépôt GitHub privé séparé (`<compte>/bim-data`) ; l'appli y accède avec un jeton GitHub saisi dans l'écran Synchronisation (icône nuage).

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
