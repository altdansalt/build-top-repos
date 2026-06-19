#!/bin/sh
# Black-box smoke: verify the astro CLI and its WASM compiler work end-to-end.
# $PROJECT = restored build tree (packages/astro/dist/ populated by pnpm/turbo build).
set -e

export ASTRO_TELEMETRY_DISABLED=1

# Run from the workspace root so Node resolves all workspace node_modules.
cd "$PROJECT"

# 1. Version check — confirms the CLI entry and dist/cli/index.js compiled OK.
node packages/astro/bin/astro.mjs --version

# 2. Build a minimal zero-import static site to exercise the Astro compiler
#    (@astrojs/compiler-rs WASM) + Vite pipeline.
#
#    pnpm does not link workspace packages (like astro) into their own workspace
#    root node_modules; we create the symlink manually so Vite can resolve
#    astro/entrypoints/prerender and similar framework entry points.
SITE=$(mktemp -d)
mkdir -p "$SITE/src/pages" "$SITE/node_modules"
ln -s "$PROJECT/packages/astro" "$SITE/node_modules/astro"

cat > "$SITE/src/pages/index.astro" << 'EOF'
---
---
<!doctype html>
<html>
  <head><title>Smoke Test</title></head>
  <body><h1>Hello Astro!</h1></body>
</html>
EOF

cat > "$SITE/package.json" << 'EOF'
{"name":"smoke","type":"module"}
EOF

# Build with --root so pages and output are rooted at $SITE, not CWD.
node packages/astro/bin/astro.mjs build --root "$SITE"

test -f "$SITE/dist/index.html"
grep -q "Hello Astro" "$SITE/dist/index.html"
echo "ASTRO_SMOKE_OK"
