# =========================================================
# Madar Test Suite: DOUR Loops & Auto-JIT
# Verifies native 'dour' loop syntax styles, steps, ranges, and comprehensions
# =========================================================

load "../test_harness.ring"

suite("Madar Core - DOUR Loops & Auto-JIT Engine")

# 1. Style 1: dour ... next
nSum1 = 0
dour x = 1 to 10
	nSum1 += x
next
assert_equal(55, nSum1, "dour ... next accumulated sum = 55")

# 2. Style 2: dour ... end
nSum2 = 0
dour x = 1 to 10
	nSum2 += x
end
assert_equal(55, nSum2, "dour ... end accumulated sum = 55")

# 3. Style 3: dour ... { }
nSum3 = 0
dour x = 1 to 10 {
	nSum3 += x
}
assert_equal(55, nSum3, "dour ... { } accumulated sum = 55")

# 4. dour with step
nSum4 = 0
dour x = 1 to 10 step 2
	nSum4 += x
next
assert_equal(25, nSum4, "dour with step 2 (1+3+5+7+9) = 25")

# 5. dour in range (1:5)
aRes = []
dour x in 1:5
	aRes + x
next
assert_equal(5, len(aRes), "dour in range produced 5 items")
assert_equal(5, aRes[5], "dour in range last item = 5")

# 6. dour in list
aNames = ["Madar", "Ring", "JIT"]
cCombined = ""
dour name in aNames
	cCombined += name + " "
end
assert_equal("Madar Ring JIT ", cCombined, "dour in list iterated all items correctly")

# 7. dour list comprehension
aSquares = [x*x dour x in 1:5]
assert_equal(5, len(aSquares), "dour comprehension [x*x dour x in 1:5] length is 5")
assert_equal(1, aSquares[1], "aSquares[1] = 1")
assert_equal(4, aSquares[2], "aSquares[2] = 4")
assert_equal(9, aSquares[3], "aSquares[3] = 9")
assert_equal(16, aSquares[4], "aSquares[4] = 16")
assert_equal(25, aSquares[5], "aSquares[5] = 25")

test_summary()

