# =========================================================
# Madar Test Suite: Native Async & Await Keywords (Track C)
# Verifies native scanner, parser, bytecode and VM execution
# =========================================================

load "../test_harness.ring"

func main {
    suite("Madar Core - Native async & await (Track C)")

    # 1. Native Await on Primitive Values
    x = await 42
    assert_equal(x, 42, "await on integer literal produces 42")

    cStr = await "Hello Madar Async"
    assert_equal(cStr, "Hello Madar Async", "await on string literal produces string")

    aList = await [1, 2, 3]
    assert_equal(len(aList), 3, "await on list produces list")

    # 2. Native Await on Expressions
    nCalc = await (10 * 5 + 2)
    assert_equal(nCalc, 52, "await on parenthesized math expression")

    # 3. Native Async Function Call
    nRes = computeAsync(6, 7)
    assert_equal(nRes, 42, "async func executes and returns value")

    # 4. Await on async function result
    nRes2 = await computeAsync(3, 4)
    assert_equal(nRes2, 12, "await computeAsync(3, 4) produces 12")

    # 5. Compound await expressions
    nCombined = (await 100) + (await 200)
    assert_equal(nCombined, 300, "compound await expressions")
}

# Native Async Function Declaration
async func computeAsync(a, b) {
    return a * b
}
