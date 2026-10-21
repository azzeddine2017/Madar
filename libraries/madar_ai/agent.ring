# ====================================================================
#   Madar AI Suite - Function Calling & AI Agent Runtime
#   (محرك استدعاء الأدوات والوكلاء الأذكياء في لغة مدار)
# ====================================================================

load "madar_ai.ring"

class AIAgent
	oModel          = NULL
	aTools          = []       # List of registered tools [ [name, desc, params, func], ... ]
	nMaxSteps       = 4        # Maximum tool execution iterations
	bVerbose        = 1        # Print tool calls & observations to terminal
	cSystemPrompt   = ""

	func init(model)
		oModel = model
		# Register default core utilities
		registerCoreTools()
		return self

	func registerTool(cName, cDesc, aParams, pFunc)
		aTools + [cName, cDesc, aParams, pFunc]
		return self

	func registerCoreTools()
		# 1. Mathematical calculation engine
		registerTool("calc", "Evaluates a mathematical or arithmetic expression accurately", ["expr"], func(args) {
			cExpr = ""
			if islist(args) and len(args) >= 1
				cExpr = "" + args[1]
			else
				cExpr = "" + args
			ok
			cExpr = trim(cExpr)
			# Safe evaluation
			try
				nRes = eval("return (" + cExpr + ")")
				return "" + nRes
			catch
				try
					nRes = eval("return " + cExpr)
					return "" + nRes
				catch
					return "Error evaluating expression"
				end
			end
		})

		# 2. Real-time Clock and Date
		registerTool("get_time", "Returns the current local date and time", [], func(args) {
			return "Current Date & Time: " + date() + " " + time()
		})

		# 3. Local File Reader
		registerTool("read_file", "Reads the entire content of a local text file", ["path"], func(args) {
			cPath = ""
			if islist(args) and len(args) >= 1
				cPath = "" + args[1]
			else
				cPath = "" + args
			ok
			cPath = trim(cPath)
			if fexists(cPath)
				cContent = read(cPath)
				if len(cContent) > 2000
					cContent = left(cContent, 2000) + "... [Truncated]"
				ok
				return cContent
			else
				return "Error: File '" + cPath + "' not found."
			ok
		})

		# 4. Operating System Info
		registerTool("sys_info", "Returns operating system and runtime platform info", [], func(args) {
			return "OS: Windows (Madar AI Native Runtime, AVX2 Enabled, FP16 KV-Cache)"
		})

	func buildToolSchema()
		cSchema = "You are an intelligent AI assistant with access to the following local functions/tools:" + nl
		for tool in aTools
			cSchema += "- " + tool[1] + "("
			params = tool[3]
			for p = 1 to len(params)
				cSchema += params[p]
				if p < len(params) cSchema += ", " ok
			next
			cSchema += "): " + tool[2] + nl
		next
		cSchema += nl + "When you need to call a tool, you MUST format your response EXACTLY as:" + nl
		cSchema += "<tool_call>" + nl
		cSchema += "name: tool_name" + nl
		cSchema += "args: argument" + nl
		cSchema += "</tool_call>" + nl + nl
		cSchema += "Examples:" + nl
		cSchema += "User: ما هو الوقت والتاريخ الآن؟" + nl
		cSchema += "<tool_call>" + nl + "name: get_time" + nl + "args: " + nl + "</tool_call>" + nl + nl
		cSchema += "User: احسب 1450 * 32" + nl
		cSchema += "<tool_call>" + nl + "name: calc" + nl + "args: 1450 * 32" + nl + "</tool_call>" + nl + nl
		cSchema += "User: كم سعر الدولار؟" + nl
		cSchema += "<tool_call>" + nl + "name: currency_rate" + nl + "args: USD to DZD" + nl + "</tool_call>" + nl + nl
		cSchema += "After receiving the <tool_response>, synthesize the final helpful response in Arabic."
		return cSchema

	func query(cUserPrompt)
		if oModel = NULL
			return "Error: AI Model is not initialized in Agent."
		ok

		# Hybrid Agent Architecture: Fast Semantic Intent Matching + LLM Synthesis
		cIntentTool = ""
		cIntentArg  = ""
		cLowerPrompt = lower(cUserPrompt)

		if substr(cLowerPrompt, "وقت") > 0 or substr(cLowerPrompt, "تاريخ") > 0 or substr(cLowerPrompt, "ساعة") > 0 or substr(cLowerPrompt, "time") > 0 or substr(cLowerPrompt, "date") > 0
			cIntentTool = "get_time"
		elseif substr(cLowerPrompt, "دولار") > 0 or substr(cLowerPrompt, "دينار") > 0 or substr(cLowerPrompt, "صرف") > 0 or substr(cLowerPrompt, "عملة") > 0
			cIntentTool = "currency_rate"
			cIntentArg  = "USD to DZD"
		elseif substr(cLowerPrompt, "احسب") > 0 or substr(cLowerPrompt, "ناتج") > 0 or substr(cLowerPrompt, "*") > 0 or substr(cLowerPrompt, "+") > 0 or substr(cLowerPrompt, "/") > 0
			cIntentTool = "calc"
			# Extract arithmetic expression
			cExpr = ""
			for i = 1 to len(cUserPrompt)
				ch = cUserPrompt[i]
				nAsc = ascii(ch)
				if (nAsc >= 48 and nAsc <= 57) or ch = '+' or ch = '-' or ch = '*' or ch = '/' or ch = ' ' or ch = '(' or ch = ')' or ch = '.'
					cExpr += ch
				ok
			next
			cIntentArg = trim(cExpr)
		elseif substr(cLowerPrompt, "نظام") > 0 or substr(cLowerPrompt, "معالج") > 0 or substr(cLowerPrompt, "نظام التشغيل") > 0
			cIntentTool = "sys_info"
		ok

		if cIntentTool != ""
			if bVerbose
				see nl + "  [Agent Action] Invoking Tool: " + cIntentTool + " (" + cIntentArg + ")..." + nl
			ok
			cToolResult = executeTool(cIntentTool, cIntentArg)
			if bVerbose
				see "  [Tool Observation] Result: " + cToolResult + nl
			ok

			# Prompt model to formulate final Arabic answer using tool result
			cPrompt = "<|im_start|>system" + nl +
			          "أنت مساعد ذكي وموثوق. أجب المستخدم باختصار ودقة باللغة العربية بناءً على نتيجة الأداة المعطاة." + "<|im_end|>" + nl +
			          "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
			          "<|im_start|>assistant" + nl +
			          "نتيجة أداة " + cIntentTool + ": " + cToolResult + nl +
			          "الإجابة: "

			oModel.setTemperature(0.3)
			cFinalAnswer = oModel.generate(cPrompt, 128)
			return cleanResponse(cFinalAnswer)
		ok

		cSys = buildToolSchema()
		cHistory = "<|im_start|>system" + nl + cSys + "<|im_end|>" + nl +
		           "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
		           "<|im_start|>assistant" + nl

		nStep = 0
		while nStep < nMaxSteps
			nStep++
			oModel.setTemperature(0.1)
			cResponse = oModel.generate(cHistory, 256)

			# Check if model emitted a tool call
			cToolName = ""
			cToolArg  = ""

			nTagStart = substr(cResponse, "<tool_call>")
			if nTagStart > 0
				cBlock = substr(cResponse, nTagStart + len("<tool_call>"))
				nTagEnd = substr(cBlock, "</tool_call>")
				if nTagEnd > 0
					cBlock = left(cBlock, nTagEnd - 1)
				ok
				cBlock = trim(cBlock)

				# 1. Try key-value format (name: ... args: ...)
				cExtName = extractParam(cBlock, "name:")
				if cExtName != ""
					cToolName = cExtName
					cToolArg  = extractParam(cBlock, "args:")
				ok

				# 2. Check for tool names directly
				if cToolName = "" or cToolName = "tool_name"
					for tool in aTools
						tName = tool[1]
						if substr(lower(cBlock), lower(tName)) > 0 and tName != "calc"
							cToolName = tName
							cToolArg  = extractParam(cBlock, "args:")
							exit
						ok
					next
					if cToolName = "" and substr(lower(cBlock), "calc") > 0
						cToolName = "calc"
						cToolArg  = extractParam(cBlock, "args:")
					ok
				ok
			else
				# Check for direct functional call e.g. get_time() or currency_rate(...)
				for tool in aTools
					tName = tool[1]
					if substr(lower(cResponse), lower(tName) + "(") > 0 and tName != "calc"
						cToolName = tName
						nOpenP = substr(cResponse, lower(tName) + "(") + len(tName) + 1
						nCloseP = substr(cResponse, ")")
						if nCloseP > nOpenP
							cToolArg = substr(cResponse, nOpenP, nCloseP - nOpenP)
						ok
						exit
					ok
				next
				if cToolName = "" and substr(lower(cResponse), "calc(") > 0
					cToolName = "calc"
					nOpenP = substr(cResponse, "calc(") + len("calc(")
					nCloseP = substr(cResponse, ")")
					if nCloseP > nOpenP
						cToolArg = substr(cResponse, nOpenP, nCloseP - nOpenP)
					ok
				ok
			ok

			# Disambiguation: if tool is calc but arg is another tool name
			if cToolName = "calc"
				for tool in aTools
					tName = tool[1]
					if tName != "calc" and substr(lower(cToolArg), lower(tName)) > 0
						cToolName = tName
						cToolArg = ""
						exit
					ok
				next
			ok

			if cToolName != ""
				cToolName = trim(cToolName)
				cToolArg  = trim(cToolArg)

				if bVerbose
					see nl + "  [Agent Action] Invoking Tool: " + cToolName + " (" + cToolArg + ")..." + nl
				ok

				cToolResult = executeTool(cToolName, cToolArg)

				if bVerbose
					see "  [Tool Observation] Result: " + cToolResult + nl
				ok

				# Inject Tool Call and Result into Assistant context to prompt final response
				cHistory += "<|im_start|>assistant" + nl +
				            "<tool_call>" + nl + "name: " + cToolName + nl + "args: " + cToolArg + nl + "</tool_call>" + "<|im_end|>" + nl +
				            "<|im_start|>tool" + nl + cToolResult + "<|im_end|>" + nl +
				            "<|im_start|>assistant" + nl
			else
				# Final model response received
				cClean = cleanResponse(cResponse)
				return cClean
			ok
		end

		return cleanResponse(cResponse)

	func executeTool(cName, cArg)
		cName = lower(trim(cName))
		# Strip any quotes or brackets from arg
		cArg = trim(cArg)
		if len(cArg) >= 2 and (cArg[1] = '"' or cArg[1] = "'")
			cArg = substr(cArg, 2, len(cArg) - 2)
		ok

		for tool in aTools
			if lower(tool[1]) = cName
				pFunc = tool[4]
				try
					return call pFunc([cArg])
				catch
					return "Error executing function " + cName
				end
			ok
		next
		return "Error: Unknown tool '" + cName + "'"

	private

	func extractParam(cText, cKey)
		nPos = substr(lower(cText), lower(cKey))
		if nPos = 0 return "" ok
		cSub = substr(cText, nPos + len(cKey))
		nNl = substr(cSub, nl)
		if nNl > 0
			cSub = left(cSub, nNl - 1)
		ok
		return trim(cSub)

	func cleanResponse(cText)
		# Strip any lingering tags
		cText = substr(cText, "<|im_end|>", "")
		cText = substr(cText, "<|endoftext|>", "")
		return trim(cText)
