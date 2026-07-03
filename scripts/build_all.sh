#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Building leap-c-acados pip packages ==="

echo ""
echo "=== Step 1: Sync template ==="
bash "$SCRIPT_DIR/sync_template.sh"

echo ""
echo "=== Step 2: Build C libraries ==="
bash "$SCRIPT_DIR/build_acados_c.sh"

echo ""
echo "=== Step 3: Build wheels ==="

echo "Building leap-c-acados-runtime..."
python3 -m build --wheel "$REPO_ROOT/packages/leap_c_acados_runtime"

echo "Building leap-c-acados..."
python3 -m build --wheel "$REPO_ROOT/packages/leap_c_acados"

echo ""
echo "=== Done ==="
echo "Wheels:"
ls -la "$REPO_ROOT/packages/leap_c_acados_runtime/dist/" "$REPO_ROOT/packages/leap_c_acados/dist/" 2>/dev/null || true
