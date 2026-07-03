#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Building acados pip packages ==="

# Step 1: Sync Python template to acados package
echo ""
echo "=== Step 1: Sync template ==="
bash "$SCRIPT_DIR/sync_template.sh"

# Step 2: Build C libraries and bundle into acados-runtime
echo ""
echo "=== Step 2: Build C libraries ==="
bash "$SCRIPT_DIR/build_acados_c.sh"

# Step 3: Build wheels
echo ""
echo "=== Step 3: Build wheels ==="

# Build acados-runtime platform wheel
echo "Building acados-runtime..."
python3 -m build --wheel "$REPO_ROOT/packages/acados_runtime"

# Build acados noarch wheel
echo "Building acados..."
python3 -m build --wheel "$REPO_ROOT/packages/acados"

echo ""
echo "=== Done ==="
echo "Wheels:"
ls -la "$REPO_ROOT/packages/acados_runtime/dist/" "$REPO_ROOT/packages/acados/dist/" 2>/dev/null || true
