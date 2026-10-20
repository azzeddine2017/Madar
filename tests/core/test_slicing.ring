# =========================================================
# Madar Core Test: Python-style Advanced Slicing (seq[start:stop:step])
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Advanced Slicing (seq[start:stop:step])")

# =========================================================
# 1. String Slicing (1-Based, Inclusive)
# =========================================================
s = "Hello World"

# Basic slices
assert_equal("Hello", s[1:5], "String slice with start and stop (s[1:5])")
assert_equal("World", s[7:11], "String slice of second word (s[7:11])")
assert_equal("World", s[7:], "String slice to end (s[7:])")
assert_equal("Hello", s[:5], "String slice from beginning (s[:5])")
assert_equal("Hello World", s[:], "String full slice copy (s[:])")

# Step slices
assert_equal("HloWrd", s[::2], "String slice with step 2 (s[::2])")
assert_equal("el ol", s[2::2], "String slice with start and step 2 (s[2::2])")
assert_equal("Hlo", s[1:5:2], "String slice with start, stop, and step 2 (s[1:5:2])")

# Negative step (Reverse)
assert_equal("dlroW olleH", s[::-1], "String full reverse (s[::-1])")
assert_equal("drWolH", s[::-2], "String reverse with step -2 (s[::-2])")
assert_equal("olleH", s[5:1:-1], "String reverse sub-slice (s[5:1:-1])")

# Negative indexing
assert_equal("d", s[-1], "String single negative index (s[-1])")
assert_equal("l", s[-2], "String second to last char (s[-2])")
assert_equal("World", s[-5:], "String slice from negative index to end (s[-5:])")
assert_equal("Hello", s[1:-7], "String slice with negative stop (s[1:-7])")

# Boundary clamping
assert_equal("Hello World", s[1:100], "String slice clamped at sequence end (s[1:100])")
assert_equal("", s[5:2], "String slice with invalid positive range returns empty string")

# =========================================================
# 2. List Slicing (1-Based, Inclusive)
# =========================================================
nums = [10, 20, 30, 40, 50]

# Basic list slices
sub1 = nums[1:3]
assert_equal(3, len(sub1), "List slice [1:3] length is 3")
assert_equal(10, sub1[1], "List slice [1:3] item 1")
assert_equal(20, sub1[2], "List slice [1:3] item 2")
assert_equal(30, sub1[3], "List slice [1:3] item 3")

sub2 = nums[3:]
assert_equal(3, len(sub2), "List slice [3:] length is 3")
assert_equal(30, sub2[1], "List slice [3:] item 1")
assert_equal(50, sub2[3], "List slice [3:] item 3")

sub3 = nums[:2]
assert_equal(2, len(sub3), "List slice [:2] length is 2")
assert_equal(10, sub3[1], "List slice [:2] item 1")
assert_equal(20, sub3[2], "List slice [:2] item 2")

sub_all = nums[:]
assert_equal(5, len(sub_all), "List full slice copy [:] length is 5")
assert_equal(10, sub_all[1], "List full slice copy item 1")
assert_equal(50, sub_all[5], "List full slice copy item 5")

# Step slices
sub_step = nums[1:5:2]
assert_equal(3, len(sub_step), "List slice with step 2 [1:5:2] length")
assert_equal(10, sub_step[1], "List slice with step 2 item 1 (10)")
assert_equal(30, sub_step[2], "List slice with step 2 item 2 (30)")
assert_equal(50, sub_step[3], "List slice with step 2 item 3 (50)")

sub_step_all = nums[::2]
assert_equal(3, len(sub_step_all), "List slice [::2] length")
assert_equal(10, sub_step_all[1], "List slice [::2] item 1 (10)")
assert_equal(50, sub_step_all[3], "List slice [::2] item 3 (50)")

# Negative step (List Reverse)
sub_rev = nums[::-1]
assert_equal(5, len(sub_rev), "List reverse [::-1] length")
assert_equal(50, sub_rev[1], "List reverse [::-1] item 1 (50)")
assert_equal(40, sub_rev[2], "List reverse [::-1] item 2 (40)")
assert_equal(30, sub_rev[3], "List reverse [::-1] item 3 (30)")
assert_equal(20, sub_rev[4], "List reverse [::-1] item 4 (20)")
assert_equal(10, sub_rev[5], "List reverse [::-1] item 5 (10)")

# Negative indexing
assert_equal(50, nums[-1], "List single negative index (nums[-1])")
assert_equal(40, nums[-2], "List second to last item (nums[-2])")

sub_neg = nums[-3:]
assert_equal(3, len(sub_neg), "List slice from negative start nums[-3:] length")
assert_equal(30, sub_neg[1], "List slice nums[-3:] item 1 (30)")
assert_equal(50, sub_neg[3], "List slice nums[-3:] item 3 (50)")

# =========================================================
# 3. Dynamic Expressions in Slices
# =========================================================
a = 1
b = 3
sub_expr = nums[a + 1 : b + 1]
assert_equal(3, len(sub_expr), "List slice with arithmetic expressions [a+1 : b+1]")
assert_equal(20, sub_expr[1], "List slice with expressions item 1 (20)")
assert_equal(40, sub_expr[3], "List slice with expressions item 3 (40)")

# =========================================================
# 4. Chained Slicing
# =========================================================
chained_str = "abcdefgh"[2:7][2:4]
assert_equal("cde", chained_str, "Chained string slicing ('abcdefgh'[2:7][2:4])")

chained_list = nums[1:4][2:3]
assert_equal(2, len(chained_list), "Chained list slicing length")
assert_equal(20, chained_list[1], "Chained list slicing item 1")
assert_equal(30, chained_list[2], "Chained list slicing item 2")

# =========================================================
# 5. Backward Compatibility Guarantee (Hash maps :symbol)
# =========================================================
person = [
	:name = "Ali",
	:age = 30,
	:city = "Algiers"
]

assert_equal("Ali", person[:name], "Hash map lookup with :name preserves backward compatibility")
assert_equal(30, person[:age], "Hash map lookup with :age preserves backward compatibility")
assert_equal("Algiers", person[:city], "Hash map lookup with :city preserves backward compatibility")

test_summary()
