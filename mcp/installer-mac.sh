#!/bin/bash
# Installe le serveur MCP de Bim comme service du Mac (démarre avec la session, redémarre s'il tombe).
#   ./installer-mac.sh https://bim.ton-domaine.fr     installe ou met à jour avec cette adresse publique
#   ./installer-mac.sh                                 installe en local seulement (http://localhost:8793)
#   ./installer-mac.sh retirer                         retire le service
# Le serveur n'écoute que sur ce Mac (127.0.0.1:8793) : c'est le tunnel qui le rend joignable.
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.bim.mcp.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
if [ "${1:-}" = "retirer" ]; then rm -f "$PLIST"; echo "Service retiré."; exit 0; fi
URL="${1:-http://localhost:8793}"
[ -x "$ICI/.venv/bin/python" ] || { uv venv -q "$ICI/.venv" && uv pip install -q --python "$ICI/.venv/bin/python" -r "$ICI/requirements.txt"; }
mkdir -p "$HOME/Library/Logs" "$ICI/donnees"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.bim.mcp</string>
  <key>ProgramArguments</key><array><string>$ICI/.venv/bin/python</string><string>-m</string><string>passerelle</string></array>
  <key>WorkingDirectory</key><string>$ICI</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>APP</key><string>bim</string>
    <key>URL_PUBLIQUE</key><string>$URL</string>
    <key>PORT</key><string>8793</string>
    <key>DONNEES</key><string>$ICI/donnees</string>
  </dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/bim-mcp.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/bim-mcp.log</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Service installé pour $URL. Journal : ~/Library/Logs/bim-mcp.log"
[ -f "$ICI/donnees/config.json" ] || echo "Reste à choisir le mot de passe : cd $ICI && .venv/bin/python -m passerelle init"
