#!/bin/bash
# Installe (ou retire avec « retirer ») l'agent qui exécute les consignes sur ce Mac, chaque minute.
# À lancer soi-même : tant qu'il n'est pas installé, aucune consigne n'est exécutée.
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.bim.consignes.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
if [ "${1:-}" = "retirer" ]; then rm -f "$PLIST"; echo "Agent retiré."; exit 0; fi
mkdir -p "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.bim.consignes</string>
  <key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$ICI/consignes.py</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HOME/.local/bin:$HOME/development/flutter/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/bim-consignes.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/bim-consignes.log</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Agent installé. Journal : ~/Library/Logs/bim-consignes.log"
