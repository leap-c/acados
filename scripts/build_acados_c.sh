#!/bin/bash
set -euo pipefail

TERA_VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/packages/leap_c_acados_runtime/leap_c_acados_runtime}"
SOURCE_DIR="${SOURCE_DIR:-}"

detect_platform() {
    case "$(uname -s)" in
        Linux)  echo "linux" ;;
        Darwin) echo "darwin" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)      echo "unknown" ;;
    esac
}

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo "amd64" ;;
    esac
}

PLATFORM=$(detect_platform)
ARCH=$(detect_arch)

echo "=== Platform: $PLATFORM, Arch: $ARCH ==="

# --- Shared library helpers ---
if [ "$PLATFORM" = "windows" ]; then
    SHLIB_EXT=".dll"
    SHLIB_PREFIX=""
    CMAKE_EXTRA_FLAGS="-DBUILD_SHARED_LIBS=ON -DBLASFEO_TARGET=GENERIC"
elif [ "$PLATFORM" = "darwin" ]; then
    SHLIB_EXT=".dylib"
    SHLIB_PREFIX="lib"
    CMAKE_EXTRA_FLAGS="-DCMAKE_OSX_ARCHITECTURES=\"x86_64;arm64\""
else
    SHLIB_EXT=".so"
    SHLIB_PREFIX="lib"
    CMAKE_EXTRA_FLAGS=""
fi

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
    -DACADOS_NUM_THREADS=1 \
    $CMAKE_EXTRA_FLAGS

cmake --build "$SOURCE_DIR/build" --target install -- -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# --- Step 3: Copy libraries ---
echo "=== Copying libraries ==="
mkdir -p "$OUTPUT_DIR/lib"

cp "$SOURCE_DIR/lib/${SHLIB_PREFIX}acados${SHLIB_EXT}" "$OUTPUT_DIR/lib/" 2>/dev/null || true
cp "$SOURCE_DIR/lib/${SHLIB_PREFIX}hpipm${SHLIB_EXT}" "$OUTPUT_DIR/lib/" 2>/dev/null || true

# blasfeo has a versioned .so on Linux
if [ "$PLATFORM" = "linux" ]; then
    cp "$SOURCE_DIR/lib/libblasfeo.so"* "$OUTPUT_DIR/lib/" 2>/dev/null || true
else
    cp "$SOURCE_DIR/lib/${SHLIB_PREFIX}blasfeo${SHLIB_EXT}" "$OUTPUT_DIR/lib/" 2>/dev/null || true
fi

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

# blasfeo and hpipm headers are at include/blasfeo/include and include/hpipm/include
if [ -d "$SOURCE_DIR/include/blasfeo" ]; then
    mkdir -p "$OUTPUT_DIR/include/blasfeo"
    cp -r "$SOURCE_DIR/include/blasfeo/"* "$OUTPUT_DIR/include/blasfeo/"
fi
if [ -d "$SOURCE_DIR/include/hpipm" ]; then
    mkdir -p "$OUTPUT_DIR/include/hpipm"
    cp -r "$SOURCE_DIR/include/hpipm/"* "$OUTPUT_DIR/include/hpipm/"
fi

echo "Headers in $OUTPUT_DIR/include:"
find "$OUTPUT_DIR/include" -type d | head -20

# --- Step 5: Download Tera renderer ---
echo "=== Downloading Tera renderer v$TERA_VERSION ==="
mkdir -p "$OUTPUT_DIR/bin"

TERA_PLATFORM=""
case "$PLATFORM" in
    linux)   TERA_PLATFORM="linux" ;;
    darwin)  TERA_PLATFORM="osx" ;;
    windows) TERA_PLATFORM="windows" ;;
esac

TERA_ARCH="$ARCH"
TERA_EXT=""
if [ "$PLATFORM" = "windows" ]; then
    TERA_EXT=".exe"
fi

TERA_URL="https://github.com/acados/tera_renderer/releases/download/v${TERA_VERSION}/t_renderer-v${TERA_VERSION}-${TERA_PLATFORM}-${TERA_ARCH}${TERA_EXT}"
echo "Downloading: $TERA_URL"

curl -fSL -o "$OUTPUT_DIR/bin/t_renderer${TERA_EXT}" "$TERA_URL" || {
    echo "WARNING: Failed to download Tera renderer from $TERA_URL"
    echo "Tera renderer will need to be installed manually."
}
chmod +x "$OUTPUT_DIR/bin/t_renderer${TERA_EXT}" 2>/dev/null || true

echo "=== Build complete ==="
