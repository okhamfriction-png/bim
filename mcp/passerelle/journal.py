"""Journal des appels : une ligne JSON par appel d'outil (date, outil, arguments, issue)."""
import datetime
import functools
import json
import os
import threading

import anyio
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.mcpserver.exceptions import ToolError

_lock = threading.Lock()


def _write(dossier, ligne):
    os.makedirs(dossier, exist_ok=True)
    nom = os.path.join(dossier, f"journal-{ligne['date'][:7]}.jsonl")
    with _lock, open(nom, "a", encoding="utf-8") as f:
        f.write(json.dumps(ligne, ensure_ascii=False) + "\n")


def journalise(dossier, erreurs=()):
    """Décorateur d'outil : exécute la fonction hors de la boucle, note l'appel, traduit les erreurs.

    `erreurs` : les exceptions « attendues » (saisie refusée, lecture impossible), renvoyées
    telles quelles à Claude comme erreur d'outil.
    """

    def deco(fn):
        @functools.wraps(fn)
        async def outil(**kwargs):
            jeton = get_access_token()
            ligne = {
                "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "outil": fn.__name__,
                "arguments": {k: v for k, v in kwargs.items() if v is not None},
                "client": jeton.client_id if jeton else None,
            }
            try:
                resultat = await anyio.to_thread.run_sync(functools.partial(fn, **kwargs))
                ligne["issue"] = "ok"
                return resultat
            except (ValueError, *erreurs) as e:
                ligne["issue"] = f"refus : {e}"
                raise ToolError(str(e)) from e
            except Exception as e:
                ligne["issue"] = f"erreur : {type(e).__name__} : {e}"
                raise
            finally:
                _write(dossier, ligne)

        return outil

    return deco
