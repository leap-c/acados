#!/bin/bash
set -euo pipefail

TERA_VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/packages/leap_c_acados_runtime/leap_c_acados_runtime}"
SOURCE_DIR="${SOURCE_DIR:-}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *)             ARCH="amd64" ;;
esac

echo "=== Linux, Arch: $ARCH ==="

# --- Step 1: Obtain acados source ---
if [ -z "$SOURCE_DIR" ]; then
    echo "=== Cloning acados source ==="
    BUILD_TMP=$(mktemp -d)
    trap 'rm -rf "$BUILD_TMP"' EXIT
    git clone https://github.com/leap-c/acados.git "$BUILD_TMP" --depth 1
    cd "$BUILD_TMP"
    git submodule update --init --recursive --depth 1 external/blasfeo external/hpipm
    SOURCE_DIR="$BUILD_TMP"
fi

echo "=== Building acados from $SOURCE_DIR ==="

# --- Step 2: CMake build ---
cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DACADOS_WITH_OPENMP=ON \
    -DACADOS_NUM_THREADS=1

cmake --build "$SOURCE_DIR/build" --target install -- -j"$(nproc)"

# --- Diagnostic: check versioned symbols ---
echo "=== Symbol versions in built .so files ==="
for lib in "$SOURCE_DIR/lib/libacados.so" "$SOURCE_DIR/lib/libhpipm.so" "$SOURCE_DIR/lib/libblasfeo.so"; do
    echo "--- $(basename "$lib") ---"
    objdump -T "$lib" 2>/dev/null | grep -E 'GLIBC_|GLIBCXX_|CXXABI_' | sort -u || echo "  (none)"
done

echo "--- libgomp (if linked by libacados.so) ---"
ldd "$SOURCE_DIR/lib/libacados.so" 2>/dev/null | awk '/libgomp/ {print $3}' | while read -r gomp; do
    echo "  $gomp"
    objdump -T "$gomp" 2>/dev/null | grep -E 'GLIBC_|GLIBCXX_|CXXABI_' | sort -u
done

# --- Step 3: Copy libraries ---
echo "=== Copying libraries ==="
mkdir -p "$OUTPUT_DIR/lib"

cp "$SOURCE_DIR/lib/libacados.so" "$OUTPUT_DIR/lib/"
cp "$SOURCE_DIR/lib/libhpipm.so" "$OUTPUT_DIR/lib/"
cp "$SOURCE_DIR/lib/libblasfeo.so"* "$OUTPUT_DIR/lib/"
cp "$SOURCE_DIR/lib/link_libs.json" "$OUTPUT_DIR/lib/" 2>/dev/null || true
cp "$SOURCE_DIR/lib/git_commit_hash" "$OUTPUT_DIR/lib/" 2>/dev/null || true

echo "Libraries in $OUTPUT_DIR/lib:"
ls -la "$OUTPUT_DIR/lib/"

# --- Step 4: Copy headers ---
echo "=== Copying headers ==="
mkdir -p "$OUTPUT_DIR/include"

for dir in acados acados_c; do
    if [ -d "$SOURCE_DIR/include/$dir" ]; then
        cp -r "$SOURCE_DIR/include/$dir" "$OUTPUT_DIR/include/"
    fi
done

if [ -d "$SOURCE_DIR/include/blasfeo" ]; then
    mkdir -p "$OUTPUT_DIR/include/blasfeo"
    cp -r "$SOURCE_DIR/include/blasfeo/"* "$OUTPUT_DIR/include/blasfeo/"
fi
if [ -d "$SOURCE_DIR/include/hpipm" ]; then
    mkdir -p "$OUTPUT_DIR/include/hpipm"
    cp -r "$SOURCE_DIR/include/hpipm/"* "$OUTPUT_DIR/include/hpipm/"
fi

# --- Step 5: Download Tera renderer ---
echo "=== Downloading Tera renderer v$TERA_VERSION ==="
mkdir -p "$OUTPUT_DIR/bin"

TERA_URL="https://github.com/acados/tera_renderer/releases/download/v${TERA_VERSION}/t_renderer-v${TERA_VERSION}-linux-${ARCH}"

curl -fSL -o "$OUTPUT_DIR/bin/t_renderer" "$TERA_URL" || {
    echo "WARNING: Failed to download Tera renderer from $TERA_URL"
    echo "Tera renderer will need to be installed manually."
}
chmod +x "$OUTPUT_DIR/bin/t_renderer"

echo "=== Build complete ==="
