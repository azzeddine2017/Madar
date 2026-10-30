# =========================================================
# Madar Test Suite: Contextual Exception Catching (cCatchError)
# Verifies Line Number, Error Code, and File Context in cCatchError
# =========================================================

load "../test_harness.ring"

suite("Madar Core - Contextual Exception Catching (cCatchError)")

# 1. Division by Zero Context
cErr1 = ""
try
	n = 10 / 0
catch
	cErr1 = cCatchError
done

assert_true(len(cErr1) > 0, "cCatchError is populated on runtime error")
assert_true(substr(cErr1, "Line ") > 0, "cCatchError contains line number prefix")
assert_true(substr(cErr1, "Error (R1)") > 0, "cCatchError contains Error (R1) code")
assert_true(substr(cErr1, "Can't divide by zero") > 0, "cCatchError contains error message")
assert_true(substr(cErr1, " in ") > 0, "cCatchError contains file separator 'in'")
assert_true(substr(cErr1, "test_try_catch_context.ring") > 0, "cCatchError contains active source file name")

# 2. Uninitialized Variable Context
cErr2 = ""
try
	? nonExistentVar_xyz123
catch
	cErr2 = cCatchError
done

assert_true(substr(cErr2, "Line ") > 0, "Uninitialized var catch contains Line prefix")
assert_true(substr(cErr2, "Error (R24)") > 0, "cCatchError contains Error (R24)")
assert_true(substr(cErr2, "nonexistentvar_xyz123") > 0, "cCatchError specifies variable name")
assert_true(substr(cErr2, "test_try_catch_context.ring") > 0, "cCatchError specifies file name")

# 3. Array Index Out of Range Context
cErr3 = ""
aList = [1, 2, 3]
try
	x = aList[100]
catch
	cErr3 = cCatchError
done

assert_true(substr(cErr3, "Line ") > 0, "Array bounds catch contains Line prefix")
assert_true(substr(cErr3, "Error (R2)") > 0, "cCatchError contains Error (R2)")
assert_true(substr(cErr3, "Index out of range") > 0, "cCatchError specifies Index out of range")

# 4. Backward Compatibility Check for Legacy substr() Patterns
bLegacyCheck1 = substr(cErr1, "Error (R1)") > 0
bLegacyCheck2 = substr(cErr1, "divide by zero") > 0
bLegacyCheck3 = substr(cErr2, "Using uninitialized variable") > 0

assert_true(bLegacyCheck1, "Legacy substr(cCatchError, 'Error (R1)') remains true")
assert_true(bLegacyCheck2, "Legacy substr(cCatchError, 'divide by zero') remains true")
assert_true(bLegacyCheck3, "Legacy substr(cCatchError, 'Using uninitialized variable') remains true")

test_summary()

