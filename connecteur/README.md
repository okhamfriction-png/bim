# Connecteur Bim pour les conversations Claude

Petit serveur MCP hébergé sur Cloudflare Workers. Une fois ajouté comme connecteur personnalisé
dans claude.ai, les conversations (web, bureau, mobile) peuvent ajouter et lire les tâches du backlog.

- `ajouter_tache` : titre, catégorie, priorité P0 à P4, descriptif, liens, appel ou entretien, source.
- `lister_taches` : les tâches ouvertes, pour éviter les doublons.

## Mise en ligne

```bash
./deployer.sh
```

Le script demande la connexion à Cloudflare, puis le jeton GitHub (limité au dépôt de données,
droit Contents en lecture et écriture), et affiche l'adresse du connecteur. Cette adresse contient
une clé secrète : toute personne qui l'a peut lire et ajouter des tâches. La clé est gardée dans
`~/.bim-connecteur-cle`, jamais dans le dépôt.

## Test local

```bash
node test.mjs
```
