#!/usr/bin/env bash
set -e

# ====================================================================
#   Madar AI Runtime - Linux GCC Build Script (with AVX2 & OpenCL)
# ====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MADAR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$MADAR_ROOT/language/src"
INC_DIR="$MADAR_ROOT/language/include"
LIB_DIR="$MADAR_ROOT/lib"
BIN_DIR="$MADAR_ROOT/bin"

mkdir -p "$LIB_DIR"
mkdir -p "$BIN_DIR"

cd "$SRC_DIR"

echo "=========================================================="
echo "  Building Madar Core Runtime (AVX2 + FMA + SIMD + POSIX) "
echo "=========================================================="

CFLAGS="-c -fPIC -O3 -mavx2 -mfma -mf16c -pthread -I$INC_DIR -I$SRC_DIR"

# Core source files
OBJS="general.o state.o ext.o hashlib.o rhtable.o vmgc.o os_e.o rstring.o \
rlist.o ritem.o ritems.o scanner.o parser.o stmt.o expr.o codegen.o vm.o \
vmerror.o vmeval.o vmthread.o vmexpr.o vmvars.o vmlists.o vmfuncs.o ringapi.o \
vmoop.o vmtry.o vmstr.o vmjump.o vmrange.o list_e.o meta_e.o vminfo_e.o \
vmperf.o vmexit.o vmstack.o vmstate.o genlib_e.o math_e.o file_e.o dll_e.o \
objfile.o ring_tensor.o ring_gguf.o ring_tokenizer.o ring_inference.o \
ring_diagnostics.o ggml.o ring_jit.o vmcgoto.o"

echo "[1/4] Compiling C source files with GCC..."
gcc $CFLAGS \
    general.c state.c ext.c hashlib.c rhtable.c vmgc.c os_e.c rstring.c \
    rlist.c ritem.c ritems.c scanner.c parser.c stmt.c expr.c codegen.c vm.c \
    vmerror.c vmeval.c vmthread.c vmexpr.c vmvars.c vmlists.c vmfuncs.c ringapi.c \
    vmoop.c vmtry.c vmstr.c vmjump.c vmrange.c list_e.c meta_e.c vminfo_e.c \
    vmperf.c vmexit.c vmstack.c vmstate.c genlib_e.c math_e.c file_e.c dll_e.c \
    objfile.c ring_tensor.c ring_gguf.c ring_tokenizer.c ring_inference.c \
    ring_diagnostics.c ggml.c ring_jit.c vmcgoto.c

echo "[2/4] Linking dynamic shared library (libring.so)..."
gcc -shared -o "$LIB_DIR/libring.so" $OBJS -lm -ldl -lpthread

echo "[3/4] Creating static library (libringstatic.a)..."
ar rcs "$LIB_DIR/libringstatic.a" $OBJS

echo "[4/4] Compiling executable runner (bin/ring)..."
gcc -O3 -mavx2 -mfma -mf16c -rdynamic ring.c -o "$BIN_DIR/ring" \
    -L"$LIB_DIR" -lring -lm -ldl -lpthread -I"$INC_DIR" -Wl,-rpath,'$ORIGIN/../lib'

# Cleanup object files
rm -f *.o

chmod +x "$BIN_DIR/ring"

echo "=========================================================="
echo "  Madar Core Runtime built successfully! -> $BIN_DIR/ring"
echo "=========================================================="
