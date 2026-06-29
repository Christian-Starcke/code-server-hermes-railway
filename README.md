# code-server + Hermes ACP on Railway

Browser-accessible VS Code with Hermes Agent AI built in. Open your IDE from phone, tablet, or any browser — with Hermes as your coding agent.

## One-click Deploy

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new?template=https://github.com/Christian-Starcke/code-server-hermes-railway)

Or from the CLI (if you have the Railway CLI linked to your project):

```bash
railway up
```

## Required Environment Variables

Set these in your Railway service's **Variables** tab:

| Variable | Description |
|----------|-------------|
| `PASSWORD` | code-server login password |
| `OPENROUTER_API_KEY` | or any Hermes-supported provider key |

## Optional Variables

| Variable | Description |
|----------|-------------|
| `GIT_REPO` | GitHub URL to auto-clone (e.g. `https://github.com/your-org/your-repo`) |
| `HERMES_CONFIG_B64` | Base64-encoded copy of `~/.hermes/config.yaml` (if you have custom config) |
| `START_DIR` | Working directory (default: `/home/coder/project`) |

## How It Works

```
Railway container
├── code-server (VS Code in browser)
│   └── ACP Client extension → spawns `hermes acp`
├── Hermes Agent (ACP mode)
│   └── Same API keys, same config as your main Hermes
└── GIT_REPO → auto-cloned workspace
```

1. Deploy to Railway using the button above
2. Set `PASSWORD` and `OPENROUTER_API_KEY` (and optionally `GIT_REPO`) in your Railway Variables
3. Open the Railway-generated URL (`https://your-service.up.railway.app`)
4. Log in with your `PASSWORD`
5. Open the **ACP Client** panel (ACP icon in the activity bar)
6. **Hermes Agent** is pre-configured — click to connect
7. Chat with Hermes inside your IDE

## Adding to Your Web App

In your Next.js app:

```tsx
export function CodeWorkspace() {
  return (
    <iframe
      src="https://your-service.up.railway.app"
      title="IDE"
      allow="clipboard-read; clipboard-write"
      style={{ width: "100%", height: "100%", border: 0 }}
    />
  );
}
```

**Note:** code-server's password auth doesn't play well inside iframes. For production, put Cloudflare Access or similar auth in front, or use the `--link` auth mode.

## Credentials

The Hermes inside code-server is a **separate instance** from your main Railway Hermes — it shares API keys but has its own sessions. They don't conflict.

## Persistent state (survives redeploys)

The workspace Railway volume (`/home/coder/project`) stores:

| Path on volume | Purpose |
|----------------|---------|
| `n8n-as-code/`, `prism-*` | Cloned git repos |
| `.railway-cli/` | Railway CLI login (symlinked from `~/.railway`) |
| `.code-server-persist/User/globalStorage/` | VS Code extension state (GitHub sign-in, etc.) |
| `.code-server-persist/config/` | code-server secret storage (OAuth tokens) |
| `.code-server-persist/gitconfig` | Git global config (token auth from `GITHUB_TOKEN`) |
| `.code-server-persist/User/settings.json` | VS Code settings (seeded once from image) |

After the first GitHub sign-in in VS Code, it should persist across container restarts and redeploys. Set `GITHUB_TOKEN` in Railway for headless git/MCP auth on every boot.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the container — code-server + Python + Hermes ACP + VS Code extensions |
| `entrypoint.sh` | Startup script — configures Hermes, clones repo, starts ACP server, launches code-server |
| `settings.json` | Pre-configured VS Code settings — ACP extension pointed at `hermes acp` |