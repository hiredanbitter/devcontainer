#!/bin/bash
set -euo pipefail

# Firewall
sudo /usr/local/bin/init-firewall.sh

# # Claude Code API key setup
# echo '{"apiKeyHelper": "/home/node/.claude/anthropic_key.sh"}' > /home/node/.claude/settings.json
# printf '#!.bin.sh\necho $ANTHROPIC_API_KEY' > /home/node/.claude/anthropic_key.sh
# chmod +x /home/node/.claude/anthropic_key.sh

# Git
git config --glob al --add safe.directory /workspace

# Run project setup
bash /workspace/.devcontainer/script-00-setup.sh
