/*
**  Madar Runtime Test Suite
**  Test Suite: Native Tensor Operator Overloading (+, -, *, /)
*/

load "../test_harness.ring"

suite("Madar Native Tensor Operator Overloading")

# ---------------------------------------------------------
# Test 1: Tensor + Tensor
# ---------------------------------------------------------
t1 = tensor_from_list([1.0, 2.0, 3.0, 4.0], "Float32")
t2 = tensor_from_list([10.0, 20.0, 30.0, 40.0], "Float32")

tAdd = t1 + t2
assert_true(istensor(tAdd), "t1 + t2 returns a valid Tensor")
assert_equal(11.0, tensor_get(tAdd, 1), "tAdd(1) = 1 + 10 = 11")
assert_equal(44.0, tensor_get(tAdd, 4), "tAdd(4) = 4 + 40 = 44")

# ---------------------------------------------------------
# Test 2: Tensor - Tensor
# ---------------------------------------------------------
tSub = t2 - t1
assert_true(istensor(tSub), "t2 - t1 returns a valid Tensor")
assert_equal(9.0, tensor_get(tSub, 1), "tSub(1) = 10 - 1 = 9")
assert_equal(36.0, tensor_get(tSub, 4), "tSub(4) = 40 - 4 = 36")

# ---------------------------------------------------------
# Test 3: Tensor * Tensor (Hadamard element-wise product)
# ---------------------------------------------------------
tMul = t1 * t2
assert_true(istensor(tMul), "t1 * t2 returns a valid Tensor")
assert_equal(10.0, tensor_get(tMul, 1), "tMul(1) = 1 * 10 = 10")
assert_equal(160.0, tensor_get(tMul, 4), "tMul(4) = 4 * 40 = 160")

# ---------------------------------------------------------
# Test 4: Tensor / Tensor
# ---------------------------------------------------------
tDiv = t2 / t1
assert_true(istensor(tDiv), "t2 / t1 returns a valid Tensor")
assert_equal(10.0, tensor_get(tDiv, 1), "tDiv(1) = 10 / 1 = 10")
assert_equal(10.0, tensor_get(tDiv, 4), "tDiv(4) = 40 / 4 = 10")

# ---------------------------------------------------------
# Test 5: Tensor * Scalar and Scalar * Tensor
# ---------------------------------------------------------
tScale1 = t1 * 3.0
assert_true(istensor(tScale1), "t1 * 3.0 returns a valid Tensor")
assert_equal(3.0, tensor_get(tScale1, 1), "tScale1(1) = 1 * 3 = 3")
assert_equal(12.0, tensor_get(tScale1, 4), "tScale1(4) = 4 * 3 = 12")

tScale2 = 3.0 * t1
assert_true(istensor(tScale2), "3.0 * t1 returns a valid Tensor")
assert_equal(3.0, tensor_get(tScale2, 1), "tScale2(1) = 3 * 1 = 3")
assert_equal(12.0, tensor_get(tScale2, 4), "tScale2(4) = 3 * 4 = 12")

# ---------------------------------------------------------
# Test 6: Tensor + Scalar and Scalar + Tensor
# ---------------------------------------------------------
tAddS1 = t1 + 5.0
assert_true(istensor(tAddS1), "t1 + 5.0 returns a valid Tensor")
assert_equal(6.0, tensor_get(tAddS1, 1), "tAddS1(1) = 1 + 5 = 6")
assert_equal(9.0, tensor_get(tAddS1, 4), "tAddS1(4) = 4 + 5 = 9")

tAddS2 = 5.0 + t1
assert_true(istensor(tAddS2), "5.0 + t1 returns a valid Tensor")
assert_equal(6.0, tensor_get(tAddS2, 1), "tAddS2(1) = 5 + 1 = 6")
assert_equal(9.0, tensor_get(tAddS2, 4), "tAddS2(4) = 5 + 4 = 9")

# ---------------------------------------------------------
# Test 7: Linear Combination Expression (2.0 * t1 + t2)
# ---------------------------------------------------------
y = 2.0 * t1 + t2
assert_true(istensor(y), "2.0 * t1 + t2 returns a valid Tensor")
assert_equal(12.0, tensor_get(y, 1), "y(1) = 2*1 + 10 = 12")
assert_equal(48.0, tensor_get(y, 4), "y(4) = 2*4 + 40 = 48")

test_summary()
