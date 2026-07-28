#!/usr/bin/env bash
# Builds the web export and ships the finished static site to Vercel.
#
# This deploys the *output* rather than the source, so Vercel never has to
# download the Godot toolchain and each deploy takes seconds instead of
# minutes. Run it from the repository root.
#
#   bash ship.sh              # production deploy
#   bash ship.sh --preview    # shareable preview URL instead
#
# Requires the Vercel CLI and a logged-in account:
#   npm i -g vercel && vercel login

set -euo pipefail

TARGET="--prod"
if [ "${1:-}" = "--preview" ]; then
  TARGET=""
fi

echo "==> building the web export"
bash build.sh

echo "==> writing deploy config"
# The build directory is deployed as-is, so it needs its own config. The two
# cross-origin headers are not optional: without them the browser refuses
# SharedArrayBuffer and the threaded Godot build cannot start.
cat > build/vercel.json <<'JSON'
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" },
        { "key": "Cross-Origin-Embedder-Policy", "value": "require-corp" },
        { "key": "Cross-Origin-Resource-Policy", "value": "cross-origin" }
      ]
    },
    {
      "source": "/index.html",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }
      ]
    },
    {
      "source": "/(.*).(wasm|pck)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=3600" }
      ]
    }
  ]
}
JSON

# Godot's exporter leaves this behind; it must not ship.
rm -f build/.gdignore

echo "==> deploying to Vercel"
cd build
vercel deploy $TARGET --yes

echo
echo "Done. If the page loads but the engine never starts, open the console and"
echo "check crossOriginIsolated is true - that means the headers above applied."
