"""Outils MCP de Bim.

Lecture : mêmes règles que l'appli (lib/store.dart, lib/models.dart, lib/defi.dart).
Écriture : uniquement par `change` de bin/bim, le chemin de la ligne de commande et le format
de l'appli. Aucun outil ne supprime : une tâche se clôt ou s'archive.
"""
import copy
import datetime
import importlib.machinery
import importlib.util
import os
import statistics
from typing import Literal
from zoneinfo import ZoneInfo

from mcp.types import ToolAnnotations

NOM = "Bim"
INSTRUCTIONS = (
    "Bim est l'organisation de Marouane : un backlog de tâches par catégorie et priorité, des sprints d'une "
    "semaine (lundi à dimanche, désignés par la date de leur lundi), des points de valeur avec une cible par "
    "sprint, trois tâches par jour au plus, et un échauffement d'impro noté en secondes tenues sans « euh ». "
    "Commence par bim_etat. Chaque outil d'écriture renvoie l'état avant et après : résume-le en une phrase. "
    "Rien ne se supprime : une tâche se termine ou s'archive avec bim_modifier_tache."
)

_chemin = os.environ.get("BIM_CLI") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin", "bim")
_spec = importlib.util.spec_from_loader("bim_cli", importlib.machinery.SourceFileLoader("bim_cli", _chemin))
bim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bim)
ERREURS = (bim.BimError,)

TZ = ZoneInfo(os.environ.get("BIM_TZ", "Europe/Paris"))
CATS = bim.DOMAINS
Categorie = Literal["Mission", "Contenu", "Destiny", "Personnel", "Parking"]
KINDS = {"rue": ("Rue", "blocs", 3), "paris": ("Vidéo Paris", "vidéos", 2), "montee": ("Vidéo montée", "vidéos", 2),
         "short": ("Short", "shorts", 1), "rangement": ("Rangement", "jours", 1),
         "echauffement": ("Échauffement", "sprints", 2)}
PREFIXES = {"rue ·": "rue", "vidéo paris": "paris", "vidéo montée": "montee", "short ·": "short",
            "rangement ·": "rangement", "échauffement ·": "echauffement"}
BLOC = {"approches": "approches", "arrets": "arrets", "abonnes_avant": "avant", "abonnes_apres": "apres",
        "demandes": "demandes", "oui": "oui", "objection": "objection", "changer": "changer",
        "secondes": "duree", "levier_joue": "levierOk"}
LECTURE = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)
ECRITURE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=False)


# ---- dates ----

def aujourdhui():
    return datetime.datetime.now(TZ).date()


def lundi_de(d):
    return d - datetime.timedelta(days=d.weekday())


def ce_lundi():
    return lundi_de(aujourdhui()).isoformat()


def ms(d):
    return int(datetime.datetime(d.year, d.month, d.day, tzinfo=TZ).timestamp() * 1000)


def jour_de(instant):
    return datetime.datetime.fromtimestamp(instant / 1000, TZ).date().isoformat() if instant else None


def un_lundi(texte):
    try:
        d = datetime.date.fromisoformat(texte)
    except (TypeError, ValueError):
        raise ValueError(f"« {texte} » n'est pas une date au format aaaa-mm-jj.") from None
    if d.weekday():
        raise ValueError(f"Un sprint commence un lundi ; {texte} n'en est pas un (lundi de cette semaine-là : {lundi_de(d)}).")
    return d


# ---- règles de l'appli ----

def cat(t):
    return bim.cat(t)


def kind_of(t):
    if t.get("kind") in KINDS:
        return t["kind"]
    s = t.get("title", "").lower()
    return next((k for p, k in PREFIXES.items() if s.startswith(p)), "")


def entiere(t):
    """Types payés une seule fois, quand toutes les sous-tâches sont cochées (l'échauffement)."""
    return kind_of(t) == "echauffement"


def subs(t):
    return t.get("subs") or []


def unites(t):
    if not subs(t) or entiere(t):
        return 1, (1 if t.get("status") == "done" else 0)
    return len(subs(t)), sum(1 for s in subs(t) if s.get("done"))


def coefs(doc):
    c = (doc.get("schedule", {}).get("points") or {}).get("coef") or {}
    return {k: c.get(k, v[2]) for k, v in KINDS.items()}


def coef_of(doc, t):
    k = kind_of(t)
    if not k:
        return 0
    if entiere(t) and t.get("sprint"):  # un seul échauffement payé par sprint : le plus ancien
        for o in doc["tasks"]:
            if (o is not t and not o.get("deleted") and o.get("sprint") == t["sprint"] and kind_of(o) == k
                    and (o.get("createdAt", 0), o["id"]) < (t.get("createdAt", 0), t["id"])):
                return 0
    return coefs(doc)[k]


def points(doc, t):
    total, faites = unites(t)
    c = coef_of(doc, t)
    return c * total, c * faites


def livraisons(t):
    if not subs(t) or entiere(t):
        return [t.get("doneAt") or t.get("updatedAt", 0)] if t.get("status") == "done" else []
    return [s.get("doneAt") or t.get("doneAt") or t.get("updatedAt", 0) for s in subs(t) if s.get("done")]


def valeur_entre(doc, debut, fin):
    return sum(coef_of(doc, t) * sum(1 for d in livraisons(t) if debut <= d < fin)
               for t in doc["tasks"] if not t.get("deleted") and kind_of(t))


def semaine(doc, lundi):
    s = doc.get("schedule", {})
    ancre = lundi_de(datetime.date.fromisoformat(s.get("anchor", "2026-01-05")))
    pair = round((lundi - ancre).days / 7) % 2 == 0
    return s.get("nameA", "Semaine A") if pair else s.get("nameB", "Semaine B")


def cible(doc, sprint):
    p = doc.get("schedule", {}).get("points") or {}
    if sprint in (p.get("targets") or {}):
        return p["targets"][sprint], True
    avec = "avec" in semaine(doc, datetime.date.fromisoformat(sprint)).lower()
    return (p.get("kids", 70) if avec else p.get("free", 90)), False


def ordre(t):
    return (t.get("priority", 2), CATS.index(cat(t)), t.get("rank", 0))


def statut(t):
    return "a_faire" if t.get("status") == "todo" else ("archivee" if t.get("archived") else "terminee")


# ---- vues renvoyées à Claude ----

def vue_sub(i, s):
    return {k: v for k, v in {
        "numero": i + 1, "titre": s.get("title", ""), "cochee": bool(s.get("done")),
        "cochee_le": jour_de(s.get("doneAt")), "resultat": s.get("result") or None,
        "donnees": s.get("data") or None}.items() if v is not None}


def vue(doc, t, detail=False):
    prevus, gagnes = points(doc, t)
    v = {"id": t["id"], "titre": t["title"], "categorie": cat(t), "priorite": f"P{t.get('priority', 2)}",
         "statut": statut(t), "sprint": t.get("sprint"), "jour_choisi": t.get("pickedOn")}
    if t.get("call"):
        v["appel_ou_entretien"] = True
    if kind_of(t):
        v["type"] = KINDS[kind_of(t)][0]
        v["points"] = {"prevus": prevus, "gagnes": gagnes}
    if subs(t):
        v["sous_taches_cochees"] = f"{sum(1 for s in subs(t) if s.get('done'))}/{len(subs(t))}"
    if detail:
        v.update({"description": t.get("note", ""), "liens": t.get("links") or [], "source": t.get("source", ""),
                  "resultat": t.get("result", ""), "metadonnees": t.get("meta") or {},
                  "sous_taches": [vue_sub(i, s) for i, s in enumerate(subs(t))],
                  "creee_le": jour_de(t.get("createdAt")), "modifiee_le": jour_de(t.get("updatedAt")),
                  "terminee_le": jour_de(t.get("doneAt"))})
    return v


def vue_sprint(doc, sprint):
    lundi = datetime.date.fromisoformat(sprint)
    c, fixee = cible(doc, sprint)
    dedans = [t for t in doc["tasks"] if not t.get("deleted") and t.get("sprint") == sprint]
    actuel = ce_lundi()
    return {"sprint": sprint, "du": sprint, "au": (lundi + datetime.timedelta(days=6)).isoformat(),
            "etat": "en_cours" if sprint == actuel else ("a_venir" if sprint > actuel else "passe"),
            "semaine": semaine(doc, lundi), "cible_points": c, "cible_fixee_a_la_main": fixee,
            "points_prevus": sum(points(doc, t)[0] for t in dedans),
            "points_faits": valeur_entre(doc, ms(lundi), ms(lundi + datetime.timedelta(days=7))),
            "taches_a_faire": sum(1 for t in dedans if t.get("status") == "todo"),
            "taches_terminees": sum(1 for t in dedans if t.get("status") == "done")}


def trouve(doc, ident):
    ident = (ident or "").strip().lower()
    vivantes = [t for t in doc.get("tasks", []) if not t.get("deleted")]
    exact = [t for t in vivantes if t["id"] == ident]
    hits = exact or ([t for t in vivantes if t["id"].startswith(ident)] if len(ident) >= 4 else [])
    if len(hits) != 1:
        raise ValueError(f"Aucune tâche avec l'identifiant « {ident} ». Cherche-la avec bim_lister_taches." if not hits
                         else f"Plusieurs tâches commencent par « {ident} » : donne l'identifiant entier.")
    return hits[0]


def trouve_sub(t, numero):
    if not 1 <= numero <= len(subs(t)):
        raise ValueError(f"Cette tâche a {len(subs(t))} sous-tâche(s) ; le numéro {numero} n'existe pas.")
    return subs(t)[numero - 1]


def regle(t):
    """Toutes cochées : la tâche est faite. Une case décochée : elle redevient à faire."""
    if not subs(t):
        return
    toutes = all(s.get("done") for s in subs(t))
    if toutes and t.get("status") != "done":
        t["doneAt"], t["status"] = bim.now_ms(), "done"
    elif not toutes and t.get("status") == "done":
        t["archived"], t["doneAt"], t["status"] = False, None, "todo"


def modifie(ident, fn, message):
    """Applique fn à une tâche par le chemin d'écriture de bin/bim ; renvoie l'état avant et après."""
    def op(doc):
        t = trouve(doc, ident)
        avant = vue(doc, t, True)
        fn(doc, t)
        t["updatedAt"] = bim.now_ms()
        return {"avant": avant, "apres": vue(doc, t, True)}
    return bim.change(op, f"bim (connecteur) : {message}")


# ---- progression de l'échauffement (lib/defi.dart) ----

def prises(doc):
    out = [(t, s) for t in doc["tasks"] if not t.get("deleted") and kind_of(t) == "echauffement"
           for s in subs(t) if ((s.get("data") or {}).get("duree") or 0) > 0]
    return sorted(out, key=lambda p: p[1].get("doneAt") or 0)


def declare(serveur, journalise):
    def lecture(fn):
        return serveur.tool(annotations=LECTURE)(journalise(fn))

    def ecriture(fn):
        return serveur.tool(annotations=ECRITURE)(journalise(fn))

    # ============ lecture ============

    @lecture
    def bim_etat() -> dict:
        """Où en est Marouane : sprint en cours, cible de points, points faits, tâches du jour, appels en attente."""
        doc = bim.read()
        jour = aujourdhui()
        sprint = ce_lundi()
        vivantes = [t for t in doc["tasks"] if not t.get("deleted")]
        choisies = sorted((t for t in vivantes if t.get("pickedOn") == jour.isoformat()), key=ordre)
        existe = sprint in (doc.get("schedule", {}).get("sprints") or [])
        return {
            "date": jour.isoformat(),
            "sprint_en_cours": vue_sprint(doc, sprint) if existe else None,
            **({} if existe else {"remarque": f"Aucun sprint n'est créé pour la semaine du {sprint}."}),
            "points_faits_aujourdhui": valeur_entre(doc, ms(jour), ms(jour + datetime.timedelta(days=1))),
            "taches_du_jour": [vue(doc, t) for t in choisies],
            "places_libres_aujourdhui": max(0, 3 - len(choisies)),
            "appels_et_entretiens": [vue(doc, t) for t in sorted(vivantes, key=ordre)
                                     if t.get("call") and t.get("status") == "todo" and cat(t) != "Parking"],
            "taches_ouvertes": sum(1 for t in vivantes if t.get("status") == "todo"),
        }

    @lecture
    def bim_lister_sprints(passes: bool = False) -> dict:
        """Liste les sprints (une semaine chacun, désignés par la date de leur lundi) avec cible, points prévus et faits.

        Args:
            passes: vrai pour inclure aussi les sprints déjà terminés.
        """
        doc = bim.read()
        actuel = ce_lundi()
        return {"sprints": [vue_sprint(doc, s) for s in sorted(set(doc.get("schedule", {}).get("sprints") or []))
                            if passes or s >= actuel]}

    @lecture
    def bim_lister_taches(sprint: str | None = None, categorie: Categorie | None = None,
                          priorite: int | None = None,
                          statut_tache: Literal["a_faire", "terminee", "archivee", "toutes"] = "a_faire",
                          recherche: str | None = None) -> dict:
        """Liste les tâches, triées par priorité puis catégorie. Sans filtre : tout ce qui reste à faire.

        Args:
            sprint: lundi du sprint (aaaa-mm-jj), « en_cours », ou « aucun » pour les tâches hors sprint.
            categorie: Mission, Contenu, Destiny, Personnel ou Parking.
            priorite: 0 (le plus urgent) à 4.
            statut_tache: a_faire (par défaut), terminee, archivee ou toutes.
            recherche: mots à trouver dans le titre.
        """
        doc = bim.read()
        if sprint == "en_cours":
            sprint = ce_lundi()
        out = []
        for t in sorted((t for t in doc["tasks"] if not t.get("deleted")), key=ordre):
            if statut_tache != "toutes" and statut(t) != statut_tache:
                continue
            if sprint is not None and (t.get("sprint") or "aucun") != sprint:
                continue
            if categorie and cat(t) != categorie:
                continue
            if priorite is not None and t.get("priority", 2) != priorite:
                continue
            if recherche and recherche.lower() not in t["title"].lower():
                continue
            out.append(vue(doc, t))
        return {"nombre": len(out), "taches": out}

    @lecture
    def bim_lire_tache(id: str) -> dict:
        """Détail complet d'une tâche : description, sous-tâches numérotées, résultats, métadonnées, liens.

        Args:
            id: identifiant de la tâche (donné par bim_lister_taches).
        """
        doc = bim.read()
        return vue(doc, trouve(doc, id), True)

    @lecture
    def bim_progression_echauffement() -> dict:
        """Échauffement d'impro : prises jour après jour, secondes tenues sans « euh », records, leviers par niveau.

        Les records visés recalés après chaque prise sont calculés par l'appli ; ici figurent les
        records visés enregistrés sur chaque tâche.
        """
        doc = bim.read()
        toutes = prises(doc)
        rang = {id(s): i + 1 for i, (_, s) in enumerate(toutes)}
        niveaux = []
        for t in sorted((t for t in doc["tasks"] if not t.get("deleted") and kind_of(t) == "echauffement"),
                        key=lambda t: ((t.get("meta") or {}).get("level", 99), t.get("sprint") or "")):
            m = t.get("meta") or {}
            notees = [s for s in subs(t) if id(s) in rang]
            secondes = [s["data"]["duree"] for s in notees]
            niveaux.append({
                "niveau": m.get("level"), "genre": m.get("genre"), "tache": t["id"], "titre": t["title"],
                "sprint": t.get("sprint"), "statut": statut(t), "record_vise_s": m.get("vise"),
                "leviers": m.get("leviers"), "levier_nouveau": m.get("nouveau"), "phase": m.get("phase"),
                "prises_cochees": f"{sum(1 for s in subs(t) if s.get('done'))}/{len(subs(t))}",
                "prises": [{"jour": rang[id(s)], "date": jour_de(s.get("doneAt")), "secondes": s["data"]["duree"],
                            "levier_joue": s["data"].get("levierOk") is True, "levier": s["data"].get("levier")}
                           for s in notees],
                "record_s": max(secondes) if secondes else None,
                "mediane_s": statistics.median(secondes) if secondes else None,
                "prises_reussies": sum(1 for s in notees if s["data"].get("levierOk") is True),
            })
        tout = [s["data"]["duree"] for _, s in toutes]
        return {"regle": "La prise s'arrête au premier « euh » ; le score est le nombre de secondes tenues. "
                         "Prise réussie : levier du jour joué avant le premier « euh ». 2 points à 6 prises sur 6.",
                "prises_notees": len(tout), "record_absolu_s": max(tout) if tout else None, "niveaux": niveaux}

    # ============ écriture ============

    @ecriture
    def bim_creer_tache(titre: str, categorie: Categorie, priorite: int = 2, description: str = "",
                        sprint: str | None = None, liens: list[str] | None = None,
                        appel_ou_entretien: bool = False, source: str = "Claude") -> dict:
        """Crée une tâche dans le backlog. Refuse un doublon (même titre qu'une tâche ouverte).

        Args:
            titre: court, à l'infinitif, sans horaire ni échéance.
            categorie: Mission, Contenu, Destiny, Personnel ou Parking.
            priorite: 0 (le plus urgent) à 4 ; 2 par défaut.
            description: texte affiché quand la tâche est dépliée.
            sprint: lundi du sprint où la ranger (aaaa-mm-jj) ; rien pour le backlog.
            liens: adresses utiles.
            appel_ou_entretien: vrai pour un appel ou un entretien de mission (passe devant tout).
            source: nom de la conversation d'où vient la tâche.
        """
        if not titre.strip():
            raise ValueError("Il manque le titre.")
        if not 0 <= priorite <= 4:
            raise ValueError("La priorité va de 0 à 4.")

        def op(doc):
            if sprint and sprint not in (doc.get("schedule", {}).get("sprints") or []):
                raise ValueError(f"Le sprint {sprint} n'existe pas. Crée-le d'abord avec bim_creer_sprint.")
            t = bim.new_task(doc, titre, categorie, priorite, note=description, links=liens, source=source,
                             call=appel_ou_entretien, sprint=sprint)
            if t is None:
                raise ValueError(f"Une tâche ouverte porte déjà ce titre : « {titre.strip()} ».")
            return {"avant": None, "apres": vue(doc, t, True)}
        return bim.change(op, f"bim (connecteur) : + {titre.strip()[:60]}")

    @ecriture
    def bim_modifier_tache(id: str, titre: str | None = None, description: str | None = None,
                           priorite: int | None = None, categorie: Categorie | None = None,
                           sprint: str | None = None, date: str | None = None,
                           statut_tache: Literal["a_faire", "terminee", "archivee"] | None = None) -> dict:
        """Modifie une tâche ; seuls les champs fournis changent. Sert aussi à la terminer ou à l'archiver.

        Args:
            id: identifiant de la tâche.
            titre: nouveau titre.
            description: nouvelle description (remplace l'ancienne en entier).
            priorite: 0 (le plus urgent) à 4.
            categorie: Mission, Contenu, Destiny, Personnel ou Parking (Parking la sort du sprint et du jour).
            sprint: lundi du sprint (aaaa-mm-jj), ou « aucun » pour la remettre au backlog.
            date: jour où la faire (aaaa-mm-jj ou « aujourdhui »), ou « aucune ». Trois tâches par jour au plus.
            statut_tache: a_faire (rouvrir), terminee (clore) ou archivee (clore et ranger aux archives).
        """
        def fn(doc, t):
            if titre is not None:
                if not titre.strip():
                    raise ValueError("Le titre ne peut pas être vide.")
                t["title"] = titre.strip()
            if description is not None:
                t["note"] = description
            if priorite is not None:
                if not 0 <= priorite <= 4:
                    raise ValueError("La priorité va de 0 à 4.")
                t["priority"] = priorite
            if categorie is not None:
                t["domain"] = categorie
                if categorie == "Parking":
                    t["sprint"], t["pickedOn"], t["call"] = None, None, False
                elif categorie != "Mission":
                    t["call"] = False
            if sprint is not None:
                if sprint in ("aucun", ""):
                    t["sprint"] = None
                else:
                    if sprint not in (doc.get("schedule", {}).get("sprints") or []):
                        raise ValueError(f"Le sprint {sprint} n'existe pas. Crée-le d'abord avec bim_creer_sprint.")
                    if cat(t) == "Parking":
                        raise ValueError("Une tâche au Parking ne va pas dans un sprint : change d'abord sa catégorie.")
                    t["sprint"] = sprint
            if date is not None:
                if date in ("aucune", ""):
                    t["pickedOn"] = None
                else:
                    jour = aujourdhui().isoformat() if date.replace("'", "") == "aujourdhui" else date
                    try:
                        datetime.date.fromisoformat(jour)
                    except ValueError:
                        raise ValueError(f"« {date} » n'est pas une date au format aaaa-mm-jj.") from None
                    if cat(t) == "Parking":
                        raise ValueError("Une tâche au Parking ne se choisit pas pour un jour.")
                    autres = [o for o in doc["tasks"] if o is not t and not o.get("deleted") and o.get("pickedOn") == jour]
                    if len(autres) >= 3:
                        raise ValueError(f"Trois tâches sont déjà choisies pour le {jour} : "
                                         + " ; ".join(o["title"] for o in autres))
                    t["pickedOn"] = jour
            if statut_tache == "a_faire":
                t["archived"], t["doneAt"], t["status"] = False, None, "todo"
            elif statut_tache in ("terminee", "archivee"):
                if t.get("status") != "done":
                    t["doneAt"], t["status"] = bim.now_ms(), "done"
                t["archived"] = statut_tache == "archivee"
        return modifie(id, fn, f"modifie {id}")

    @ecriture
    def bim_ajouter_sous_tache(id: str, titre: str, nombre: int = 1) -> dict:
        """Ajoute une ou plusieurs sous-tâches (cases à cocher) à une tâche.

        Args:
            id: identifiant de la tâche.
            titre: titre de la sous-tâche.
            nombre: pour en créer plusieurs d'un coup, numérotées « titre (1/3) », « titre (2/3) »…
        """
        if not titre.strip() or not 1 <= nombre <= 50:
            raise ValueError("Il faut un titre, et un nombre entre 1 et 50.")

        def fn(doc, t):
            s = titre.strip()
            t.setdefault("subs", []).extend(
                {"title": s if nombre == 1 else f"{s} ({i}/{nombre})", "done": False} for i in range(1, nombre + 1))
            regle(t)
        return modifie(id, fn, f"+ sous-tâche {id}")

    @ecriture
    def bim_cocher_sous_tache(id: str, numero: int, cochee: bool = True) -> dict:
        """Coche ou décoche une sous-tâche. Quand toutes sont cochées, la tâche est terminée.

        Args:
            id: identifiant de la tâche.
            numero: numéro de la sous-tâche, à partir de 1 (voir bim_lire_tache).
            cochee: faux pour décocher.
        """
        def fn(doc, t):
            s = trouve_sub(t, numero)
            s["done"] = cochee
            if cochee:
                s["doneAt"] = bim.now_ms()
            else:
                s.pop("doneAt", None)
            regle(t)
        return modifie(id, fn, f"coche {id} #{numero}")

    @ecriture
    def bim_saisir_resultat(id: str, sous_tache: int | None = None, texte: str | None = None,
                            approches: int | None = None, arrets: int | None = None,
                            abonnes_avant: int | None = None, abonnes_apres: int | None = None,
                            demandes: int | None = None, oui: int | None = None,
                            objection: str | None = None, changer: str | None = None,
                            secondes: int | None = None, levier_joue: bool | None = None) -> dict:
        """Remplit le résultat d'une tâche, d'un bloc de rue ou d'une prise d'échauffement. Seuls les champs fournis changent.

        Sans `sous_tache` : `texte` devient le résultat de la tâche. Avec `sous_tache` : bloc de rue
        (approches, arrets, abonnes_avant, abonnes_apres, demandes, oui, objection, changer) ou prise
        d'échauffement (secondes, levier_joue). Ne coche pas la case : utilise bim_cocher_sous_tache.

        Args:
            id: identifiant de la tâche.
            sous_tache: numéro de la sous-tâche (bloc de rue ou prise), à partir de 1.
            texte: résultat en clair.
            approches: approches faites dans le bloc (sur 20).
            arrets: personnes qui se sont arrêtées.
            abonnes_avant: abonnés de la page avant le bloc.
            abonnes_apres: abonnés de la page après le bloc.
            demandes: demandes de place faites.
            oui: nombre de oui.
            objection: objection la plus entendue.
            changer: une chose à changer au bloc suivant.
            secondes: prise d'échauffement, secondes tenues avant le premier « euh ».
            levier_joue: prise d'échauffement, le levier du jour a été joué avant le premier « euh ».
        """
        donnees = {BLOC[k]: v for k, v in locals().items() if k in BLOC and v is not None}
        if any(isinstance(v, int) and not isinstance(v, bool) and v < 0 for v in donnees.values()):
            raise ValueError("Les nombres ne peuvent pas être négatifs.")
        if sous_tache is None and donnees:
            raise ValueError("Les chiffres d'un bloc ou d'une prise se notent sur une sous-tâche : précise `sous_tache`.")
        if sous_tache is None and texte is None:
            raise ValueError("Rien à noter : donne `texte`, ou `sous_tache` avec ses chiffres.")

        def fn(doc, t):
            if sous_tache is None:
                t["result"] = texte.strip()
                return
            s = trouve_sub(t, sous_tache)
            if ("duree" in donnees or "levierOk" in donnees) != (kind_of(t) == "echauffement") and donnees:
                raise ValueError("`secondes` et `levier_joue` sont réservés aux prises d'échauffement ; "
                                 "les autres chiffres, aux blocs de rue.")
            if texte is not None:
                s["result"] = texte.strip()
            if donnees:
                s["data"] = {**(s.get("data") or {}), **donnees}
        return modifie(id, fn, f"résultat {id}" + (f" #{sous_tache}" if sous_tache else ""))

    def planning(fn, message):
        def op(doc):
            s = doc.setdefault("schedule", {})
            s.setdefault("sprints", [])
            resultat = fn(doc, s)
            s["updatedAt"] = bim.now_ms()
            return resultat
        return bim.change(op, f"bim (connecteur) : {message}")

    def fixe_cible(s, sprint, valeur):
        if not 0 <= valeur <= 500:
            raise ValueError("La cible va de 0 à 500 points.")
        p = s.setdefault("points", {})
        p.setdefault("targets", {})[sprint] = valeur

    @ecriture
    def bim_creer_sprint(lundi: str | None = None, cible_points: int | None = None) -> dict:
        """Crée un sprint d'une semaine (lundi à dimanche).

        Args:
            lundi: date du lundi (aaaa-mm-jj). Sans date : la première semaine sans sprint, à partir de celle-ci.
            cible_points: cible de points ; sans elle, la cible par défaut de la semaine (avec ou sans enfants).
        """
        def fn(doc, s):
            if lundi:
                d = un_lundi(lundi)
                if d.isoformat() < ce_lundi():
                    raise ValueError("Ce lundi est déjà passé.")
                if d.isoformat() in s["sprints"]:
                    raise ValueError(f"Le sprint du {lundi} existe déjà.")
            else:
                d = lundi_de(aujourdhui())
                while d.isoformat() in s["sprints"]:
                    d += datetime.timedelta(days=7)
            s["sprints"] = sorted({*s["sprints"], d.isoformat()})
            if cible_points is not None:
                fixe_cible(s, d.isoformat(), cible_points)
            return {"avant": None, "apres": vue_sprint(doc, d.isoformat())}
        return planning(fn, "+ sprint")

    @ecriture
    def bim_modifier_sprint(sprint: str, cible_points: int | None = None, nouveau_lundi: str | None = None) -> dict:
        """Change la cible de points d'un sprint, ou le déplace à une autre semaine avec ses tâches.

        Un sprint dure toujours du lundi au dimanche : changer ses dates, c'est changer de lundi.

        Args:
            sprint: lundi du sprint à modifier (aaaa-mm-jj), ou « en_cours ».
            cible_points: nouvelle cible de points (0 à 500).
            nouveau_lundi: lundi de la semaine où déplacer le sprint.
        """
        def fn(doc, s):
            cle = ce_lundi() if sprint == "en_cours" else un_lundi(sprint).isoformat()
            if cle not in s["sprints"]:
                raise ValueError(f"Le sprint {cle} n'existe pas.")
            avant = vue_sprint(doc, cle)
            if nouveau_lundi:
                vers = un_lundi(nouveau_lundi).isoformat()
                if vers in s["sprints"]:
                    raise ValueError(f"Un sprint existe déjà le {vers}.")
                if vers < ce_lundi():
                    raise ValueError("Ce lundi est déjà passé.")
                s["sprints"] = sorted({*(x for x in s["sprints"] if x != cle), vers})
                cibles = (s.get("points") or {}).get("targets") or {}
                if cle in cibles:
                    cibles[vers] = cibles.pop(cle)
                for t in doc["tasks"]:
                    if not t.get("deleted") and t.get("sprint") == cle:
                        t["sprint"], t["updatedAt"] = vers, bim.now_ms()
                cle = vers
            if cible_points is not None:
                fixe_cible(s, cle, cible_points)
            return {"avant": avant, "apres": vue_sprint(doc, cle)}
        return planning(fn, f"sprint {sprint}")

    # ============ consignes à l'agent de l'appli ============

    def vue_consigne(c):
        return {k: v for k, v in {
            "id": c["id"], "etat": c["etat"], "texte": c["texte"], "recue_le": c.get("recueLe"),
            "plan_a_valider": c.get("plan"), "compte_rendu": c.get("resume"), "changements": c.get("changements"),
            "terminee_le": c.get("finLe"), "erreur": c.get("erreur")}.items() if v}

    @ecriture
    def bim_envoyer_consigne(texte: str) -> dict:
        """Transmet une consigne en texte libre à l'agent de l'appli Bim (Claude Code sur le Mac de Marouane).

        L'agent la traite comme un message collé dans son chat. Il peut lire le code et ajouter ou
        terminer des tâches tout de suite ; tout changement de code, de format de données ou de
        publication attend que Marouane valide le plan dans l'appli. Renvoie un identifiant à
        suivre avec bim_statut_consigne. L'exécution prend de quelques minutes à plus d'une heure.

        Args:
            texte: la consigne, complète et autonome (l'agent ne voit pas cette conversation).
        """
        if len(texte.strip()) < 10:
            raise ValueError("La consigne est trop courte pour être comprise.")
        if len(texte) > 40000:
            raise ValueError("La consigne dépasse 40 000 caractères.")

        def op(doc):
            c = {"id": bim.new_id(), "texte": texte.strip(), "etat": "recue",
                 "recueLe": datetime.datetime.now(TZ).isoformat(timespec="seconds")}
            doc.setdefault("consignes", []).append(c)
            return {"avant": None, "apres": vue_consigne(c)}
        return bim.change(op, "bim (connecteur) : consigne reçue", "consignes.json")

    @lecture
    def bim_statut_consigne(id: str | None = None) -> dict:
        """Où en est une consigne envoyée à l'agent, et ce qu'elle a changé.

        États : recue (en file), en_cours, a_valider (un plan attend l'accord de Marouane dans
        l'appli), validee (accord donné, exécution à venir), terminee, refusee, echec.

        Args:
            id: identifiant renvoyé par bim_envoyer_consigne. Sans lui : les cinq dernières consignes.
        """
        toutes = bim.read("consignes.json").get("consignes", [])
        if id is None:
            return {"consignes": [vue_consigne(c) for c in toutes[-5:]]}
        for c in toutes:
            if c["id"] == id.strip():
                return vue_consigne(c)
        raise ValueError(f"Aucune consigne avec l'identifiant « {id} ».")
