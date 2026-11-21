#!/usr/bin/env python3
"""Exécute sur le Mac les consignes reçues par le connecteur (consignes.json du dépôt de données).

Lancé chaque minute par launchd (agent/installer.sh). Une consigne à la fois, en deux temps :

1. Analyse, en lecture seule : l'agent (Claude Code, dans ~/Git/bim) lit le code et les données,
   sans aucun outil pour modifier quoi que ce soit. Il répond à la question posée, ou rend un plan.
   Un plan met la consigne à l'état « a_valider ».
2. Exécution, seulement après que Marouane a validé le plan dans l'appli (état « validee ») :
   la même conversation reprend, avec le droit de modifier et de publier ce que dit le plan.

États : recue → en_cours → terminee | a_valider → validee → en_cours → terminee ; refusee ; echec.
"""
import datetime
import fcntl
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
DEPOT = os.path.abspath(os.path.join(ICI, "..", ".."))
_spec = importlib.util.spec_from_loader("bim_cli", importlib.machinery.SourceFileLoader("bim_cli", os.path.join(DEPOT, "bin", "bim")))
bim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bim)

CLAUDE = os.environ.get("CLAUDE_BIN", os.path.expanduser("~/.local/bin/claude"))
FICHIER = "consignes.json"

ANALYSE = """Cette consigne arrive du connecteur Claude de Bim : Marouane l'a dictée dans une conversation \
claude.ai et elle t'est transmise telle quelle. Traite-la comme un message de lui dans ce projet.

Pour l'instant tu es en lecture seule : tu peux lire le code et les données (`bin/bim list` n'est pas \
disponible, lis les fichiers), mais tu n'as aucun outil pour modifier, lancer ou publier.

- Si la consigne est une question, ou ne demande aucun changement : réponds-y complètement, en texte brut sans Markdown, puis termine \
par une dernière ligne contenant exactement `VERDICT: REPONSE`.
- Si elle demande un changement (code, format des données, données, publication) : n'essaie rien. Rends le \
plan que tu exécuteras une fois validé, en français simple, pour quelqu'un qui le lira sur son téléphone : \
en texte brut sans Markdown (ni #, ni **, ni `), ce qui change pour lui, les fichiers touchés, si le format des données change, et si tu publies (web, APK, \
release) ou non. Termine par une dernière ligne contenant exactement `VERDICT: PLAN`.

CONSIGNE :
"""

EXECUTION = """Marouane vient de valider ce plan dans l'appli Bim. Exécute-le maintenant, et seulement lui : \
si un point demande d'en sortir, arrête-toi et dis-le. Vérifie ton travail comme d'habitude. Termine par un \
compte rendu court : ce qui est fait, ce qui est publié, ce qui n'est pas vérifié."""


def maintenant():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def maj(cid, **champs):
    def op(doc):
        for c in doc.get("consignes", []):
            if c["id"] == cid:
                c.update(champs)
                return dict(c)
    return bim.change(op, f"bim (agent) : consigne {cid} → {champs.get('etat', 'suite')}", FICHIER)


def claude(args, minutes):
    """Lance Claude Code sans écran ; renvoie (texte, identifiant de conversation, erreur)."""
    try:
        r = subprocess.run([CLAUDE, "-p", *args, "--output-format", "json"], cwd=DEPOT,
                           capture_output=True, text=True, timeout=minutes * 60)
    except subprocess.TimeoutExpired:
        return "", None, f"Arrêtée après {minutes} minutes."
    try:
        j = json.loads(r.stdout)
    except ValueError:
        return "", None, (r.stderr or r.stdout).strip()[-600:] or f"claude a rendu le code {r.returncode}"
    if j.get("is_error"):
        return "", j.get("session_id"), str(j.get("result"))[:600]
    return str(j.get("result") or "").strip(), j.get("session_id"), None


def git(*a):
    return subprocess.run(["git", "-C", DEPOT, *a], capture_output=True, text=True).stdout.strip()


def analyse(c):
    maj(c["id"], etat="en_cours", debutLe=maintenant())
    texte, session, erreur = claude(
        [ANALYSE + c["texte"], "--tools", "Read,Grep,Glob", "--permission-mode", "dontAsk"], 20)
    if erreur:
        return maj(c["id"], etat="echec", erreur=erreur, finLe=maintenant())
    lignes = texte.rstrip().splitlines()
    verdict = lignes[-1].strip().strip("`") if lignes else ""
    corps = "\n".join(lignes[:-1]).strip()
    if verdict == "VERDICT: REPONSE":
        return maj(c["id"], etat="terminee", resume=corps[:6000], changements=[], finLe=maintenant())
    # Tout ce qui n'est pas une simple réponse attend une validation, verdict lisible ou non.
    return maj(c["id"], etat="a_valider", plan=(corps or texte)[:6000], session=session)


def execute(c):
    tete, debut = git("rev-parse", "HEAD"), datetime.datetime.now(datetime.timezone.utc)
    maj(c["id"], etat="en_cours", debutLe=maintenant())
    reprise = ["--resume", c["session"]] if c.get("session") else []
    consigne = EXECUTION if reprise else f"{EXECUTION}\n\nCONSIGNE :\n{c['texte']}\n\nPLAN VALIDÉ :\n{c.get('plan', '')}"
    texte, _, erreur = claude([consigne, *reprise, "--permission-mode", "acceptEdits",
                               "--allowedTools", "Bash", "Edit", "Write", "Read", "Grep", "Glob"], 120)
    changements = [f"code : {l}" for l in git("log", "--oneline", f"{tete}..HEAD").splitlines()]
    changements += [f"non enregistré : {l.strip()}" for l in git("status", "--short").splitlines()[:20]]
    code, out, _ = bim.gh(f"repos/{bim.repo()}/commits?path=backlog.json&since={debut.strftime('%Y-%m-%dT%H:%M:%SZ')}")
    if code == 0:
        changements += [f"données : {x['commit']['message'].splitlines()[0]}" for x in json.loads(out)]
    if erreur:
        return maj(c["id"], etat="echec", erreur=erreur, changements=changements, finLe=maintenant())
    return maj(c["id"], etat="terminee", resume=texte[:6000], changements=changements, finLe=maintenant())


def main():
    verrou = open(os.path.join(os.environ.get("TMPDIR", "/tmp"), "bim-consignes.lock"), "w")
    try:
        fcntl.flock(verrou, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # une consigne est déjà en cours
    toutes = bim.read(FICHIER).get("consignes", [])
    for c in toutes:  # le verrou est libre : une consigne « en_cours » est restée en plan
        if c["etat"] == "en_cours":
            maj(c["id"], etat="echec", erreur="Interrompue (Mac éteint ou agent arrêté).", finLe=maintenant())
    suivante = next((c for c in toutes if c["etat"] == "validee"), None) or \
        next((c for c in toutes if c["etat"] == "recue"), None)
    if suivante:
        fin = (execute if suivante["etat"] == "validee" else analyse)(suivante)
        print(maintenant(), suivante["id"], "→", fin and fin.get("etat"))


if __name__ == "__main__":
    try:
        main()
    except bim.BimError as e:
        sys.exit(f"{maintenant()} {e}")
