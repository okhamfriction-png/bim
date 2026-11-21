"""Démarre la passerelle d'une appli : `python -m passerelle [init|serve]`.

Variables : APP (module de apps/, « bim » par défaut), URL_PUBLIQUE (https://hôte, sans chemin),
DONNEES (dossier de l'état, du journal et de la configuration), PORT (8793), ECOUTE (127.0.0.1).
Chemins servis : /mcp, /connexion et les chemins OAuth (/authorize, /token, /register,
/.well-known/oauth-*). Tout le reste répond 404.
"""
import getpass
import importlib
import json
import os
import sys
from urllib.parse import urlparse

import uvicorn
from mcp.server import MCPServer
from mcp.server.auth.settings import AuthSettings, ClientRegistrationOptions, RevocationOptions
from mcp.server.transport_security import TransportSecuritySettings

from .journal import journalise
from .oauth import Autorisation, hacher_mot_de_passe

DONNEES = os.environ.get("DONNEES", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "donnees"))


def init():
    """Choisit le mot de passe de l'écran de connexion (jamais affiché, jamais dans le dépôt)."""
    a = getpass.getpass("Mot de passe de la passerelle (12 caractères au moins) : ")
    if len(a) < 12 or a != getpass.getpass("Le même, une seconde fois : "):
        sys.exit("Trop court, ou les deux saisies diffèrent. Rien n'a été enregistré.")
    os.makedirs(DONNEES, exist_ok=True)
    chemin = os.path.join(DONNEES, "config.json")
    with open(os.open(chemin, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
        json.dump({"motdepasse": hacher_mot_de_passe(a)}, f)
    print(f"Enregistré dans {chemin}.")


def application():
    app = importlib.import_module(f"apps.{os.environ.get('APP', 'bim')}")
    public = os.environ.get("URL_PUBLIQUE", f"http://localhost:{os.environ.get('PORT', '8793')}").rstrip("/")
    ressource = f"{public}/mcp"
    autorisation = Autorisation(DONNEES, public, ressource, app.NOM)
    serveur = MCPServer(
        app.NOM,
        instructions=app.INSTRUCTIONS,
        auth_server_provider=autorisation,
        auth=AuthSettings(
            issuer_url=public,
            resource_server_url=ressource,
            validate_token_resource=True,
            client_registration_options=ClientRegistrationOptions(enabled=True),
            revocation_options=RevocationOptions(enabled=True),
        ),
    )
    serveur.custom_route("/connexion", methods=["GET", "POST"])(autorisation.connexion)
    app.declare(serveur, journalise(DONNEES, app.ERREURS))
    hote = urlparse(public).netloc
    return serveur.streamable_http_app(
        streamable_http_path="/mcp",
        json_response=True,
        stateless_http=True,
        transport_security=TransportSecuritySettings(
            enable_dns_rebinding_protection=True,
            allowed_hosts=[hote, f"{hote}:*", "localhost:*", "127.0.0.1:*"],
            allowed_origins=[public, "https://claude.ai", "http://localhost:*", "http://127.0.0.1:*"],
        ),
    )


if __name__ == "__main__":
    if sys.argv[1:] == ["init"]:
        init()
    else:
        uvicorn.run(application(), host=os.environ.get("ECOUTE", "127.0.0.1"),
                    port=int(os.environ.get("PORT", "8793")), proxy_headers=True, forwarded_allow_ips="*",
                    log_level="warning")
