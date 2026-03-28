#!/bin/bash
set -euo pipefail

# Firewall
sudo /usr/local/bin/init-firewall.sh

# Claude Code API key setup
echo '{"apiKeyHelper": "/home/node/.claude/anthropic_key.sh"}' > /home/node/.claude/settings.json
printf '#!/bin/sh\necho $ANTHROPIC_API_KEY' > /home/node/.claude/anthropic_key.sh
chmod +x /home/node/.claude/anthropic_key.sh

# Git
git config --global --add safe.directory /workspace

# ngrok auth
ngrok config add-authtoken "${NGROK_AUTH_TOKEN}"


# Linear MCP server (skip if already registered)
claude mcp add --transport http linear-server https://mcp.linear.app/mcp 2>/dev/null || true
