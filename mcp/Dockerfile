# Passerelle MCP d'une appli (ici Bim). Contexte de construction : la racine du dépôt Bim.
FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 TZ=Europe/Paris DONNEES=/donnees BIM_CLI=/app/bin/bim ECOUTE=0.0.0.0 PORT=8793
WORKDIR /app
COPY mcp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd -u 1027 -m passerelle && mkdir /donnees && chown passerelle /donnees
COPY bin/bim bin/bim
COPY mcp/passerelle passerelle
COPY mcp/apps apps
USER passerelle
VOLUME /donnees
EXPOSE 8793
CMD ["python", "-m", "passerelle"]
