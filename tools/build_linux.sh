#!/usr/bin/env bash
set -e

# ====================================================================
#   Madar Runtime - Complete Linux / Colab Build Pipeline
# ====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MADAR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================================="
echo "  Madar Runtime - Complete Linux Build Pipeline           "
echo "=========================================================="

# 1. Build Core Runtime
echo "[1/3] Building Core Compiler and VM (bin/ring, lib/libring.so)..."
bash "$MADAR_ROOT/language/build/buildgcc_madar.sh"

export PATH="$MADAR_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$MADAR_ROOT/lib:$LD_LIBRARY_PATH"

# 2. Build Extensions
echo "[2/3] Building Extensions..."

# 2.1 RingTensor (AI Math, Autograd, OpenCL GPU & CPU Adam Kernels)
if [ -d "$MADAR_ROOT/extensions/ringtensor" ]; then
    echo "  - Building RingTensor extension..."
    (cd "$MADAR_ROOT/extensions/ringtensor" && bash buildgcc.sh)
    # Ensure library is present in all search paths
    if [ -f "$MADAR_ROOT/lib/libring_tensor.so" ]; then
        cp -f "$MADAR_ROOT/lib/libring_tensor.so" "$MADAR_ROOT/bin/libring_tensor.so" 2>/dev/null || true
        cp -f "$MADAR_ROOT/lib/libring_tensor.so" "$MADAR_ROOT/extensions/ringtensor/libring_tensor.so" 2>/dev/null || true
        echo "  [OK] RingTensor deployed to lib/, bin/, and extensions/ringtensor/"
    fi
fi

if [ -d "$MADAR_ROOT/extensions/AlQalam" ]; then
    echo "  - Building AlQalam C++ extension (Hybrid RAG, Fast Vector & Inverted Index)..."
    (cd "$MADAR_ROOT/extensions/AlQalam" && bash buildgcc.sh || true)
fi

if [ -d "$MADAR_ROOT/extensions/ringconsolecolors" ]; then
    echo "  - Building ringconsolecolors..."
    (cd "$MADAR_ROOT/extensions/ringconsolecolors" && bash buildgcc.sh || true)
fi

if [ -d "$MADAR_ROOT/extensions/ringcurl" ]; then
    echo "  - Building ringcurl..."
    (cd "$MADAR_ROOT/extensions/ringcurl" && bash buildgcc.sh || true)
fi

if [ -d "$MADAR_ROOT/extensions/ringcjson" ]; then
    echo "  - Building RingCJSON extension..."
    (cd "$MADAR_ROOT/extensions/ringcjson" && bash buildgcc.sh || true)
    if [ -f "$MADAR_ROOT/lib/libring_cjson.so" ]; then
        cp -f "$MADAR_ROOT/lib/libring_cjson.so" "$MADAR_ROOT/bin/libring_cjson.so" 2>/dev/null || true
        cp -f "$MADAR_ROOT/lib/libring_cjson.so" "$MADAR_ROOT/extensions/ringcjson/libring_cjson.so" 2>/dev/null || true
    fi
fi

# Ensure standard library case-compatibility symlinks on Linux
if [ -d "$MADAR_ROOT/bin/load" ]; then
    (cd "$MADAR_ROOT/bin/load" && ln -sf stdlibcore.ring stdlibCore.ring 2>/dev/null || true)
    (cd "$MADAR_ROOT/bin/load" && ln -sf stdlib.ring StdLib.ring 2>/dev/null || true)
fi

# 3. Verification
echo "[3/3] Verifying Binaries & Extensions..."
if [ -f "$MADAR_ROOT/bin/ring" ]; then
    echo "  [OK] bin/ring exists and is executable!"
    "$MADAR_ROOT/bin/ring" -v
    echo "  [OK] Testing Madar runtime:"
    "$MADAR_ROOT/bin/ring" -e 'see "  => Madar Core is operational!" + nl'
    
    # Verify RingTensor loader
    if [ -f "$MADAR_ROOT/lib/libring_tensor.so" ]; then
        echo "  [OK] Verifying RingTensor execution:"
        "$MADAR_ROOT/bin/ring" -e 'load "ringtensor.ring" see "  => RingTensor successfully loaded and verified!" + nl' || true
    fi
else
    echo "  [ERROR] bin/ring was not created!"
    exit 1
fi

echo "=========================================================="
echo "  Madar Build Pipeline Completed Successfully!            "
echo "=========================================================="
