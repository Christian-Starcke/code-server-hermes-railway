FROM codercom/code-server:4.126.0

USER root

# === Install Hermes ===
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Hermes in its own venv
RUN python3 -m venv /opt/hermes && \
    /opt/hermes/bin/pip install --upgrade pip && \
    /opt/hermes/bin/pip install hermes-agent[acp]
ENV PATH="/opt/hermes/bin:$PATH"

# === Pre-install VS Code extensions ===
# ACP Client — connects to hermes acp (Open VSX, works in code-server ✓)
RUN code-server --install-extension formulahendry.acp-client
# A few quality-of-life extensions
RUN code-server --install-extension esbenp.prettier-vscode

# Pre-configure the ACP extension to use Hermes by default
COPY settings.json /home/coder/.local/share/code-server/User/settings.json
RUN chown -R coder:coder /home/coder/.local

# Port
ENV PORT=8080

# Custom entrypoint starts Hermes ACP in the background, then code-server
COPY entrypoint.sh /usr/bin/deploy-container-entrypoint.sh
RUN chmod +x /usr/bin/deploy-container-entrypoint.sh

USER coder

# Run via bash so a missing executable bit can't block startup (Git files default to 644)
ENTRYPOINT ["bash", "/usr/bin/deploy-container-entrypoint.sh"]
