FROM codercom/code-server:4.126.0

USER root

# === Install Hermes + deps ===
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Hermes in its own venv
RUN python3 -m venv /opt/hermes && \
    /opt/hermes/bin/pip install --upgrade pip && \
    /opt/hermes/bin/pip install hermes-agent[acp]
ENV PATH="/opt/hermes/bin:$PATH"

# === Install Railway CLI + n8nac ===
# Required for Railway MCP server (railway mcp) and n8n-as-code CLI
ENV NPM_CONFIG_PREFIX=/home/coder/.npm-global
ENV PATH="/home/coder/.npm-global/bin:$PATH"
RUN mkdir -p /home/coder/.npm-global && \
    npm install -g @railway/cli n8nac && \
    chown -R coder:coder /home/coder/.npm-global

# Pre-configure VS Code settings (dark theme, ACP config)
COPY settings.json /home/coder/.local/share/code-server/User/settings.json
RUN chown -R coder:coder /home/coder/.local

# Port
ENV PORT=8080

# Custom entrypoint
COPY entrypoint.sh /usr/bin/deploy-container-entrypoint.sh
RUN chmod +x /usr/bin/deploy-container-entrypoint.sh

# Entrypoint runs as root to chown the Railway volume, then drops to coder
USER root

ENTRYPOINT ["bash", "/usr/bin/deploy-container-entrypoint.sh"]