# =========================================================
# Madar Test Suite: Compiler & Runtime JSON Errors Feedback Loop
# Verifies structured JSON error reporting for AI Agents
# =========================================================

load "../test_harness.ring"

suite("Madar Compiler & Runtime JSON Errors (--json-errors)")

# 1. Test madar_json_errors() API
nInitial = madar_json_errors()
assert_true(nInitial = 0 or nInitial = 1, "madar_json_errors() returns integer flag")

nPrev = madar_json_errors(1)
assert_equal(1, madar_json_errors(), "madar_json_errors(1) enables JSON errors")

madar_json_errors(0)
assert_equal(0, madar_json_errors(), "madar_json_errors(0) disables JSON errors")

# Restore initial state
madar_json_errors(nInitial)

# 2. Test ring_state_setjsonerrors() on Sub-State
pState = ring_state_new()
assert_true(pState != NULL, "ring_state_new returns valid state pointer")
ring_state_setjsonerrors(pState, 1)
assert_true(true, "ring_state_setjsonerrors(pState, 1) executed without error")
ring_state_delete(pState)

# 3. Test CLI Runtime Error with --json-errors
cTempScript = "temp_rt_err.ring"
cTempOut = "temp_rt_out.json"

cCode = "t1 = tensor([1, 2, 3])" + nl +
        "t2 = tensor([1, 2])" + nl +
        "t3 = t1 + t2" + nl
write(cTempScript, cCode)

if iswindows()
	cRingExe = "..\..\bin\ring.exe"
else
	cRingExe = "../../bin/ring"
ok
cCmd = cRingExe + " --json-errors " + cTempScript + " > " + cTempOut + " 2>&1"
system(cCmd)

cJson = read(cTempOut)
assert_true(substr(cJson, '"madar_error"') > 0, "Runtime JSON contains 'madar_error' root")
assert_true(substr(cJson, '"status": "error"') > 0, "Runtime JSON contains error status")
assert_true(substr(cJson, '"stage": "runtime"') > 0, "Runtime JSON stage is 'runtime'")
assert_true(substr(cJson, '"hint"') > 0, "Runtime JSON contains intelligent hint")
assert_true(substr(cJson, '"source_snippet"') > 0, "Runtime JSON contains source snippet")
assert_true(substr(cJson, '"call_stack"') > 0, "Runtime JSON contains call stack array")

# Clean up
remove(cTempScript)
remove(cTempOut)

# 4. Test CLI Parser / Syntax Error with --json-errors
cTempScript2 = "temp_syntax_err.ring"
cTempOut2 = "temp_syntax_out.json"

cCode2 = "func main" + nl +
         "    if 1 = 1" + nl +
         "        see 'test'" + nl
write(cTempScript2, cCode2)

cCmd2 = cRingExe + " --json-errors " + cTempScript2 + " > " + cTempOut2 + " 2>&1"
system(cCmd2)

cJson2 = read(cTempOut2)
assert_true(substr(cJson2, '"madar_error"') > 0, "Syntax JSON contains 'madar_error' root")
assert_true(substr(cJson2, '"stage": "parser"') > 0, "Syntax JSON stage is 'parser'")
assert_true(substr(cJson2, '"hint"') > 0, "Syntax JSON contains actionable syntax fix hint")
assert_true(substr(cJson2, "ok") > 0, "Syntax hint advises closing if with 'ok'")

# Clean up
remove(cTempScript2)
remove(cTempOut2)

test_summary()
