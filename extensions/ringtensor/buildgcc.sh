#!/bin/bash
set -e

# تحديد المسارات
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
LIB_DIR="$ROOT/lib"
INCLUDE_DIR="$ROOT/language/include"

mkdir -p "$LIB_DIR"
mkdir -p "$ROOT/bin"

echo "🏗 Building RingTensor (Linux/Colab)..."
cd "$SCRIPT_DIR"

# 1. Try compilation with OpenCL GPU acceleration
if gcc -shared -o "$LIB_DIR/libring_tensor.so" -O3 -fPIC -fopenmp \
    ring_tensor.c \
    -I include \
    -I "$INCLUDE_DIR" \
    -L "$LIB_DIR" -Wl,-rpath,'$ORIGIN':-Wl,-rpath,'$ORIGIN/../lib' -lring -lOpenCL 2>/dev/null; then
    echo "  [OK] RingTensor compiled with OpenCL GPU acceleration."
else
    echo "  [INFO] OpenCL development libraries not found. Building RingTensor in High-Performance CPU Mode..."
    gcc -shared -o "$LIB_DIR/libring_tensor.so" -O3 -fPIC -fopenmp -DUSE_OPENCL=0 \
        ring_tensor.c \
        -I include \
        -I "$INCLUDE_DIR" \
        -L "$LIB_DIR" -Wl,-rpath,'$ORIGIN':-Wl,-rpath,'$ORIGIN/../lib' -lring
    echo "  [OK] RingTensor compiled with CPU SIMD / OpenMP acceleration."
fi

cp -f "$LIB_DIR/libring_tensor.so" "$ROOT/bin/libring_tensor.so" 2>/dev/null || true
cp -f "$LIB_DIR/libring_tensor.so" "$SCRIPT_DIR/libring_tensor.so" 2>/dev/null || true

echo "✅ RingTensor built successfully!"
