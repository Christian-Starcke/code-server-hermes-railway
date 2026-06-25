#!/bin/bash

PREFIX="code-server-hermes"
START_DIR="${START_DIR:-/home/coder/project}"

mkdir -p "$START_DIR"

# ── 1. Hermes setup ─────────────────────────────────────
mkdir -p /home/coder/.hermes

# Write .env from Railway environment variables
ENV_FILE="/home/coder/.hermes/.env"
: > "$ENV_FILE"

# Collect all known env vars (provider + MCP keys)
ALL_KEYS="
OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
GEMINI_API_KEY DEEPSEEK_API_KEY XAI_API_KEY
HF_TOKEN MISTRAL_API_KEY ELEVENLABS_API_KEY
GITHUB_TOKEN COPILOT_GITHUB_TOKEN
VOICE_TOOLS_OPENAI_KEY
GLM_API_KEY KIMI_API_KEY DASHSCOPE_API_KEY
FIRECRAWL_API_KEY RETELL_API_KEY SUPABASE_PAT
N8N_API_KEY RAILWAY_API_TOKEN
"

for var in $ALL_KEYS; do
    val="${!var}"
    if [ -n "$val" ]; then
        echo "${var}=${val}" >> "$ENV_FILE"
    fi
done

if [ -s "$ENV_FILE" ]; then
    echo "[$PREFIX] ✓ Configured Hermes from $(wc -l < "$ENV_FILE") env vars"
else
    echo "[$PREFIX] ⚠ No Hermes API keys found. Set OPENROUTER_API_KEY in Railway."
fi

# Restore config.yaml if provided as base64 env var
if [ -n "$HERMES_CONFIG_B64" ]; then
    echo "$HERMES_CONFIG_B64" | base64 -d > /home/coder/.hermes/config.yaml 2>/dev/null
    echo "[$PREFIX] ✓ Restored Hermes config.yaml"
fi

# ── 2. Clone repository ───────────────────────────────
if [ -n "${GIT_REPO}" ]; then
    if [ -d "$START_DIR/.git" ]; then
        echo "[$PREFIX] Repository already cloned"
    else
        echo "[$PREFIX] Cloning $GIT_REPO ..."
        git clone "$GIT_REPO" "$START_DIR" 2>&1 || \
            echo "[$PREFIX] ⚠ Git clone failed — check GIT_REPO value and credentials"
    fi
else
    echo "[$PREFIX] No GIT_REPO set — starting with empty workspace"
    echo "# code-server workspace" > "$START_DIR/welcome.md"
    echo "Set GIT_REPO in Railway environment to auto-clone a repository." >> "$START_DIR/welcome.md"
fi

# ── 3. Restore VS Code settings from image ────────────
SETTINGS_DIR="/home/coder/.local/share/code-server/User"
mkdir -p "$SETTINGS_DIR"
cp /home/coder/.local/share/code-server/User/settings.json "$SETTINGS_DIR/settings.json" 2>/dev/null || true
echo "[$PREFIX] ✓ Restored VS Code settings"

# ── 4. Install VS Code extensions ────────────────────
echo "[$PREFIX] Installing ACP Client extension..."
code-server --install-extension formulahendry.acp-client --force 2>&1 | tail -1
echo "[$PREFIX] ✓ ACP Client extension installed"

echo "[$PREFIX] Installing n8n-as-code extension..."
code-server --install-extension etienne-lescot.n8n-as-code --force 2>&1 | tail -1
echo "[$PREFIX] ✓ n8n-as-code extension installed"

# ── 5. Add Railway CLI to PATH ───────────────────────
# Railway CLI is installed via npm at build time
export PATH="$HOME/.npm-global/bin:$PATH"
export N8NAC_TELEMETRY_DISABLED=1

# ── 6. Configure n8n environment + update AI context ──
if [ -n "$N8N_API_KEY" ]; then
    echo "[$PREFIX] Configuring n8n environment..."
    cd "$START_DIR" || true
    
    # Check if the environment exists already
    if n8nac env list 2>/dev/null | grep -q "Personal"; then
        printf '%s' "$N8N_API_KEY" | n8nac env auth set Personal --api-key-stdin 2>&1 | head -1
        echo "[$PREFIX] ✓ n8n environment 'Personal' authenticated"
    else
        echo "[$PREFIX] Creating n8n environment 'Personal'..."
        n8nac env add Personal \
            --base-url https://primary-production-10917.up.railway.app \
            --workflows-path workflows/starcke-n8n-railway-hosted 2>&1 | tail -1
        printf '%s' "$N8N_API_KEY" | n8nac env auth set Personal --api-key-stdin 2>&1 | head -1
        n8nac env use Personal 2>&1 | tail -1
        echo "[$PREFIX] ✓ n8n environment 'Personal' created and authenticated"
    fi
    
    # Update AI context (schemas, skills, examples) for the IDE
    echo "[$PREFIX] Updating n8n AI context..."
    n8nac update-ai 2>&1 | tail -2
    echo "[$PREFIX] ✓ n8n AI context updated"
    
    # Show workflow count
    WF_COUNT=$(n8nac list 2>&1 | grep -cE "^(│ )?[a-zA-Z0-9_-]+" || echo "0")
    echo "[$PREFIX] n8n: $WF_COUNT workflows available"
fi

# ── 7. Verify Hermes ACP configuration ─────────────────
echo "[$PREFIX] Checking Hermes ACP configuration..."
/opt/hermes/bin/hermes acp --check 2>&1 && \
    echo "[$PREFIX] ✓ Hermes ACP configuration valid" || \
    echo "[$PREFIX] ⚠ Hermes ACP check failed — the extension may not connect"

# ── 8. Start code-server (foreground) ─────────────────
echo "[$PREFIX] Starting code-server..."
exec /usr/bin/entrypoint.sh --bind-addr 0.0.0.0:8080 "$START_DIR"