# Baseline Backward Compatibility Test Suite for Madar Core

load "../test_harness.ring"

suite("Ring Core Backward Compatibility")

# 1. Scalar types and Arithmetic
assert_equal(10, 5 + 5, "Addition works correctly")
assert_equal(25, 5 * 5, "Multiplication works correctly")
assert_equal(2.5, 5 / 2, "Float division works correctly")

# 2. String operations
cStr = "Hello, Madar!"
assert_equal(13, len(cStr), "String length calculation")
assert_equal("HELLO, MADAR!", upper(cStr), "String uppercase conversion")
assert_equal("hello, madar!", lower(cStr), "String lowercase conversion")

# 3. List and Memory model
aList = [1, 2, 3, "four", [5, 6]]
assert_equal(5, len(aList), "List element count")
assert_equal("four", aList[4], "List 1-based indexing for strings")
assert_equal(5, aList[5][1], "Nested list access")
add(aList, 7)
assert_equal(6, len(aList), "List dynamic append")

# 4. Control Flow
nSum = 0
for i = 1 to 10
	nSum += i
next
assert_equal(55, nSum, "For loop sum accumulation")

test_summary()
