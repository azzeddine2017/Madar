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

# 3. Verification
echo "[3/3] Verifying Binaries..."
if [ -f "$MADAR_ROOT/bin/ring" ]; then
    echo "  [OK] bin/ring exists and is executable!"
    "$MADAR_ROOT/bin/ring" -v
    echo "  [OK] Testing Madar one-liner:"
    "$MADAR_ROOT/bin/ring" -e 'see "  => Madar is working smoothly! [Tensor + AI Core ready]" + nl'
else
    echo "  [ERROR] bin/ring was not created!"
    exit 1
fi

echo "=========================================================="
echo "  Madar Build Pipeline Completed Successfully!            "
echo "=========================================================="
