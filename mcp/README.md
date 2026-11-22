# Connecteur Bim pour Claude (serveur MCP distant)

Un serveur MCP en Streamable HTTP, protégé par OAuth, que claude.ai ajoute comme connecteur
personnalisé. Claude lit et modifie Bim (tâches, sprints, résultats, échauffement) et peut
transmettre une consigne à l'agent de l'appli.

Construit avec le SDK Python officiel (`mcp` 2.3) en suivant
[la doc des connecteurs](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp),
[l'authentification des connecteurs](https://claude.com/docs/connectors/building/authentication)
et [Build an MCP server](https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server).

## Ce qu'il y a dans ce dossier

| Élément | Rôle |
|---|---|
| `passerelle/` | Cœur commun à toutes les applis : serveur, OAuth (enregistrement dynamique, PKCE S256, jetons tournants), écran de connexion, journal des appels |
| `apps/bim.py` | Les 14 outils de Bim. Écrit uniquement par `change` de `bin/bim` |
| `agent/` | Sur le Mac : exécute les consignes (`consignes.py`), installé par `installer.sh` |
| `Dockerfile`, `compose.yaml`, `.env.exemple` | Hébergement sur le NAS |

## Outils

Lecture (annotés lecture seule) : `bim_etat`, `bim_lister_sprints`, `bim_lister_taches`,
`bim_lire_tache`, `bim_progression_echauffement`, `bim_statut_consigne`.

Écriture (chacun renvoie l'état avant et après) : `bim_creer_tache`, `bim_modifier_tache`,
`bim_ajouter_sous_tache`, `bim_cocher_sous_tache`, `bim_saisir_resultat`, `bim_creer_sprint`,
`bim_modifier_sprint`, `bim_envoyer_consigne`.

Aucun outil ne supprime. Une tâche se termine ou s'archive avec `bim_modifier_tache`.

## Chemins servis

`/mcp` (les outils, jeton obligatoire), et ce qu'OAuth exige pour que Claude puisse se connecter :
`/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-authorization-server`,
`/register`, `/authorize`, `/token`, `/revoke`, `/connexion` (l'écran du mot de passe).
Tout autre chemin répond 404.

## Mise en ligne sur le Mac mini (choix retenu)

1. `./installer-mac.sh https://<hôte>` installe le service (il écoute sur `127.0.0.1:8793`, démarre
   avec la session et redémarre s'il tombe). Sans adresse, il reste en local.
2. Mot de passe de l'écran de connexion : `.venv/bin/python -m passerelle init`
3. Un tunnel rend `https://<hôte>` joignable sur le port 443 et pointe vers `http://127.0.0.1:8793`.
4. Le Mac doit rester allumé et la session ouverte. L'accès aux données passe par `gh`, déjà connecté.

## Mise en ligne sur le NAS (autre possibilité)

1. Copier le dépôt sur le NAS, puis dans `mcp/` : `cp .env.exemple .env` et remplir
   `URL_PUBLIQUE`, `BIM_TOKEN` (jeton GitHub limité à `bim-data`, Contents en lecture et écriture).
2. Choisir le mot de passe de l'écran de connexion (il n'est écrit nulle part en clair) :
   `docker compose run --rm bim-mcp python -m passerelle init`
3. Démarrer : `docker compose up -d --build`
4. Rendre `https://<hôte>` joignable sur le port 443, au choix :
   - **Tunnel Cloudflare** (aucun port ouvert sur la box) : créer un tunnel, mettre son jeton dans
     `TUNNEL_TOKEN`, y déclarer l'hôte public vers `http://bim-mcp:8793`, puis
     `docker compose --profile tunnel up -d`.
   - **Reverse proxy du NAS** : une règle `https://<hôte>:443` → `http://127.0.0.1:8793`, un
     certificat Let's Encrypt pour cet hôte, et la redirection du port 443 de la box vers le NAS.
5. Dans claude.ai : Personnaliser → Connecteurs → Ajouter → Ajouter un connecteur personnalisé,
   coller `https://<hôte>/mcp`, laisser l'authentification détectée (connexion OAuth,
   enregistrement automatique), puis « Connecter » et saisir le mot de passe.

## Journal

`donnees/journal-AAAA-MM.jsonl`, une ligne par appel : date, outil, arguments, client, issue.

## Consignes à l'agent

`bim_envoyer_consigne` dépose la consigne dans `consignes.json` du dépôt de données. Sur le Mac,
`agent/consignes.py` (lancé chaque minute une fois `agent/installer.sh` exécuté) la fait lire à
Claude Code en lecture seule : une question reçoit sa réponse ; tout changement devient un plan,
à l'état « à valider ». Rien n'est modifié tant que le plan n'est pas validé dans l'appli Bim
(bandeau jaune en haut). Après validation, la même conversation reprend et exécute le plan.

## Test local

```bash
uv venv .venv && uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m passerelle init
.venv/bin/python -m passerelle        # http://localhost:8793/mcp
```

## Brancher une autre appli

Un module `apps/<nom>.py` qui expose `NOM`, `INSTRUCTIONS`, `ERREURS` et `declare(serveur, journalise)`,
puis un service de plus dans `compose.yaml` (`APP=<nom>`, son port, son hôte, son dossier de données).
L'authentification, le journal et la marche à suivre côté Claude sont les mêmes.
