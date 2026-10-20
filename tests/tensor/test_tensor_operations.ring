# =========================================================
# Madar Tensor Engine Unit Test Suite
# =========================================================

load "../test_harness.ring"

suite("Madar Native Tensor Engine")

# 1. Tensor Allocation & Type Checking
t1 = tensor([2, 4], "float32")
assert_true(istensor(t1), "t1 is recognized by istensor()")
assert_equal("TENSOR", type(t1), "type(t1) returns 'TENSOR'")
assert_equal("Float32", tensor_type(t1), "tensor_type(t1) returns 'Float32'")
assert_equal(2, tensor_dims(t1), "Rank of [2, 4] tensor is 2")
assert_equal(8, tensor_elements(t1), "Total elements in [2, 4] is 8")

aShape = tensor_shape(t1)
assert_equal(2, len(aShape), "Shape length is 2")
assert_equal(2, aShape[1], "First dimension is 2")
assert_equal(4, aShape[2], "Second dimension is 4")

# 2. Different Data Types
tF64 = tensor([3], "float64")
assert_equal("Float64", tensor_type(tF64), "Tensor Float64 type created")

tI32 = tensor([5], "int32")
assert_equal("Int32", tensor_type(tI32), "Tensor Int32 type created")

tI8 = tensor([16], "int8")
assert_equal("Int8", tensor_type(tI8), "Tensor Int8 type created")

# 3. List <-> Tensor Interop Bridge
srcList = [1.5, 2.5, 3.5, 4.5]
tFromList = tensor_from_list(srcList, "float32")
assert_true(istensor(tFromList), "tensor_from_list returns a valid tensor")
assert_equal(4, tensor_elements(tFromList), "tensor_from_list has 4 elements")

resList = tensor_to_list(tFromList)
assert_equal(4, len(resList), "tensor_to_list returns list of size 4")
assert_equal(1.5, resList[1], "First element round-trip conversion")
assert_equal(2.5, resList[2], "Second element round-trip conversion")
assert_equal(3.5, resList[3], "Third element round-trip conversion")
assert_equal(4.5, resList[4], "Fourth element round-trip conversion")

# 4. Zero-Copy Reshaping
tMatrix = tensor([2, 3], "float32")
assert_equal(6, tensor_elements(tMatrix), "Original 2x3 tensor has 6 elements")

tReshaped = tensor_reshape(tMatrix, [3, 2])
assert_true(istensor(tReshaped), "Reshaped tensor is valid")
assert_equal(2, tensor_dims(tReshaped), "Reshaped rank is 2")
rShape = tensor_shape(tReshaped)
assert_equal(3, rShape[1], "Reshaped dim 1 is 3")
assert_equal(2, rShape[2], "Reshaped dim 2 is 2")

tFlat = tensor_reshape(tMatrix, [6])
assert_equal(1, tensor_dims(tFlat), "Flattened tensor rank is 1")
assert_equal(6, tensor_shape(tFlat)[1], "Flattened tensor length is 6")

# 5. Zero-Copy Slicing
tBig = tensor([4, 4], "float32")
tSlice = tensor_slice(tBig, 1, 1, 2)
assert_true(istensor(tSlice), "Sliced tensor is valid")
sShape = tensor_shape(tSlice)
assert_equal(2, sShape[1], "Sliced dimension 1 has size 2")
assert_equal(4, sShape[2], "Sliced dimension 2 retains size 4")

test_summary()
