/*
**  Madar Runtime Test Suite
**  Test Suite: Embedded GGML Core & Half-Precision FP16
*/

load "../test_harness.ring"

suite("Madar GGML Core Integration")

# ---------------------------------------------------------
# Test 1: GGML Version Identifier
# ---------------------------------------------------------
ver = ggml_version()
assert_true(len(ver) > 0, "ggml_version returns non-empty string")
assert_equal(ver, "GGML Core (ANSI C99 Embedded)", "ggml_version matches expected identifier")

# ---------------------------------------------------------
# Test 2: Half-Precision FP16 Conversions
# ---------------------------------------------------------
val = 3.14159
h = ggml_fp32_to_fp16(val)
assert_true(h > 0, "FP16 representation of 3.14159 is non-zero")

roundtrip = ggml_fp16_to_fp32(h)
diff = fabs(roundtrip - val)
assert_true(diff < 0.005, "FP16 roundtrip preserves value within half-precision tolerance")

# ---------------------------------------------------------
# Test 3: FP16 Zero and Negative Values
# ---------------------------------------------------------
hZero = ggml_fp32_to_fp16(0.0)
assert_equal(0.0, ggml_fp16_to_fp32(hZero), "FP16 handles 0.0 correctly")

hNeg = ggml_fp32_to_fp16(-42.5)
assert_equal(-42.5, ggml_fp16_to_fp32(hNeg), "FP16 handles -42.5 correctly")

test_summary()
