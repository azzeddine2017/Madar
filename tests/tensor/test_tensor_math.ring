/*
**  Madar Runtime Test Suite
**  Test Suite: Native Tensor Math, Indexing, Activations & GEMM
*/

load "../test_harness.ring"

suite("Madar Tensor Math, Indexing, Activations & GEMM")

# ---------------------------------------------------------
# Test 1: Element Access, Indexing & Mutation
# ---------------------------------------------------------
t = tensor([2, 3], "Float32")
tensor_fill(t, 7.0)

assert_equal(tensor_get(t, 1, 1), 7.0, "tensor_fill sets (1, 1) to 7.0")
assert_equal(tensor_get(t, 2, 3), 7.0, "tensor_fill sets (2, 3) to 7.0")

# Mutation using varargs
tensor_set(t, 1, 2, 99.0)
assert_equal(tensor_get(t, 1, 2), 99.0, "tensor_set with varargs updates element")

# Mutation and access using list
tensor_set(t, [2, 1], 42.0)
assert_equal(tensor_get(t, [2, 1]), 42.0, "tensor_set with list updates element")
assert_equal(tensor_get(t, 2, 1), 42.0, "tensor_get with varargs reads list-set element")

# ---------------------------------------------------------
# Test 2: Element-wise Arithmetic
# ---------------------------------------------------------
listA = [1.0, 2.0, 3.0, 4.0]
listB = [10.0, 20.0, 30.0, 40.0]

tA = tensor_from_list(listA, "Float32")
tB = tensor_from_list(listB, "Float32")

# Addition
tAdd = tensor_add(tA, tB)
assert_true(istensor(tAdd), "tensor_add returns a valid tensor")
assert_equal(tensor_get(tAdd, 1), 11.0, "Addition element 1: 1 + 10 = 11")
assert_equal(tensor_get(tAdd, 4), 44.0, "Addition element 4: 4 + 40 = 44")

# Subtraction
tSub = tensor_sub(tB, tA)
assert_equal(tensor_get(tSub, 1), 9.0, "Subtraction element 1: 10 - 1 = 9")
assert_equal(tensor_get(tSub, 4), 36.0, "Subtraction element 4: 40 - 4 = 36")

# Multiplication (Hadamard product)
tMul = tensor_mul(tA, tB)
assert_equal(tensor_get(tMul, 2), 40.0, "Multiplication element 2: 2 * 20 = 40")
assert_equal(tensor_get(tMul, 3), 90.0, "Multiplication element 3: 3 * 30 = 90")

# Division
tDiv = tensor_div(tB, tA)
assert_equal(tensor_get(tDiv, 1), 10.0, "Division element 1: 10 / 1 = 10")
assert_equal(tensor_get(tDiv, 4), 10.0, "Division element 4: 40 / 4 = 10")

# Scalar Scale & Add
tScale = tensor_scale(tA, 3.0)
assert_equal(tensor_get(tScale, 1), 3.0, "Scalar scale element 1: 1 * 3 = 3")
assert_equal(tensor_get(tScale, 4), 12.0, "Scalar scale element 4: 4 * 3 = 12")

tAddScalar = tensor_add_scalar(tA, 5.0)
assert_equal(tensor_get(tAddScalar, 1), 6.0, "Scalar add element 1: 1 + 5 = 6")
assert_equal(tensor_get(tAddScalar, 4), 9.0, "Scalar add element 4: 4 + 5 = 9")

# ---------------------------------------------------------
# Test 3: High-Performance Matrix Multiplication (GEMM)
# ---------------------------------------------------------
# A = [ [1, 2],
#       [3, 4] ]
# B = [ [5, 6],
#       [7, 8] ]
# C = A x B = [ [19, 22],
#               [43, 50] ]
matA = tensor_from_list([1.0, 2.0, 3.0, 4.0], "Float32")
matA = tensor_reshape(matA, [2, 2])

matB = tensor_from_list([5.0, 6.0, 7.0, 8.0], "Float32")
matB = tensor_reshape(matB, [2, 2])

matC = tensor_matmul(matA, matB)
assert_true(istensor(matC), "tensor_matmul returns a valid tensor")

cShape = tensor_shape(matC)
assert_equal(cShape[1], 2, "GEMM result rows = 2")
assert_equal(cShape[2], 2, "GEMM result cols = 2")

assert_equal(tensor_get(matC, 1, 1), 19.0, "GEMM C(1,1) = 1*5 + 2*7 = 19")
assert_equal(tensor_get(matC, 1, 2), 22.0, "GEMM C(1,2) = 1*6 + 2*8 = 22")
assert_equal(tensor_get(matC, 2, 1), 43.0, "GEMM C(2,1) = 3*5 + 4*7 = 43")
assert_equal(tensor_get(matC, 2, 2), 50.0, "GEMM C(2,2) = 3*6 + 4*8 = 50")

# ---------------------------------------------------------
# Test 4: Neural Network Activations
# ---------------------------------------------------------
actInput = tensor_from_list([-3.0, 0.0, 5.0], "Float32")

# ReLU
tRelu = tensor_relu(actInput)
assert_equal(tensor_get(tRelu, 1), 0.0, "ReLU of -3.0 is 0.0")
assert_equal(tensor_get(tRelu, 2), 0.0, "ReLU of 0.0 is 0.0")
assert_equal(tensor_get(tRelu, 3), 5.0, "ReLU of 5.0 is 5.0")

# Sigmoid at 0.0 is 0.5
zeroTensor = tensor_from_list([0.0], "Float32")
tSig = tensor_sigmoid(zeroTensor)
sigVal = tensor_get(tSig, 1)
assert_true(fabs(sigVal - 0.5) < 0.0001, "Sigmoid(0) = 0.5")

# GELU at 0.0 is 0.0
tGelu = tensor_gelu(zeroTensor)
assert_equal(tensor_get(tGelu, 1), 0.0, "GELU(0) = 0.0")

# Softmax: sum across distribution should equal 1.0
distInput = tensor_from_list([1.0, 2.0, 3.0], "Float32")
tSoftmax = tensor_softmax(distInput)
smSum = tensor_sum(tSoftmax)
assert_true(fabs(smSum - 1.0) < 0.0001, "Softmax probabilities sum to 1.0")

# ---------------------------------------------------------
# Test 5: Reductions
# ---------------------------------------------------------
redInput = tensor_from_list([10.0, 20.0, 30.0, 40.0], "Float32")

assert_equal(tensor_sum(redInput), 100.0, "tensor_sum([10, 20, 30, 40]) = 100.0")
assert_equal(tensor_mean(redInput), 25.0, "tensor_mean([10, 20, 30, 40]) = 25.0")
assert_equal(tensor_max(redInput), 40.0, "tensor_max([10, 20, 30, 40]) = 40.0")
assert_equal(tensor_min(redInput), 10.0, "tensor_min([10, 20, 30, 40]) = 10.0")

test_summary()
