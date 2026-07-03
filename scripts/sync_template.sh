#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/interfaces/acados_template/acados_template"
DST="$REPO_ROOT/packages/acados/acados"

echo "=== Setting up acados package symlink ==="

if [ -L "$DST" ] && [ -d "$DST" ]; then
    echo "Symlink already exists: $DST -> $(readlink "$DST")"
else
    rm -rf "$DST"
    ln -s "../../interfaces/acados_template/acados_template" "$DST"
    echo "Created symlink: $DST -> $SRC"
fi
