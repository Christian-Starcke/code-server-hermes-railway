FROM codercom/code-server:4.126.0

USER root

# === Install Hermes + deps (incl. Playwright/Chromium system libraries) ===
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    nodejs \
    npm \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libx11-6 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    && rm -rf /var/lib/apt/lists/*

# Hermes in its own venv
RUN python3 -m venv /opt/hermes && \
    /opt/hermes/bin/pip install --upgrade pip && \
    /opt/hermes/bin/pip install hermes-agent[acp]
ENV PATH="/opt/hermes/bin:$PATH"
# Symlinked to Railway volume at runtime (see entrypoint.sh)
ENV PLAYWRIGHT_BROWSERS_PATH="/home/coder/.hermes/playwright-browsers"

# === Install Railway CLI + n8nac ===
# Required for Railway MCP server (railway mcp) and n8n-as-code CLI
ENV NPM_CONFIG_PREFIX=/home/coder/.npm-global
ENV PATH="/home/coder/.npm-global/bin:$PATH"
RUN mkdir -p /home/coder/.npm-global && \
    npm install -g @railway/cli n8nac && \
    chown -R coder:coder /home/coder/.npm-global && \
    ln -sf /home/coder/.npm-global/bin/railway /usr/local/bin/railway && \
    ln -sf /home/coder/.npm-global/bin/n8nac /usr/local/bin/n8nac

# Default PATH for all login/interactive shells (code-server terminals use sh or bash)
RUN printf '%s\n' \
    'export PATH="/home/coder/.hermes/node/bin:/home/coder/.npm-global/bin:/opt/hermes/bin:$PATH"' \
    'export N8NAC_TELEMETRY_DISABLED=1' \
    'export PLAYWRIGHT_BROWSERS_PATH="/home/coder/.hermes/playwright-browsers"' \
    > /etc/profile.d/code-server-hermes.sh && \
    chmod 644 /etc/profile.d/code-server-hermes.sh

# Pre-configure VS Code settings (dark theme, ACP config, menu bar)
COPY settings.json /etc/code-server-hermes/settings.json
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