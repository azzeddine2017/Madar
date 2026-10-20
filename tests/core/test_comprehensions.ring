# =========================================================
# Madar Core Test: Python-style List Comprehensions
# [ expr for var in source (if cond)? ]
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Python List Comprehensions")

# =========================================================
# 1. Basic List Comprehensions (Identity & Arithmetic)
# =========================================================
nums = [x for x in 1:5 ]
assert_equal(5, len(nums), "Basic identity range [x for x in 1:5] length")
assert_equal(1, nums[1], "Basic identity item 1")
assert_equal(3, nums[3], "Basic identity item 3")
assert_equal(5, nums[5], "Basic identity item 5")

squares = [x * x for x in 1:5]
assert_equal(5, len(squares), "Squares length")
assert_equal(1, squares[1], "1^2 = 1")
assert_equal(4, squares[2], "2^2 = 4")
assert_equal(9, squares[3], "3^2 = 9")
assert_equal(16, squares[4], "4^2 = 16")
assert_equal(25, squares[5], "5^2 = 25")

doubled = [x * 2 for x in 1:4]
assert_equal(4, len(doubled), "Doubled length")
assert_equal(2, doubled[1], "1*2 = 2")
assert_equal(4, doubled[2], "2*2 = 4")
assert_equal(6, doubled[3], "3*2 = 6")
assert_equal(8, doubled[4], "4*2 = 8")

# =========================================================
# 2. Filtered List Comprehensions (Single 'if')
# =========================================================
evens = [x for x in 1:10 if x % 2 = 0]
assert_equal(5, len(evens), "Filtered evens count in 1:10")
assert_equal(2, evens[1], "Even item 1")
assert_equal(4, evens[2], "Even item 2")
assert_equal(6, evens[3], "Even item 3")
assert_equal(8, evens[4], "Even item 4")
assert_equal(10, evens[5], "Even item 5")

gt_five = [x * 10 for x in 1:8 if x > 5]
assert_equal(3, len(gt_five), "Filtered count x > 5 in 1:8")
assert_equal(60, gt_five[1], "6 * 10 = 60")
assert_equal(70, gt_five[2], "7 * 10 = 70")
assert_equal(80, gt_five[3], "8 * 10 = 80")

# =========================================================
# 3. Chained and Compound Conditions
# =========================================================
# Chained 'if' clauses: if x > 3 if x < 8
mid = [x for x in 1:10 if x > 3 if x < 8]
assert_equal(4, len(mid), "Chained if count")
assert_equal(4, mid[1], "Chained item 1 = 4")
assert_equal(7, mid[4], "Chained item 4 = 7")

# Compound logical operator 'and' in condition
mid_and = [x for x in 1:10 if x > 3 and x < 8]
assert_equal(4, len(mid_and), "Compound and condition count")
assert_equal(4, mid_and[1], "Compound item 1 = 4")
assert_equal(7, mid_and[4], "Compound item 4 = 7")

# =========================================================
# 4. Iterating Over Existing Lists & Strings
# =========================================================
names = ["alice", "bob", "charlie", "david"]
uppers = [upper(n) for n in names]
assert_equal(4, len(uppers), "Upper names count")
assert_equal("ALICE", uppers[1], "Upper item 1")
assert_equal("BOB", uppers[2], "Upper item 2")
assert_equal("CHARLIE", uppers[3], "Upper item 3")
assert_equal("DAVID", uppers[4], "Upper item 4")

long_names = [n for n in names if len(n) > 4]
assert_equal(3, len(long_names), "Long names count (>4)")
assert_equal("alice", long_names[1], "Long name 1")
assert_equal("charlie", long_names[2], "Long name 2")
assert_equal("david", long_names[3], "Long name 3")

# String as sequence
chars = [c for c in "madar"]
assert_equal(5, len(chars), "String chars count")
assert_equal("m", chars[1], "Char 1")
assert_equal("a", chars[2], "Char 2")
assert_equal("d", chars[3], "Char 3")
assert_equal("a", chars[4], "Char 4")
assert_equal("r", chars[5], "Char 5")

# =========================================================
# 5. Empty Results (Filtered Out or Empty Source)
# =========================================================
empty_filter = [x for x in 1:5 if x > 100]
assert_equal(0, len(empty_filter), "All filtered out produces empty list")
empty_source = [x for x in []]
assert_equal(0, len(empty_source), "Empty source produces empty list")

# =========================================================
# 6. Function Calls in Projection and Conditions
# =========================================================
func_proj = [double_num(x) for x in 1:3]
assert_equal(3, len(func_proj), "Function call in projection length")
assert_equal(2, func_proj[1], "double_num(1)")
assert_equal(4, func_proj[2], "double_num(2)")
assert_equal(6, func_proj[3], "double_num(3)")

func_cond = [x for x in 1:6 if is_even(x)]
assert_equal(3, len(func_cond), "Function call in condition length")
assert_equal(2, func_cond[1], "is_even 1")
assert_equal(4, func_cond[2], "is_even 2")
assert_equal(6, func_cond[3], "is_even 3")

# =========================================================
# 7. Complex Projections (Lists, f-strings, Dictionaries)
# =========================================================
pairs = [[x, x * 10] for x in 1:3]
assert_equal(3, len(pairs), "Pair list length")
assert_equal(1, pairs[1][1], "Pair 1 first")
assert_equal(10, pairs[1][2], "Pair 1 second")
assert_equal(2, pairs[2][1], "Pair 2 first")
assert_equal(20, pairs[2][2], "Pair 2 second")
assert_equal(3, pairs[3][1], "Pair 3 first")
assert_equal(30, pairs[3][2], "Pair 3 second")

# f-strings inside comprehension
labels = [f"item_{x}" for x in 1:3]
assert_equal(3, len(labels), "Labels length")
assert_equal("item_1", labels[1], "Label 1")
assert_equal("item_2", labels[2], "Label 2")
assert_equal("item_3", labels[3], "Label 3")

# Dictionaries / hash maps inside comprehension
dicts = [[:id = x, :val = x * 2] for x in 1:2]
assert_equal(2, len(dicts), "Dicts length")
assert_equal(1, dicts[1][:id], "Dict 1 id")
assert_equal(2, dicts[1][:val], "Dict 1 val")
assert_equal(2, dicts[2][:id], "Dict 2 id")
assert_equal(4, dicts[2][:val], "Dict 2 val")

# =========================================================
# 8. Multi-Variable (Nested 'for') Comprehensions
# =========================================================
cartesian = [x + y for x in [1, 2] for y in [10, 20]]
assert_equal(4, len(cartesian), "Cartesian product count (2x2)")
assert_equal(11, cartesian[1], "1 + 10 = 11")
assert_equal(21, cartesian[2], "1 + 20 = 21")
assert_equal(12, cartesian[3], "2 + 10 = 12")
assert_equal(22, cartesian[4], "2 + 20 = 22")

# Multi-for with condition
diag = [x * y for x in 1:3 for y in 1:3 if x = y]
assert_equal(3, len(diag), "Diagonal filter count")
assert_equal(1, diag[1], "1 * 1 = 1")
assert_equal(4, diag[2], "2 * 2 = 4")
assert_equal(9, diag[3], "3 * 3 = 9")

# =========================================================
# 9. Nested Comprehensions (Matrix / 2D List)
# =========================================================
matrix = [[r * c for c in 1:3] for r in 1:3]
assert_equal(3, len(matrix), "Matrix row count")
assert_equal(1, matrix[1][1], "matrix[1][1]")
assert_equal(2, matrix[1][2], "matrix[1][2]")
assert_equal(3, matrix[1][3], "matrix[1][3]")
assert_equal(2, matrix[2][1], "matrix[2][1]")
assert_equal(4, matrix[2][2], "matrix[2][2]")
assert_equal(6, matrix[2][3], "matrix[2][3]")
assert_equal(3, matrix[3][1], "matrix[3][1]")
assert_equal(6, matrix[3][2], "matrix[3][2]")
assert_equal(9, matrix[3][3], "matrix[3][3]")

# =========================================================
# 10. Multi-line List Comprehension
# =========================================================
multiline = [
    x * 3
    for x in 1:4
    if x > 1
]
assert_equal(3, len(multiline), "Multi-line comprehension length")
assert_equal(6, multiline[1], "2 * 3 = 6")
assert_equal(9, multiline[2], "3 * 3 = 9")
assert_equal(12, multiline[3], "4 * 3 = 12")

# =========================================================
# 11. Slicing on List Comprehensions
# =========================================================
sliced = [x * 10 for x in 1:6][2:4]
assert_equal(3, len(sliced), "Sliced comprehension [2:4] length is 3")
assert_equal(20, sliced[1], "Sliced item 1 = 20")
assert_equal(30, sliced[2], "Sliced item 2 = 30")
assert_equal(40, sliced[3], "Sliced item 3 = 40")

# =========================================================
# 12. Standard Lists Backward Compatibility
# =========================================================
std_list = [1, 2, 3, 4]
assert_equal(4, len(std_list), "Standard list [1, 2, 3, 4] remains fully working")
assert_equal(1, std_list[1], "Standard item 1")
assert_equal(4, std_list[4], "Standard item 4")

# =========================================================
# 13. Flow-style List Comprehensions [ for x in src if cond : expr ]
# =========================================================
flow_basic = [for x in 1:5 : x * 2]
assert_equal(5, len(flow_basic), "Flow comprehension [for x in 1:5 : x * 2] length")
assert_equal(2, flow_basic[1], "Flow item 1 = 2")
assert_equal(10, flow_basic[5], "Flow item 5 = 10")

flow_filtered = [for x in 1:10 if x % 2 = 0 : x]
assert_equal(5, len(flow_filtered), "Flow filtered evens length")
assert_equal(2, flow_filtered[1], "Flow filtered item 1")
assert_equal(10, flow_filtered[5], "Flow filtered item 5")

test_summary()

# Helper function
func double_num(n) {
    return n * 2
}

func is_even(n) {
    return (n % 2) = 0
}