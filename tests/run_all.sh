#!/usr/bin/env bash
# ==========================================================
# Madar Test Suite Runner (Linux / macOS / Google Colab)
# Executes all unit tests for Core, Tensors, AI, and AlQalam
# ==========================================================

set -e

# Detect directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MADAR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RING_BIN="$MADAR_ROOT/bin/ring"

# Ensure runtime binary exists
if [ ! -x "$RING_BIN" ]; then
    echo -e "\033[1;31m[ERROR] $RING_BIN not found or not executable!\033[0m"
    echo "Please build Madar first using: bash tools/build_linux.sh"
    exit 1
fi

# Export shared libraries path
export LD_LIBRARY_PATH="$MADAR_ROOT/lib:$MADAR_ROOT/bin:$LD_LIBRARY_PATH"

echo "=========================================================="
echo "  🪐 Madar Automated Test Suite Runner"
echo "  Binary  : $RING_BIN"
echo "  Platform: $(uname -s) $(uname -m)"
echo "=========================================================="
echo ""

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

run_test() {
    local dir="$1"
    local file="$2"
    local label="$3"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo -e "\033[1;34m▶ Running [$label]: $file ...\033[0m"
    
    pushd "$dir" > /dev/null
    if "$RING_BIN" "$file"; then
        echo -e "\033[1;32m✔ [$label] $file PASSED\033[0m\n"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        echo -e "\033[1;31m✘ [$label] $file FAILED\033[0m\n"
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
    popd > /dev/null
}

# ----------------------------------------------------------
# 1. Core Dialect & Syntactic Enhancements
# ----------------------------------------------------------
echo "=== [1/3] Core Dialect & Runtime Tests ==="
run_test "$SCRIPT_DIR/core" "test_backward_compat.ring"   "CORE"
run_test "$SCRIPT_DIR/core" "test_fstrings.ring"          "CORE"
run_test "$SCRIPT_DIR/core" "test_default_args.ring"      "CORE"
run_test "$SCRIPT_DIR/core" "test_slicing.ring"           "CORE"
run_test "$SCRIPT_DIR/core" "test_comprehensions.ring"    "CORE"
run_test "$SCRIPT_DIR/core" "test_dour.ring"              "CORE"
run_test "$SCRIPT_DIR/core" "test_arabic_utf8.ring"       "CORE"
run_test "$SCRIPT_DIR/core" "test_try_catch_context.ring" "CORE"
run_test "$SCRIPT_DIR/core" "test_nanotime.ring"          "CORE"
run_test "$SCRIPT_DIR/core" "test_async_native.ring"      "CORE"
run_test "$SCRIPT_DIR/core" "test_json_errors.ring"       "CORE"

# ----------------------------------------------------------
# 2. Native Tensor Engine & GGUF Loader Tests
# ----------------------------------------------------------
echo "=== [2/3] Tensor & GGUF Loader Tests ==="
run_test "$SCRIPT_DIR/tensor" "test_tensor_operations.ring" "TENSOR"
run_test "$SCRIPT_DIR/tensor" "test_tensor_math.ring"       "TENSOR"
run_test "$SCRIPT_DIR/tensor" "test_tensor_operators.ring"  "TENSOR"
run_test "$SCRIPT_DIR/tensor" "test_ggml.ring"              "TENSOR"
run_test "$SCRIPT_DIR/tensor" "test_gguf_loader.ring"       "TENSOR"

# ----------------------------------------------------------
# 3. AI Engine & BPE Tokenizer Synthetic Tests
# ----------------------------------------------------------
echo "=== [3/3] AI Engine & Tokenizer Tests ==="
run_test "$SCRIPT_DIR/ai" "test_qwen.ring" "AI"

# Clean up temporary test files if generated
rm -f "$SCRIPT_DIR/ai/test_tok.gguf"

# Summary
echo "=========================================================="
echo "  🏁 Test Execution Summary"
echo "  Total Suites : $TOTAL_SUITES"
echo -e "  Passed       : \033[1;32m$PASSED_SUITES\033[0m"
if [ "$FAILED_SUITES" -gt 0 ]; then
    echo -e "  Failed       : \033[1;31m$FAILED_SUITES\033[0m"
    echo "=========================================================="
    exit 1
else
    echo -e "  Failed       : 0"
    echo -e "\033[1;32m🎉 ALL TEST SUITES PASSED SUCCESSFULLY!\033[0m"
    echo "=========================================================="
    exit 0
fi
