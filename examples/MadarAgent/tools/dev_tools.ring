# ====================================================================
#   MadarAgent - Developer & Execution Tools
#   أدوات المطور: الآلة الحاسبة وتنفيذ أكواد رينج واختبارها حياً
# ====================================================================


# --------------------------------------------------------------------
# 1. CalcTool: Accurate Mathematical Computation
# --------------------------------------------------------------------
class CalcTool from AgentTool
	func init
		cName = "calc"
		cDescription = "Evaluates an arithmetic or mathematical expression accurately (e.g. '300 / 120 * 60')"
		aParameters = [
			["expression", "string", "Mathematical expression to evaluate (e.g. '120 * 2.5')", true]
		]
		return self

	func execute(aArgs)
		cExpr = ""
		if islist(aArgs) and len(aArgs) >= 1
			cExpr = "" + aArgs[1]
		elseif isstring(aArgs)
			cExpr = aArgs
		ok

		cExpr = substr(cExpr, '"', "")
		cExpr = substr(cExpr, "'", "")
		cExpr = trim(cExpr)

		if cExpr = "" return "Error: Empty expression passed to calc." ok

		# Normalize Arabic words to mathematical symbols
		cExpr = substr(cExpr, "ضرب", "*")
		cExpr = substr(cExpr, "في", "*")
		cExpr = substr(cExpr, "×", "*")
		cExpr = substr(cExpr, "زائد", "+")
		cExpr = substr(cExpr, "جمع", "+")
		cExpr = substr(cExpr, "طرح", "-")
		cExpr = substr(cExpr, "ناقص", "-")
		cExpr = substr(cExpr, "قسمة", "/")
		cExpr = substr(cExpr, "على", "/")
		cExpr = substr(cExpr, "÷", "/")

		# Security filter: only allow numbers, operators, parens, spaces
		cAllowed = "0123456789+-*/(). "
		bSafe = true
		for i = 1 to len(cExpr)
			if substr(cAllowed, cExpr[i]) = 0
				bSafe = false
				exit
			ok
		next

		if !bSafe
			return f"Error: Expression '{cExpr}' contains invalid characters for calc."
		ok

		try
			nRes = 0
			eval("nRes = " + cExpr)
			return f"Result: {cExpr} = {nRes}"
		catch
			return f"Calculation Error: {cCatchError}"
		done

# --------------------------------------------------------------------
# 2. RingRunTool: Execute Ring Code Live and Return Real Output
# --------------------------------------------------------------------
class RingRunTool from AgentTool
	func init
		cName = "run_ring_code"
		cDescription = "Executes a snippet of Ring programming code in an isolated sub-process and returns stdout/stderr"
		aParameters = [
			["code", "string", "The complete Ring source code to execute", true]
		]
		return self

	func execute(aArgs)
		cCode = ""
		if islist(aArgs) and len(aArgs) >= 1
			cCode = "" + aArgs[1]
		elseif isstring(aArgs)
			cCode = aArgs
		ok

		cCode = trim(cCode)
		if cCode = "" return "Error: No code provided to run_ring_code." ok

		# Clean markdown fences if model passed them
		if substr(cCode, "```ring") > 0
			cCode = substr(cCode, "```ring", "")
		ok
		if substr(cCode, "```") > 0
			cCode = substr(cCode, "```", "")
		ok
		cCode = trim(cCode)

		cTempFile = "sandbox_eval.ring"
		cOutFile  = "sandbox_eval.log"

		write(cTempFile, cCode)

		# Execute ring process safely redirecting output
		cCmd = f"ring {cTempFile} > {cOutFile} 2>&1"
		system(cCmd)

		cOutput = ""
		if fexists(cOutFile)
			cOutput = read(cOutFile)
			remove(cOutFile)
		ok
		if fexists(cTempFile)
			remove(cTempFile)
		ok

		cOutput = trim(cOutput)
		if cOutput = ""
			return "Execution completed successfully with no terminal output."
		ok
		if len(cOutput) > 3000
			return left(cOutput, 3000) + nl + "... [Truncated output]"
		ok
		return "Execution Output:" + nl + cOutput
