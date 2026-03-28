#!/usr/bin/env bash
# fix-worker-setup.sh
# Fixes three bugs that prevent `pnpm worker` from connecting to the coordinator.
# Run from the agentfactory/my-agent directory:
#   bash ../../summaries/fix-worker-setup.sh
# or from anywhere by passing the project root:
#   bash fix-worker-setup.sh /path/to/agentfactory/my-agent

set -euo pipefail

# ── Resolve project root ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"

if [[ ! -f "$PROJECT_DIR/package.json" ]] || ! grep -q '"my-agent"' "$PROJECT_DIR/package.json" 2>/dev/null; then
  # Try the sibling my-agent directory relative to this script
  CANDIDATE="$SCRIPT_DIR/../my-agent"
  if [[ -f "$CANDIDATE/package.json" ]]; then
    PROJECT_DIR="$(cd "$CANDIDATE" && pwd)"
  else
    echo "ERROR: Could not locate the my-agent project directory."
    echo "Usage: bash fix-worker-setup.sh [/path/to/agentfactory/my-agent]"
    exit 1
  fi
fi

echo "Project directory: $PROJECT_DIR"
cd "$PROJECT_DIR"

# ── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo "  [INFO]  $*"; }
success() { echo "  [OK]    $*"; }
warn()    { echo "  [WARN]  $*"; }

# ────────────────────────────────────────────────────────────────────────────
# FIX 1 — Redis
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Fix 1: Redis ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! command -v redis-cli &>/dev/null; then
  info "Redis not found — installing..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y redis-server
  elif command -v brew &>/dev/null; then
    brew install redis
  else
    echo "ERROR: Cannot install Redis automatically. Install it manually and re-run."
    exit 1
  fi
else
  info "Redis binary found."
fi

if ! redis-cli ping &>/dev/null; then
  info "Redis not responding — starting service..."
  if command -v service &>/dev/null && service redis-server status &>/dev/null 2>&1; then
    sudo service redis-server start
  elif command -v systemctl &>/dev/null && systemctl list-units --type=service | grep -q redis; then
    sudo systemctl start redis
  else
    redis-server --daemonize yes --logfile /tmp/redis-agentfactory.log
  fi
  sleep 1
fi

if redis-cli ping | grep -q PONG; then
  success "Redis is running."
else
  echo "ERROR: Redis did not start. Check logs and start it manually."
  exit 1
fi

# ── Ensure REDIS_URL is in .env.local ───────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env.local"
if [[ ! -f "$ENV_FILE" ]]; then
  info "Creating .env.local"
  touch "$ENV_FILE"
fi

if ! grep -q "^REDIS_URL=" "$ENV_FILE"; then
  echo "REDIS_URL=redis://localhost:6379" >> "$ENV_FILE"
  success "Added REDIS_URL to .env.local"
else
  success "REDIS_URL already set in .env.local"
fi

# ────────────────────────────────────────────────────────────────────────────
# FIX 2 — WORKER_API_URL (remove the /api suffix)
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Fix 2: WORKER_API_URL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if grep -q "^WORKER_API_URL=.*\/api$" "$ENV_FILE"; then
  # Strip trailing /api from the value
  sed -i 's|^\(WORKER_API_URL=.*\)/api$|\1|' "$ENV_FILE"
  success "Removed trailing /api from WORKER_API_URL in .env.local"
elif grep -q "^WORKER_API_URL=" "$ENV_FILE"; then
  CURRENT=$(grep "^WORKER_API_URL=" "$ENV_FILE" | head -1)
  success "WORKER_API_URL already set (no /api suffix): $CURRENT"
else
  echo "WORKER_API_URL=http://localhost:3000" >> "$ENV_FILE"
  success "Added WORKER_API_URL=http://localhost:3000 to .env.local"
fi

# ────────────────────────────────────────────────────────────────────────────
# FIX 3 — Tailwind v3 vs v4 CSS incompatibility
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Fix 3: Tailwind CSS compatibility ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PATCHES_DIR="$PROJECT_DIR/patches"
PATCH_FILE="$PATCHES_DIR/@renseiai__agentfactory-dashboard@0.8.18.patch"
GLOBALS_CSS="$PROJECT_DIR/src/app/globals.css"
LAYOUT_TSX="$PROJECT_DIR/src/app/layout.tsx"
PKG_JSON="$PROJECT_DIR/package.json"

# 3a — Create patch file ─────────────────────────────────────────────────────
mkdir -p "$PATCHES_DIR"

if [[ ! -f "$PATCH_FILE" ]]; then
  info "Creating pnpm patch for @renseiai/agentfactory-dashboard..."
  cat > "$PATCH_FILE" << 'PATCH'
diff --git a/src/styles/globals.css b/src/styles/globals.css
index 3925727dcf1e15ba1c0350ee8921aea894724d93..e15f161c784d49bc92bbcff229ed661c95b70588 100644
--- a/src/styles/globals.css
+++ b/src/styles/globals.css
@@ -1,7 +1,3 @@
-@tailwind base;
-@tailwind components;
-@tailwind utilities;
-
 @layer base {
   :root {
     --background: 222 55% 5%;
@@ -34,10 +30,11 @@

 @layer base {
   * {
-    @apply border-border;
+    border-color: hsl(var(--border));
   }
   body {
-    @apply bg-background text-foreground;
+    background-color: hsl(var(--background));
+    color: hsl(var(--foreground));
     font-feature-settings: "rlig" 1, "calt" 1, "ss01" 1;
     -webkit-font-smoothing: antialiased;
     -moz-osx-font-smoothing: grayscale;
PATCH
  success "Created $PATCH_FILE"
else
  success "Patch file already exists."
fi

# 3b — Register patch in package.json ────────────────────────────────────────
if ! python3 -c "import json,sys; d=json.load(open('$PKG_JSON')); sys.exit(0 if 'pnpm' in d else 1)" 2>/dev/null; then
  info "Adding pnpm.patchedDependencies to package.json..."
  python3 - "$PKG_JSON" << 'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
d.setdefault("pnpm", {})["patchedDependencies"] = {
    "@renseiai/agentfactory-dashboard@0.8.18":
        "patches/@renseiai__agentfactory-dashboard@0.8.18.patch"
}
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  success "Updated package.json with pnpm.patchedDependencies"
else
  success "pnpm.patchedDependencies already present in package.json"
fi

# 3c — Apply patch directly to the installed package ────────────────────────
DASHBOARD_INSTALLED=$(find "$PROJECT_DIR/node_modules/.pnpm" \
  -maxdepth 3 -type d \
  -name "@renseiai+agentfactory-dashboard@0.8.18*" 2>/dev/null | head -1)

if [[ -n "$DASHBOARD_INSTALLED" ]]; then
  DASHBOARD_CSS="$DASHBOARD_INSTALLED/node_modules/@renseiai/agentfactory-dashboard/src/styles/globals.css"
  if grep -q "@apply border-border" "$DASHBOARD_CSS" 2>/dev/null; then
    info "Applying patch to installed dashboard package..."
    patch -p1 \
      --directory="$DASHBOARD_INSTALLED/node_modules/@renseiai/agentfactory-dashboard" \
      --forward \
      < "$PATCH_FILE" && success "Patch applied to installed package." \
                      || warn "Patch failed or already applied — continuing."
  else
    success "Installed dashboard CSS already patched."
  fi
else
  warn "Could not find installed @renseiai/agentfactory-dashboard — run 'pnpm install' to install it."
fi

# 3d — Update globals.css ────────────────────────────────────────────────────
THEME_MARKER="@theme inline"

if ! grep -q "$THEME_MARKER" "$GLOBALS_CSS" 2>/dev/null; then
  info "Rewriting src/app/globals.css..."
  cat > "$GLOBALS_CSS" << 'CSS'
@import "tailwindcss";
@import "@renseiai/agentfactory-dashboard/styles";
@source "../../node_modules/@renseiai/agentfactory-dashboard/src";

@theme inline {
  --color-background: hsl(var(--background));
  --color-foreground: hsl(var(--foreground));
  --color-card: hsl(var(--card));
  --color-card-foreground: hsl(var(--card-foreground));
  --color-popover: hsl(var(--popover));
  --color-popover-foreground: hsl(var(--popover-foreground));
  --color-primary: hsl(var(--primary));
  --color-primary-foreground: hsl(var(--primary-foreground));
  --color-secondary: hsl(var(--secondary));
  --color-secondary-foreground: hsl(var(--secondary-foreground));
  --color-muted: hsl(var(--muted));
  --color-muted-foreground: hsl(var(--muted-foreground));
  --color-accent: hsl(var(--accent));
  --color-accent-foreground: hsl(var(--accent-foreground));
  --color-destructive: hsl(var(--destructive));
  --color-destructive-foreground: hsl(var(--destructive-foreground));
  --color-border: hsl(var(--border));
  --color-input: hsl(var(--input));
  --color-ring: hsl(var(--ring));
}
CSS
  success "Updated globals.css"
else
  success "globals.css already has @theme inline block."
fi

# 3e — Remove duplicate JS import from layout.tsx ───────────────────────────
if grep -q "agentfactory-dashboard/styles" "$LAYOUT_TSX" 2>/dev/null; then
  info "Removing duplicate dashboard styles import from layout.tsx..."
  sed -i "/import '@renseiai\/agentfactory-dashboard\/styles'/d" "$LAYOUT_TSX"
  sed -i '/import "@renseiai\/agentfactory-dashboard\/styles"/d' "$LAYOUT_TSX"
  success "Removed dashboard JS import from layout.tsx"
else
  success "layout.tsx already clean (no duplicate import)."
fi

# ────────────────────────────────────────────────────────────────────────────
# Final: clear Next.js cache so the server picks up all changes
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Clearing Next.js cache ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -d "$PROJECT_DIR/.next" ]]; then
  rm -rf "$PROJECT_DIR/.next"
  success "Cleared .next directory"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  All fixes applied."
echo ""
echo "  Next steps:"
echo "    1. cd $PROJECT_DIR"
echo "    2. pnpm dev          # start (or restart) the Next.js server"
echo "    3. pnpm worker       # in a second terminal"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
