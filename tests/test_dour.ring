# Test Madar DOUR Loop & Comprehensions

? "===================================="
? " Testing Madar DOUR Syntax & Styles "
? "===================================="

# Style 1: dour ... next
see "Testing Style 1 (next): "
nSum1 = 0
dour x = 1 to 10
    nSum1 += x
next
if nSum1 = 55 ? "PASS (sum=55)" else ? "FAIL (" + nSum1 + ")" ok

# Style 2: dour ... end
see "Testing Style 2 (end): "
nSum2 = 0
dour x = 1 to 10
    nSum2 += x
end
if nSum2 = 55 ? "PASS (sum=55)" else ? "FAIL (" + nSum2 + ")" ok

# Style 3: dour ... { }
see "Testing Style 3 (braces): "
nSum3 = 0
dour x = 1 to 10 {
    nSum3 += x
}
if nSum3 = 55 ? "PASS (sum=55)" else ? "FAIL (" + nSum3 + ")" ok

# Step test
see "Testing Step (step 2): "
nSum4 = 0
dour x = 1 to 10 step 2
    nSum4 += x
next
# 1 + 3 + 5 + 7 + 9 = 25
if nSum4 = 25 ? "PASS (sum=25)" else ? "FAIL (" + nSum4 + ")" ok

# DOUR In Range
see "Testing DOUR in Range (1:5): "
aRes = []
dour x in 1:5
    aRes + x
next
if len(aRes) = 5 and aRes[5] = 5 ? "PASS" else ? "FAIL" ok

# DOUR In List
see "Testing DOUR in List: "
aNames = ["Madar", "Ring", "JIT"]
cCombined = ""
dour name in aNames
    cCombined += name + " "
end
if cCombined = "Madar Ring JIT " ? "PASS (" + cCombined + ")" else ? "FAIL" ok

# DOUR List Comprehension
see "Testing DOUR List Comprehension [x*x dour x in 1:5]: "
aSquares = [x*x dour x in 1:5]
if len(aSquares) = 5 and aSquares[5] = 25
    ? "PASS ([1, 4, 9, 16, 25])"
else
    ? "FAIL"
ok

? "===================================="
? " All DOUR tests completed!          "
? "===================================="
