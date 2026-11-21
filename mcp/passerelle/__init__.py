"""Passerelle MCP : un serveur distant (Streamable HTTP + OAuth) qui expose les outils d'une appli.

Le cœur (authentification, journal, démarrage) est commun ; chaque appli est un module de
`apps/` qui déclare ses outils. Pour brancher une autre appli : un module de plus, un service
de plus dans compose.yaml, la même marche à suivre côté Claude.
"""
