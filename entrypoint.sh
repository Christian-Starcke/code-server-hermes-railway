#!/bin/bash

PREFIX="code-server-hermes"
START_DIR="${START_DIR:-/home/coder/project}"
N8N_AS_CODE_PROJECT_DIR="${N8N_AS_CODE_PROJECT_DIR:-$START_DIR/n8n-as-code}"
export START_DIR N8N_AS_CODE_PROJECT_DIR

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
RESEND_API_KEY SENTRY_ACCESS_TOKEN
BETTERSTACK_API_TOKEN POSTHOG_PERSONAL_API_KEY
N8N_NATIVE_MCP_TOKEN N8N_NATIVE_MCP_URL
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

# ── 2. Multi-repo workspace bootstrap ─────────────────
configure_git_auth() {
    if [ -n "$GITHUB_TOKEN" ]; then
        git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    fi
}

clone_or_pull() {
    local url="$1"
    local dest="$2"
    if [ -z "$url" ]; then
        return 0
    fi
    if [ -d "$dest/.git" ]; then
        echo "[$PREFIX] Pulling $dest ..."
        git -C "$dest" pull --ff-only 2>&1 || \
            echo "[$PREFIX] ⚠ Git pull failed — $dest"
    else
        echo "[$PREFIX] Cloning $url -> $dest ..."
        git clone "$url" "$dest" 2>&1 || \
            echo "[$PREFIX] ⚠ Git clone failed — $dest"
    fi
}

configure_git_auth
clone_or_pull "$GIT_REPO_N8N" "$START_DIR/n8n-as-code"
clone_or_pull "$GIT_REPO_PLAYBOOK" "$START_DIR/prism-playbook"
clone_or_pull "$GIT_REPO_PLATFORM" "$START_DIR/prism-platform"

if [ -n "${GIT_REPO}" ] && [ -z "$GIT_REPO_N8N$GIT_REPO_PLAYBOOK$GIT_REPO_PLATFORM" ]; then
    echo "[$PREFIX] ⚠ Legacy GIT_REPO is set but GIT_REPO_N8N/PLAYBOOK/PLATFORM are not — migrate to multi-repo vars"
fi

if [ ! -d "$START_DIR/n8n-as-code/.git" ] && [ ! -d "$START_DIR/prism-playbook/.git" ] && [ ! -d "$START_DIR/prism-platform/.git" ]; then
    echo "[$PREFIX] No workspace repos cloned — set GIT_REPO_N8N, GIT_REPO_PLAYBOOK, GIT_REPO_PLATFORM"
    echo "# code-server workspace" > "$START_DIR/welcome.md"
    echo "Set GIT_REPO_N8N (and optional PLAYBOOK/PLATFORM) in Railway to auto-clone repositories." >> "$START_DIR/welcome.md"
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
export PATH="$HOME/.npm-global/bin:$PATH"
export N8NAC_TELEMETRY_DISABLED=1

# ── 6. Configure n8n environment + update AI context ──
if [ -n "$N8N_API_KEY" ] && [ -d "$N8N_AS_CODE_PROJECT_DIR" ]; then
    echo "[$PREFIX] Configuring n8n environment in $N8N_AS_CODE_PROJECT_DIR ..."
    cd "$N8N_AS_CODE_PROJECT_DIR" || true
    if n8nac env list 2>/dev/null | grep -q "Dev"; then
        n8nac env use Dev 2>&1 | tail -1
        printf '%s' "$N8N_API_KEY" | n8nac env auth set Dev --api-key-stdin 2>&1 | head -1
        echo "[$PREFIX] ✓ n8n environment 'Dev' authenticated"
    else
        echo "[$PREFIX] Creating n8n environment 'Dev'..."
        n8nac env add Dev \
            --base-url https://primary-production-10917.up.railway.app \
            --workflows-path workflows/dev 2>&1 | tail -1
        printf '%s' "$N8N_API_KEY" | n8nac env auth set Dev --api-key-stdin 2>&1 | head -1
        n8nac env use Dev 2>&1 | tail -1
        echo "[$PREFIX] ✓ n8n environment 'Dev' created and authenticated"
    fi
    echo "[$PREFIX] Updating n8n AI context..."
    n8nac update-ai 2>&1 | tail -2
    echo "[$PREFIX] ✓ n8n AI context updated"
    WF_COUNT=$(n8nac list 2>&1 | grep -cE "^(│ )?[a-zA-Z0-9_-]+" || echo "0")
    echo "[$PREFIX] n8n: $WF_COUNT workflows available"
elif [ -n "$N8N_API_KEY" ]; then
    echo "[$PREFIX] ⚠ N8N_API_KEY set but $N8N_AS_CODE_PROJECT_DIR not found — skip n8nac setup"
fi

# ── 7. Generate native VS Code mcp.json ────────────────
echo "[$PREFIX] Generating native MCP mcp.json..."
MCP_JSON_DIR="$START_DIR/.vscode"
mkdir -p "$MCP_JSON_DIR"

python3 << 'PYEOF'
import json, os

start_dir = os.environ.get("START_DIR", "/home/coder/project")
n8n_project_dir = os.environ.get("N8N_AS_CODE_PROJECT_DIR", start_dir + "/n8n-as-code")
mcp_path = os.path.join(start_dir, ".vscode", "mcp.json")

G = os.environ.get
github_token   = G("GITHUB_TOKEN", "")
firecrawl_key  = G("FIRECRAWL_API_KEY", "")
retell_key     = G("RETELL_API_KEY", "")
supabase_pat   = G("SUPABASE_PAT", "")
resend_key     = G("RESEND_API_KEY", "")
n8n_url        = G("N8N_NATIVE_MCP_URL", "")
n8n_token      = G("N8N_NATIVE_MCP_TOKEN", "")
openrouter_key = G("OPENROUTER_API_KEY", "")
sentry_token   = G("SENTRY_ACCESS_TOKEN", "")
betterstack_tk = G("BETTERSTACK_API_TOKEN", "")
posthog_key    = G("POSTHOG_PERSONAL_API_KEY", "")

mcp = {
    "mcpServers": {
        "github": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": github_token}
        },
        "firecrawl": {
            "command": "npx",
            "args": ["-y", "firecrawl-mcp"],
            "env": {"FIRECRAWL_API_KEY": firecrawl_key}
        },
        "railway": {
            "command": "/home/coder/.npm-global/bin/railway",
            "args": ["mcp"]
        },
        "retellai": {
            "command": "npx",
            "args": ["-y", "@abhaybabbar/retellai-mcp-server"],
            "env": {"RETELL_API_KEY": retell_key}
        },
        "supabase": {
            "command": "npx",
            "args": ["-y", "@supabase/mcp-server-supabase@latest",
                     "--access-token", supabase_pat]
        },
        "resend": {
            "command": "npx",
            "args": ["-y", "resend-mcp"],
            "env": {"RESEND_API_KEY": resend_key}
        },
        "n8nac": {
            "command": "npx",
            "args": ["-y", "@n8n-as-code/mcp"],
            "env": {
                "N8N_AS_CODE_PROJECT_DIR": n8n_project_dir,
                "N8NAC_NATIVE_MCP_ENABLED": "1",
                "N8N_NATIVE_MCP_URL": n8n_url,
                "N8NAC_NATIVE_MCP_TOKEN": n8n_token
            }
        },
        "openrouter": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://mcp.openrouter.ai/mcp",
                     "--header", "Authorization: Bearer " + openrouter_key]
        },
        "vercel": {
            "url": "https://mcp.vercel.com"
        },
        "sentry": {
            "command": "npx",
            "args": ["-y", "@sentry/mcp-server@latest"],
            "env": {
                "SENTRY_ACCESS_TOKEN": sentry_token,
                "MCP_DISABLE_SKILLS": "seer"
            }
        },
        "better-stack": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://mcp.betterstack.com",
                     "--header", "Authorization: Bearer " + betterstack_tk]
        },
        "posthog": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://mcp.posthog.com/mcp",
                     "--header", "Authorization: Bearer " + posthog_key]
        }
    }
}

os.makedirs(os.path.dirname(mcp_path), exist_ok=True)
with open(mcp_path, "w") as f:
    json.dump(mcp, f, indent=2)

gip = os.path.join(start_dir, ".vscode", ".gitignore")
with open(gip, "w") as f:
    f.write("# MCP config with embedded secrets -- auto-generated at container startup\nmcp.json\n")

PYEOF
echo "[$PREFIX] ✓ Generated native mcp.json with 12 MCP servers + .gitignore"

# ── 8. Verify Hermes ACP configuration ─────────────────
echo "[$PREFIX] Checking Hermes ACP configuration..."
/opt/hermes/bin/hermes acp --check 2>&1 && \
    echo "[$PREFIX] ✓ Hermes ACP configuration valid" || \
    echo "[$PREFIX] ⚠ Hermes ACP check failed -- the extension may not connect"

# ── 9. Start code-server (foreground) ─────────────────
echo "[$PREFIX] Starting code-server..."
exec /usr/bin/entrypoint.sh --bind-addr 0.0.0.0:8080 "$START_DIR"