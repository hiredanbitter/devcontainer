# AgentFactory Worker Setup — Issues & Fixes

This document describes three bugs that prevent `pnpm worker` from connecting to the
coordinator. Apply all three fixes in the `agentfactory/my-agent` directory.

---

## Issue 1 — CSS Compilation Error (500 on all API routes)

### Symptom
Every API route (including `/api/workers/register`) returns an HTML 500 page
instead of JSON. The Next.js dev terminal shows:

```
CssSyntaxError: tailwindcss: .../agentfactory-dashboard/.../globals.css:1:1:
Cannot apply unknown utility class `border-border`.
```

The `pnpm worker` log shows:
```
ERR API request failed: /api/workers/register { status=500, body=<!DOCTYPE html>... }
```

### Root Cause
`@renseiai/agentfactory-dashboard` ships CSS written for **Tailwind v3**. It uses:
- `@tailwind base;` / `@tailwind components;` / `@tailwind utilities;` (v3 directives)
- `@apply border-border;` and `@apply bg-background text-foreground;` (shadcn custom utilities)

The project uses **Tailwind v4**, which does not recognise these v3 directives or the
shadcn custom utilities out of the box. This causes a PostCSS/Turbopack compile error
that makes every HTTP response return an HTML 500 error page.

### Files Involved
- `node_modules/@renseiai/agentfactory-dashboard/src/styles/globals.css` — broken CSS
- `src/app/layout.tsx` — was importing the broken CSS as a JS module
- `src/app/globals.css` — project Tailwind entry point
- `package.json` — needs `pnpm.patchedDependencies`
- `patches/@renseiai__agentfactory-dashboard@0.8.18.patch` — the patch file (created by fix)

### Fix

**Step 1 — Create a pnpm patch** that replaces the `@apply` calls with direct CSS
properties and removes the v3 `@tailwind` directives.

Create `patches/@renseiai__agentfactory-dashboard@0.8.18.patch`:
```diff
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
```

**Step 2 — Register the patch** in `package.json` (add a `"pnpm"` top-level key):
```json
"pnpm": {
  "patchedDependencies": {
    "@renseiai/agentfactory-dashboard@0.8.18": "patches/@renseiai__agentfactory-dashboard@0.8.18.patch"
  }
}
```

**Step 3 — Move the dashboard CSS import** from JavaScript to CSS so it shares the
same Tailwind v4 processing context.

In `src/app/layout.tsx`, **remove** this line:
```ts
import '@renseiai/agentfactory-dashboard/styles'
```

In `src/app/globals.css`, **add** the CSS `@import` and the `@theme inline` block so
Tailwind v4 generates the shadcn colour utilities (`border-border`, `bg-background`, etc.):
```css
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
```

**Step 4 — Apply the patch** and apply it to the installed package:
```bash
pnpm install
# If the lockfile prevents re-install, apply directly:
patch -p1 \
  --directory=node_modules/.pnpm/@renseiai+agentfactory-dashboard@0.8.18*/node_modules/@renseiai/agentfactory-dashboard \
  < patches/@renseiai__agentfactory-dashboard@0.8.18.patch
```

**Step 5 — Restart** the Next.js dev server (it must be restarted; Turbopack caches
`node_modules` and will not pick up the patch without a full restart):
```bash
# In the terminal running `pnpm dev`, Ctrl+C then:
rm -rf .next
pnpm dev
```

---

## Issue 2 — Worker API URL double-prefixed (404 on /api/workers/register)

### Symptom
After the CSS fix, `pnpm worker` gets an HTML 404 instead of 401/201:
```
ERR API request failed: /api/workers/register { status=404, body=<!DOCTYPE html>... }
```

### Root Cause
The worker library (`@renseiai/agentfactory-cli`) constructs the full URL as:
```
{WORKER_API_URL}{path}
```
where `path` is `/api/workers/register` (already includes `/api`).

If `.env.local` sets `WORKER_API_URL=http://localhost:3000/api`, the resulting URL is:
```
http://localhost:3000/api/api/workers/register   ← double /api, route not found
```

### Files Involved
- `.env.local` — `WORKER_API_URL` value

### Fix
In `.env.local`, change:
```
WORKER_API_URL=http://localhost:3000/api
```
to:
```
WORKER_API_URL=http://localhost:3000
```

---

## Issue 3 — Redis not installed or not running (500 inside register handler)

### Symptom
The register endpoint returns 503 JSON (`"Failed to register worker"`) or the server
logs show Redis connection errors.

### Root Cause
The worker storage layer uses Redis for all worker state. If Redis is not installed or
not running, `registerWorker()` returns `null` and the API returns 503.

### Files Involved
- `.env.local` — must contain `REDIS_URL=redis://localhost:6379`
- System — Redis service must be running

### Fix
```bash
# Install Redis (Debian/Ubuntu)
sudo apt-get install -y redis-server

# Start Redis
sudo service redis-server start
# or
redis-server --daemonize yes

# Verify
redis-cli ping   # should return PONG
```

Ensure `.env.local` contains:
```
REDIS_URL=redis://localhost:6379
```

---

## Summary of all changed files

| File | Change |
|------|--------|
| `patches/@renseiai__agentfactory-dashboard@0.8.18.patch` | Created — removes v3 Tailwind directives and replaces `@apply` with direct CSS |
| `package.json` | Added `pnpm.patchedDependencies` to register the patch |
| `src/app/globals.css` | Added CSS `@import` for dashboard styles + `@theme inline` colour tokens |
| `src/app/layout.tsx` | Removed `import '@renseiai/agentfactory-dashboard/styles'` |
| `.env.local` | `WORKER_API_URL` changed from `http://localhost:3000/api` to `http://localhost:3000` |

---

## Verification

After all fixes, with `pnpm dev` and Redis running:
```bash
pnpm worker
# Expected output:
# INF Configuration { apiUrl=http://localhost:3000, ... }
# INF Registering with coordinator
# ✓ REGISTERED Worker ID: <id>
# INF Polling for work...
```
