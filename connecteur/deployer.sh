#!/bin/bash
# Met en ligne le connecteur Bim sur Cloudflare Workers (offre gratuite) et affiche
# l'adresse à coller dans claude.ai. À lancer soi-même : le script demande le jeton GitHub.
set -euo pipefail
cd "$(dirname "$0")"
KEYFILE="$HOME/.bim-connecteur-cle"

echo "1/4 Connexion à Cloudflare"
npx --yes wrangler@4 whoami >/dev/null 2>&1 || npx --yes wrangler@4 login

echo "2/4 Mise en ligne"
OUT=$(npx --yes wrangler@4 deploy 2>&1) || { echo "$OUT"; exit 1; }
URL=$(echo "$OUT" | grep -Eo 'https://[a-z0-9.-]+\.workers\.dev' | head -1)

echo "3/4 Secrets"
if [ ! -f "$KEYFILE" ]; then
  (umask 077; openssl rand -hex 24 > "$KEYFILE")
fi
REPO="$(gh api user -q .login)/bim-data"
tr -d '\n' < "$KEYFILE" | npx --yes wrangler@4 secret put BIM_KEY >/dev/null
printf '%s' "$REPO" | npx --yes wrangler@4 secret put BIM_REPO >/dev/null
echo "Colle maintenant ton jeton GitHub (limité à $REPO, Contents en lecture et écriture) :"
npx --yes wrangler@4 secret put GITHUB_TOKEN

echo "4/4 Terminé. Adresse du connecteur à coller dans claude.ai (garde-la pour toi) :"
echo "$URL/mcp/$(cat "$KEYFILE")"
