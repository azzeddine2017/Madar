#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MADAR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"

echo "  - Compiling AlQalam C++ extension (libalqalam.so)..."
g++ -c -fPIC -O3 -std=c++20 alqalam.cpp -I"$MADAR_ROOT/language/include"

echo "  - Linking libalqalam.so..."
g++ -shared -o "$MADAR_ROOT/lib/libalqalam.so" alqalam.o -L"$MADAR_ROOT/lib" -lring -lpthread

mkdir -p "$MADAR_ROOT/bin"
cp "$MADAR_ROOT/lib/libalqalam.so" "$MADAR_ROOT/bin/libalqalam.so" 2>/dev/null || true
cp "$MADAR_ROOT/lib/libalqalam.so" "$MADAR_ROOT/bin/alqalam.so" 2>/dev/null || true

rm -f alqalam.o

echo "  - [OK] AlQalam extension built successfully!"
