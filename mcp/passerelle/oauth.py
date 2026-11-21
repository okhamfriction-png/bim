"""Serveur d'autorisation OAuth 2.1 de la passerelle, pour un seul utilisateur.

Ce que demande le client MCP de Claude (doc « Authentication for connectors ») :
enregistrement dynamique du client (DCR), PKCE S256, adresse de retour
https://claude.ai/api/mcp/auth_callback, jetons de rafraîchissement tournants,
erreur `invalid_grant` quand un jeton n'est plus valable.

L'écran de connexion demande le mot de passe de la passerelle : sans lui, aucun jeton n'est
émis, même si n'importe qui peut enregistrer un client. Les jetons sont gardés sous forme
d'empreinte (SHA-256) dans etat.json ; le mot de passe sous forme PBKDF2 dans config.json.
"""
import base64
import hashlib
import hmac
import html
import json
import os
import secrets
import threading
import time
from urllib.parse import urlparse

from mcp.server.auth.provider import (
    AccessToken,
    AuthorizationCode,
    AuthorizationParams,
    AuthorizeError,
    RefreshToken,
    RegistrationError,
    construct_redirect_uri,
)
from mcp.shared.auth import OAuthClientInformationFull, OAuthToken
from starlette.requests import Request
from starlette.responses import HTMLResponse, RedirectResponse

RETOUR_CLAUDE = "https://claude.ai/api/mcp/auth_callback"
ACCES = 3600  # durée d'un jeton d'accès, en secondes
RAFRAICHISSEMENT = 90 * 86400
ITER = 200_000


def empreinte(jeton):
    return hashlib.sha256(jeton.encode()).hexdigest()


def hacher_mot_de_passe(mdp, sel=None):
    sel = sel or secrets.token_bytes(16)
    h = hashlib.pbkdf2_hmac("sha256", mdp.encode(), sel, ITER)
    return {"sel": base64.b64encode(sel).decode(), "hash": base64.b64encode(h).decode(), "iter": ITER}


def retour_permis(uri):
    """L'adresse de retour de Claude, ou une adresse locale (Claude Code, tests)."""
    u = urlparse(str(uri))
    return str(uri) == RETOUR_CLAUDE or (u.scheme == "http" and u.hostname in ("localhost", "127.0.0.1"))


class Autorisation:
    def __init__(self, dossier, emetteur, ressource, nom):
        self.dossier, self.emetteur, self.ressource, self.nom = dossier, emetteur.rstrip("/"), ressource, nom
        self._verrou = threading.Lock()
        self._codes = {}  # code → AuthorizationCode
        self._demandes = {}  # demande en attente de mot de passe → (client, params, échéance)
        self._echecs = []  # instants des mots de passe refusés
        self._fichier = os.path.join(dossier, "etat.json")
        try:
            with open(self._fichier, encoding="utf-8") as f:
                self._etat = json.load(f)
        except FileNotFoundError:
            self._etat = {"clients": {}, "acces": {}, "rafraichissement": {}}

    # ---- état sur disque ----

    def _enregistre(self):
        now = time.time()
        for k in ("acces", "rafraichissement"):
            self._etat[k] = {h: v for h, v in self._etat[k].items() if v["expires_at"] > now}
        os.makedirs(self.dossier, exist_ok=True)
        tmp = self._fichier + ".tmp"
        with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
            json.dump(self._etat, f, ensure_ascii=False)
        os.replace(tmp, self._fichier)

    def _mot_de_passe_ok(self, mdp):
        try:
            with open(os.path.join(self.dossier, "config.json"), encoding="utf-8") as f:
                c = json.load(f)["motdepasse"]
        except (FileNotFoundError, KeyError):
            return False
        h = hashlib.pbkdf2_hmac("sha256", mdp.encode(), base64.b64decode(c["sel"]), c["iter"])
        return hmac.compare_digest(h, base64.b64decode(c["hash"]))

    # ---- interface attendue par le SDK ----

    async def get_client(self, client_id):
        c = self._etat["clients"].get(client_id)
        return OAuthClientInformationFull.model_validate(c) if c else None

    async def register_client(self, client_info):
        if not client_info.redirect_uris or not all(retour_permis(u) for u in client_info.redirect_uris):
            raise RegistrationError("invalid_redirect_uri", f"Seule l'adresse de retour {RETOUR_CLAUDE} est acceptée.")
        with self._verrou:
            if len(self._etat["clients"]) >= 200:  # l'enregistrement est ouvert : on borne
                anciens = sorted(self._etat["clients"].items(), key=lambda kv: kv[1].get("client_id_issued_at") or 0)
                utilises = {v["client_id"] for k in ("acces", "rafraichissement") for v in self._etat[k].values()}
                for cid, _ in anciens:
                    if cid not in utilises and len(self._etat["clients"]) >= 200:
                        del self._etat["clients"][cid]
            self._etat["clients"][client_info.client_id] = client_info.model_dump(mode="json", exclude_none=True)
            self._enregistre()

    async def authorize(self, client, params: AuthorizationParams):
        if params.resource and params.resource.rstrip("/") != self.ressource.rstrip("/"):
            raise AuthorizeError("invalid_target", "Cette ressource n'est pas servie ici.")
        demande = secrets.token_urlsafe(32)
        with self._verrou:
            now = time.time()
            self._demandes = {k: v for k, v in self._demandes.items() if v[2] > now}
            self._demandes[demande] = (client, params, now + 600)
        return f"{self.emetteur}/connexion?demande={demande}"

    async def load_authorization_code(self, client, authorization_code):
        c = self._codes.get(authorization_code)
        return c if c and c.client_id == client.client_id else None

    def _emet(self, client_id, scopes):
        acces, raf, now = secrets.token_urlsafe(32), secrets.token_urlsafe(32), int(time.time())
        base = {"client_id": client_id, "scopes": scopes, "resource": self.ressource, "subject": "proprietaire"}
        self._etat["acces"][empreinte(acces)] = {**base, "expires_at": now + ACCES}
        self._etat["rafraichissement"][empreinte(raf)] = {**base, "expires_at": now + RAFRAICHISSEMENT}
        self._enregistre()
        return OAuthToken(access_token=acces, token_type="Bearer", expires_in=ACCES,
                          refresh_token=raf, scope=" ".join(scopes) or None)

    async def exchange_authorization_code(self, client, authorization_code):
        with self._verrou:
            if self._codes.pop(authorization_code.code, None) is None:
                from mcp.server.auth.provider import TokenError
                raise TokenError("invalid_grant", "Ce code a déjà servi.")
            return self._emet(client.client_id, authorization_code.scopes)

    async def load_refresh_token(self, client, refresh_token):
        v = self._etat["rafraichissement"].get(empreinte(refresh_token))
        if not v or v["client_id"] != client.client_id or v["expires_at"] < time.time():
            return None
        return RefreshToken(token=refresh_token, **v)

    async def exchange_refresh_token(self, client, refresh_token, scopes):
        with self._verrou:  # rotation : l'ancien jeton meurt dans la même réponse
            if self._etat["rafraichissement"].pop(empreinte(refresh_token.token), None) is None:
                from mcp.server.auth.provider import TokenError
                raise TokenError("invalid_grant", "Ce jeton de rafraîchissement n'est plus valable.")
            return self._emet(client.client_id, scopes or refresh_token.scopes)

    async def load_access_token(self, token):
        v = self._etat["acces"].get(empreinte(token))
        if not v or v["expires_at"] < time.time():
            return None
        return AccessToken(token=token, **v)

    async def revoke_token(self, token):
        with self._verrou:
            for k in ("acces", "rafraichissement"):
                self._etat[k] = {h: v for h, v in self._etat[k].items() if v["client_id"] != token.client_id}
            self._enregistre()

    # ---- écran de connexion ----

    def _page(self, demande, client, params, erreur=""):
        hote = html.escape(urlparse(str(params.redirect_uri)).netloc)
        local = "" if str(params.redirect_uri) == RETOUR_CLAUDE else (
            "<p class=w>Cette demande vient d'un programme de cet ordinateur, pas de claude.ai. "
            "Ne continue que si tu viens de la lancer toi-même.</p>")
        return HTMLResponse(f"""<!doctype html><html lang="fr"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Connexion · {html.escape(self.nom)}</title>
<style>body{{font:16px system-ui;max-width:26rem;margin:12vh auto;padding:0 1.2rem;color:#1c1b1a}}
input,button{{font:inherit;width:100%;box-sizing:border-box;padding:.7rem;border-radius:.6rem;border:1px solid #bbb;margin-top:.6rem}}
button{{background:#1c1b1a;color:#fff;border:0;font-weight:700}}.e{{color:#b3261e;font-weight:600}}.w{{background:#fff3cd;padding:.6rem;border-radius:.6rem}}
small{{color:#666}}@media(prefers-color-scheme:dark){{body{{background:#161616;color:#eee}}button{{background:#eee;color:#111}}}}</style>
<h1>{html.escape(self.nom)}</h1>
<p><b>{html.escape(client.client_name or "Un client MCP")}</b> demande à lire et modifier tes données.
Après accord, tu seras renvoyé vers <b>{hote}</b>.</p>{local}
{f'<p class=e>{html.escape(erreur)}</p>' if erreur else ''}
<form method="post" action="{self.emetteur}/connexion">
<input type="hidden" name="demande" value="{html.escape(demande)}">
<input type="password" name="motdepasse" placeholder="Mot de passe de la passerelle" autofocus autocomplete="current-password">
<button>Autoriser</button></form>
<p><small>Si tu n'as rien demandé, ferme cette page.</small></p></html>""",
                            status_code=401 if erreur else 200,
                            headers={"Cache-Control": "no-store", "X-Frame-Options": "DENY",
                                     "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'"})

    async def connexion(self, request: Request):
        if request.method == "GET":
            demande = request.query_params.get("demande", "")
            form = {}
        else:
            form = await request.form()
            demande = str(form.get("demande", ""))
        d = self._demandes.get(demande)
        if not d or d[2] < time.time():
            return HTMLResponse("<meta charset=utf-8><p>Cette demande de connexion a expiré. Relance-la depuis Claude.</p>",
                                status_code=400)
        client, params, _ = d
        if request.method == "GET":
            return self._page(demande, client, params)
        now = time.time()
        with self._verrou:
            self._echecs = [t for t in self._echecs if t > now - 900]
            if len(self._echecs) >= 5:
                return self._page(demande, client, params, "Trop d'essais. Réessaie dans un quart d'heure.")
            if not self._mot_de_passe_ok(str(form.get("motdepasse", ""))):
                self._echecs.append(now)
                return self._page(demande, client, params, "Mot de passe refusé.")
            del self._demandes[demande]
            code = secrets.token_urlsafe(32)
            self._codes = {k: v for k, v in self._codes.items() if v.expires_at > now}
            self._codes[code] = AuthorizationCode(
                code=code, scopes=params.scopes or [], expires_at=now + 300, client_id=client.client_id,
                code_challenge=params.code_challenge, redirect_uri=params.redirect_uri,
                redirect_uri_provided_explicitly=params.redirect_uri_provided_explicitly,
                resource=self.ressource, subject="proprietaire")
        return RedirectResponse(construct_redirect_uri(str(params.redirect_uri), code=code, state=params.state),
                                status_code=302, headers={"Cache-Control": "no-store"})
