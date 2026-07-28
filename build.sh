#!/usr/bin/env bash
# Builds the Godot web export. Used as the Vercel build command, and works
# the same way locally.
#
# The engine is not vendored into this repository, so the build fetches the
# matching Godot editor binary and the web export template, then exports the
# project to ./build.

set -euo pipefail

GODOT_VERSION="4.3-stable"
GODOT_DIR="4.3.stable"
GODOT_BIN="Godot_v${GODOT_VERSION}_linux.x86_64"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}"
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_DIR}"

echo "==> fetching Godot ${GODOT_VERSION}"
if [ ! -x "./${GODOT_BIN}" ]; then
  curl -fsSL --retry 3 -o godot.zip "${BASE}/${GODOT_BIN}.zip"
  python3 -m zipfile -e godot.zip .
  chmod +x "./${GODOT_BIN}"
  rm -f godot.zip
fi

echo "==> fetching web export template"
if [ ! -f "${TEMPLATE_DIR}/web_release.zip" ]; then
  mkdir -p "${TEMPLATE_DIR}"
  # Only the web template is needed; the archive carries every platform.
  curl -fsSL --retry 3 -o templates.tpz \
    "${BASE}/Godot_v${GODOT_VERSION}_export_templates.tpz"
  python3 - "${TEMPLATE_DIR}" <<'PY'
import os, shutil, sys, zipfile
dest = sys.argv[1]
with zipfile.ZipFile("templates.tpz") as archive:
    for name in ("templates/web_release.zip", "templates/version.txt"):
        with archive.open(name) as src:
            with open(os.path.join(dest, os.path.basename(name)), "wb") as out:
                shutil.copyfileobj(src, out)
PY
  rm -f templates.tpz
fi

echo "==> importing project"
# The first import populates .godot and the global class cache. It reports a
# non-zero status on some platforms even when it succeeds.
"./${GODOT_BIN}" --headless --path . --import || true

echo "==> exporting web build"
mkdir -p build
"./${GODOT_BIN}" --headless --path . --export-release "Web" build/index.html

test -s build/index.wasm || { echo "export produced no wasm"; exit 1; }
test -s build/index.pck || { echo "export produced no pck"; exit 1; }

echo "==> done"
ls -la build
