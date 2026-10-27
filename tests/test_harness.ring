# =========================================================
# Madar Test Harness Framework
# Lightweight assertions and test suite reporting for Madar
# =========================================================

nTestsPassed = 0
nTestsFailed = 0
cCurrentSuite = ""

func suite(cName)
	cCurrentSuite = cName
	see nl + "==================================================" + nl
	see "  TEST SUITE: " + cName + nl
	see "==================================================" + nl

func assert_equal(expected, actual, cMessage)
	if expected = actual
		nTestsPassed++
		see "  [PASS] " + cMessage + nl
	else
		nTestsFailed++
		see "  [FAIL] " + cMessage + nl
		see "         Expected: " + string(expected) + nl
		see "         Actual  : " + string(actual) + nl
	ok

func assert_true(condition, cMessage)
	assert_equal(true, condition, cMessage)

func assert_false(condition, cMessage)
	assert_equal(false, condition, cMessage)

func test_summary()
	see nl + "--------------------------------------------------" + nl
	see "  RESULTS: " + (nTestsPassed + nTestsFailed) + " Total | "
	see "" + nTestsPassed + " Passed | " + nTestsFailed + " Failed" + nl
	see "--------------------------------------------------" + nl
	if nTestsFailed = 0
		see "  SUCCESS: All tests in this suite passed!" + nl
	else
		see "  FAILURE: Some tests failed!" + nl
		bye 1
	ok
