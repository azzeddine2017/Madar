# File: extensions/ringtensor/tests/test_core.ring

load "ringtensor.ring"


see "=== RingTensor Core Test (Pointer Mode) ===" + nl


# 1. Lifecycle Test
see "1. Testing Init & Set/Get..." + nl
p1 = tensor_init(2, 2)
tensor_set(p1, 1, 1, 10.0)
tensor_set(p1, 2, 2, 20.0)
val = tensor_get(p1, 1, 1)

if val = 10.0 
    see "   PASS: Value retrieved successfully." + nl
else 
    see "   FAIL: Expected 10.0, got " + val + nl
ok

# 2. Math Test (Add)
see nl + "2. Testing Addition..." + nl
# Create 2 tensors
A = tensor_init(2, 2)
tensor_fill(A, 1.0) # [[1,1],[1,1]]

B = tensor_init(2, 2)
tensor_fill(B, 2.0) # [[2,2],[2,2]]

tensor_add(A, B) # A = A + B
val = tensor_get(A, 1, 1) # Should be 3.0

if val = 3.0
    see "   PASS: 1.0 + 2.0 = 3.0" + nl
else
    see "   FAIL: Addition wrong." + nl
ok

# 3. MatMul Test
see nl + "3. Testing Matrix Multiplication..." + nl
# A (1x2) = [1, 2]
mA = tensor_init(1, 2)
tensor_set(mA, 1, 1, 1.0)
tensor_set(mA, 1, 2, 2.0)

# B (2x1) = [[3], [4]]
mB = tensor_init(2, 1)
tensor_set(mB, 1, 1, 3.0)
tensor_set(mB, 2, 1, 4.0)

# Res (1x1)
mRes = tensor_init(1, 1)

tensor_matmul(mA, mB, mRes)
res = tensor_get(mRes, 1, 1)

# 1*3 + 2*4 = 11
if res = 11.0
    see "   PASS: MatMul Result is 11.0" + nl
else
    see "   FAIL: MatMul Result is " + res + nl
ok

see nl + "Done." + nl

# --- Helper to print tensor ---
func printT pTensor, rows, cols
    see "[" + nl
    for r=1 to rows
        see "  "
        for c=1 to cols
            see "" + tensor_get(pTensor, r, c) + " "
        next
        see nl
    next
    see "]" + nl
