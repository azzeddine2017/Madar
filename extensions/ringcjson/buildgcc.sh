#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
LIB_DIR="$ROOT/lib"
BIN_DIR="$ROOT/bin"
INCLUDE_DIR="$ROOT/language/include"

mkdir -p "$LIB_DIR"
mkdir -p "$BIN_DIR"

cd "$SCRIPT_DIR"
gcc -c -fpic -O2 ring_cjson.c lib/cJSON.c lib/cJSON_Utils.c -I "$INCLUDE_DIR"
gcc -shared -o "$LIB_DIR/libring_cjson.so" ring_cjson.o cJSON.o cJSON_Utils.o \
    -L "$LIB_DIR" -Wl,-rpath,'$ORIGIN':-Wl,-rpath,'$ORIGIN/../lib' -lring

cp -f "$LIB_DIR/libring_cjson.so" "$BIN_DIR/libring_cjson.so" 2>/dev/null || true
cp -f "$LIB_DIR/libring_cjson.so" "$SCRIPT_DIR/libring_cjson.so" 2>/dev/null || true
rm -f ring_cjson.o cJSON.o cJSON_Utils.o

echo "  [OK] RingCJSON built successfully!"
