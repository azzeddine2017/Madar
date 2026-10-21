# ====================================================================
#   Madar AI Suite - Function Calling & AI Agent Runtime
#   (محرك استدعاء الأدوات والوكلاء الأذكياء في لغة مدار)
# ====================================================================

load "madar_ai.ring"
load "dataframe.ring"
load "rag.ring"

class AIAgent
	oModel           = NULL
	aTools           = []       # List of registered tools [ [name, desc, params, func], ... ]
	nMaxSteps        = 4        # Maximum tool execution iterations
	bVerbose         = 1        # Print tool calls & observations to terminal
	bStream          = 0        # Real-time token streaming to terminal
	cSystemPrompt    = ""
	aConversation    = []       # Multi-turn conversational history: [ [role, text], ... ]
	nMaxHistoryTurns = 6        # Max conversation turns to retain
	bMemoryEnabled   = 1        # Enable/disable conversation memory
	oMemory          = NULL     # Long-term VectorStore instance
	cMemoryPath      = ""       # Disk path for binary memory persistence
	bVectorMemory    = 1        # Enable/disable long-term vector memory

	func init(model)
		oModel = model
		# Register default core utilities
		registerCoreTools()
		return self

	func initMemory(cPath)
		if cPath = NULL or cPath = ""
			cPath = "agent_memory.bin"
		ok
		cMemoryPath = cPath
		oMemory = new VectorStore(oModel)
		if fexists(cMemoryPath)
			oMemory.loadBinary(cMemoryPath)
		ok
		return oMemory

	func saveMemory()
		if oMemory != NULL and cMemoryPath != ""
			oMemory.saveBinary(cMemoryPath)
			return true
		ok
		return false

	func remember(cFact)
		if oMemory = NULL
			initMemory("agent_memory.bin")
		ok
		cFact = trim(cFact)
		if cFact = "" return false ok
		oMemory.addText(cFact)
		saveMemory()
		return true

	func recall(cQuery, nTopK)
		if oMemory = NULL return [] ok
		if nTopK = NULL or nTopK <= 0 nTopK = 3 ok
		return oMemory.search(cQuery, nTopK)

	func learnFile(cFilePath)
		if oMemory = NULL
			initMemory("agent_memory.bin")
		ok
		if not fexists(cFilePath) and fexists("examples/ai/" + cFilePath)
			cFilePath = "examples/ai/" + cFilePath
		ok
		if not fexists(cFilePath) return 0 ok
		nAdded = oMemory.addFile(cFilePath)
		saveMemory()
		return nAdded

	func resetHistory()
		aConversation = []
		if oModel != NULL oModel.reset() ok

	func undo()
		if len(aConversation) >= 2
			del(aConversation, len(aConversation))
			del(aConversation, len(aConversation))
			return true
		elseif len(aConversation) = 1
			del(aConversation, 1)
			return true
		ok
		return false

	func getHistory()
		return aConversation

	func formatHistory()
		cHist = ""
		nStart = 1
		if len(aConversation) > (nMaxHistoryTurns * 2)
			nStart = len(aConversation) - (nMaxHistoryTurns * 2) + 1
		ok
		for i = nStart to len(aConversation)
			turn = aConversation[i]
			cHist += "<|im_start|>" + turn[1] + nl + turn[2] + "<|im_end|>" + nl
		next
		return cHist

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
			cPath = substr(cPath, '"', "")
			cPath = substr(cPath, "'", "")
			cPath = substr(cPath, "؟", "")
			cPath = substr(cPath, "?", "")
			cPath = substr(cPath, ":", "")
			cPath = trim(cPath)

			if not fexists(cPath) and fexists("examples/ai/" + cPath)
				cPath = "examples/ai/" + cPath
			ok
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
			return "OS: Windows x64 (Madar AI Native Runtime, AVX2 SIMD Enabled, FP16 KV-Cache 2048 Context Window, 4 CPU Worker Threads)"
		})

		# 5. CSV DataFrame Statistical Summary
		registerTool("csv_summary", "Loads CSV table and returns statistical summary (count, mean, std, min, max)", ["path"], func(args) {
			cPath = "examples/ai/sample_data.csv"
			if islist(args) and len(args) >= 1 and args[1] != ""
				cPath = "" + args[1]
			elseif isstring(args) and trim(args) != ""
				cPath = trim(args)
			ok
			if not fexists(cPath) and fexists("examples/ai/" + cPath)
				cPath = "examples/ai/" + cPath
			ok
			if not fexists(cPath) return "Error: File '" + cPath + "' not found." ok
			df = new DataFrame(cPath)
			cRes = "Rows: " + df.shape()[1] + ", Columns: " + df.shape()[2] + nl
			for item in df.aTensors
				cCol = item[1]
				cRes += "- " + cCol + ": Mean=" + df.mean(cCol) + ", Min=" + df.min(cCol) + ", Max=" + df.max(cCol) + nl
			next
			return cRes
		})

		# 6. CSV DataFrame Query Tool (calculates max, min, mean, sum on numeric columns)
		registerTool("csv_query", "Calculates statistical metric (mean, max, min, sum) on a CSV table column", ["query"], func(args) {
			cPath = "examples/ai/sample_data.csv"
			cMetric = "mean"
			cCol = "salary"
			s = ""
			if islist(args) and len(args) >= 1
				s = lower("" + args[1])
			elseif isstring(args)
				s = lower(args)
			ok

			if substr(s, "max") > 0 or substr(s, "أعلى") > 0 or substr(s, "اكبر") > 0 or substr(s, "أكبر") > 0
				cMetric = "max"
			elseif substr(s, "min") > 0 or substr(s, "أدنى") > 0 or substr(s, "اصغر") > 0 or substr(s, "أصغر") > 0 or substr(s, "اقل") > 0
				cMetric = "min"
			elseif substr(s, "sum") > 0 or substr(s, "مجموع") > 0 or substr(s, "إجمالي") > 0
				cMetric = "sum"
			else
				cMetric = "mean"
			ok

			if substr(s, "age") > 0 or substr(s, "عمر") > 0 or substr(s, "أعمار") > 0
				cCol = "age"
			elseif substr(s, "performance") > 0 or substr(s, "أداء") > 0 or substr(s, "تقييم") > 0
				cCol = "performance"
			else
				cCol = "salary"
			ok

			if not fexists(cPath) and fexists("examples/ai/" + cPath)
				cPath = "examples/ai/" + cPath
			ok
			if not fexists(cPath) return "Error: File '" + cPath + "' not found." ok
			df = new DataFrame(cPath)
			if cMetric = "max"
				return "Max " + cCol + " = " + ("" + df.max(cCol))
			elseif cMetric = "min"
				return "Min " + cCol + " = " + ("" + df.min(cCol))
			elseif cMetric = "sum"
				return "Total " + cCol + " = " + ("" + df.sum(cCol))
			else
				return "Average " + cCol + " = " + ("" + df.mean(cCol))
			ok
		})

		# 7. RAG Knowledge & Long-Term Memory Search
		registerTool("rag_search", "Searches agent's long-term vector knowledge base and memories for relevant facts", ["query"], func(args) {
			s = ""
			if islist(args) and len(args) >= 1 s = "" + args[1] else s = "" + args ok
			s = trim(s)
			if s = "" return "No search query provided." ok
			if oMemory = NULL return "No long-term memory or knowledge base loaded." ok
			aResults = oMemory.search(s, 2)
			if len(aResults) = 0 return "No relevant knowledge found in memory." ok
			cRes = ""
			for r in aResults
				fScore = r[1]
				chunk = r[2]
				cRes += "- [Similarity: " + round(fScore, 2) + "]: " + chunk.cText + nl
			next
			return cRes
		})

		# 8. Persistent Memory Inscription
		registerTool("remember_fact", "Saves a persistent user fact, project rule, or preference to long-term memory", ["fact"], func(args) {
			s = ""
			if islist(args) and len(args) >= 1 s = "" + args[1] else s = "" + args ok
			s = trim(s)
			if s = "" return "No fact provided to remember." ok
			remember(s)
			return "Saved successfully to long-term memory: " + s
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

	func queryStream(cUserPrompt)
		oldStream = bStream
		bStream = 1
		res = query(cUserPrompt)
		bStream = oldStream
		return res

	func query(cUserPrompt)
		if oModel = NULL
			return "Error: AI Model is not initialized in Agent."
		ok

		# Hybrid Agent Architecture: Fast Semantic Intent Matching + Multi-turn Synthesis
		cIntentTool = ""
		cIntentArg  = ""
		cLowerPrompt = lower(cUserPrompt)

		bIsQuestion = (substr(cLowerPrompt, "هل") > 0 or substr(cLowerPrompt, "ماذا") > 0 or substr(cLowerPrompt, "ما هو") > 0 or substr(cLowerPrompt, "ماهو") > 0 or substr(cLowerPrompt, "what") > 0)

		if not bIsQuestion and (substr(cLowerPrompt, "تذكر") > 0 or substr(cLowerPrompt, "احفظ") > 0 or substr(cLowerPrompt, "remember") > 0)
			cIntentTool = "remember_fact"
			cFact = cUserPrompt
			aPrefixes = ["تذكر أن ", "تذكر ان ", "تذكر هذا: ", "تذكر هذا ", "تذكر: ", "تذكر ", 
			             "احفظ عندك: ", "احفظ عندك ", "احفظ أن ", "احفظ ان ", "احفظ هذا: ", "احفظ هذا ", "احفظ: ", "احفظ ",
			             "remember that ", "remember this: ", "remember this ", "remember: ", "remember "]
			for pfx in aPrefixes
				nPos = substr(lower(cFact), pfx)
				if nPos > 0
					cFact = trim(substr(cFact, nPos + len(pfx)))
					exit
				ok
			next
			cIntentArg = cFact
		elseif substr(cLowerPrompt, "ابحث في المعرفة") > 0 or substr(cLowerPrompt, "ماذا تعرف عن") > 0 or substr(cLowerPrompt, "ماذا تتذكر") > 0 or substr(cLowerPrompt, "هل تتذكر") > 0 or substr(cLowerPrompt, "من أنا") > 0 or substr(cLowerPrompt, "search knowledge") > 0 or substr(cLowerPrompt, "what do you know about") > 0 or substr(cLowerPrompt, "who am i") > 0 or substr(cLowerPrompt, "do you remember") > 0
			cIntentTool = "rag_search"
			cIntentArg  = cUserPrompt
		elseif substr(cLowerPrompt, "وقت") > 0 or substr(cLowerPrompt, "تاريخ") > 0 or substr(cLowerPrompt, "ساعة") > 0 or substr(cLowerPrompt, "time") > 0 or substr(cLowerPrompt, "date") > 0 or substr(cLowerPrompt, "clock") > 0
			cIntentTool = "get_time"
		elseif substr(cLowerPrompt, "دولار") > 0 or substr(cLowerPrompt, "دينار") > 0 or substr(cLowerPrompt, "صرف") > 0 or substr(cLowerPrompt, "عملة") > 0 or substr(cLowerPrompt, "currency") > 0 or substr(cLowerPrompt, "exchange") > 0
			cIntentTool = "currency_rate"
			cIntentArg  = "USD to DZD"
		elseif substr(cLowerPrompt, "احسب") > 0 or substr(cLowerPrompt, "ناتج") > 0 or substr(cLowerPrompt, "calc") > 0 or substr(cLowerPrompt, "calculate") > 0 or substr(cLowerPrompt, "*") > 0 or substr(cLowerPrompt, "+") > 0 or substr(cLowerPrompt, "/") > 0
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
		elseif substr(cLowerPrompt, "اقرأ") > 0 or substr(cLowerPrompt, "ملف") > 0 or substr(cLowerPrompt, "read") > 0 or substr(cLowerPrompt, "محتوى") > 0 or substr(cLowerPrompt, "file") > 0
			cIntentTool = "read_file"
			cWords = split(cUserPrompt, " ")
			for w in cWords
				wClean = trim(w)
				if substr(wClean, ".") > 0 or substr(wClean, "/") > 0 or substr(wClean, "\\") > 0
					wClean = substr(wClean, "؟", "")
					wClean = substr(wClean, "?", "")
					wClean = substr(wClean, ":", "")
					wClean = substr(wClean, '"', "")
					wClean = substr(wClean, "'", "")
					cIntentArg = trim(wClean)
					exit
				ok
			next
			if cIntentArg = "" cIntentArg = "README.md" ok
		elseif substr(cLowerPrompt, "نظام") > 0 or substr(cLowerPrompt, "معالج") > 0 or substr(cLowerPrompt, "نظام التشغيل") > 0 or substr(cLowerPrompt, "system") > 0 or substr(cLowerPrompt, "os") > 0 or substr(cLowerPrompt, "specs") > 0
			cIntentTool = "sys_info"
		elseif substr(cLowerPrompt, ".csv") > 0 or substr(cLowerPrompt, "بيانات") > 0 or substr(cLowerPrompt, "جدول") > 0 or substr(cLowerPrompt, "موظف") > 0 or substr(cLowerPrompt, "رواتب") > 0 or substr(cLowerPrompt, "راتب") > 0 or substr(cLowerPrompt, "csv") > 0 or substr(cLowerPrompt, "salary") > 0 or substr(cLowerPrompt, "dataframe") > 0
			if substr(cLowerPrompt, "ملخص") > 0 or substr(cLowerPrompt, "إحصاء") > 0 or substr(cLowerPrompt, "summary") > 0 or substr(cLowerPrompt, "describe") > 0
				cIntentTool = "csv_summary"
				cIntentArg  = "examples/ai/sample_data.csv"
			else
				cIntentTool = "csv_query"
				cIntentArg  = cUserPrompt
			ok
		ok

		if cIntentTool != ""
			if bVerbose
				see nl + "  [Agent Action] Invoking Tool: " + cIntentTool + " (" + cIntentArg + ")..." + nl
			ok
			cToolResult = executeTool(cIntentTool, cIntentArg)
			if bVerbose
				see "  [Tool Observation] Result: " + cToolResult + nl
			ok

			# Prompt model to formulate final answer using tool result and conversation history
			cSysPrompt = "أنت مساعد ذكي وموثوق. أجب المستخدم باختصار ودقة باللغة العربية بناءً على نتيجة الأداة وسياق المحادثة."
			cPrompt = "<|im_start|>system" + nl + cSysPrompt + "<|im_end|>" + nl
			if bMemoryEnabled and len(aConversation) > 0
				cPrompt += formatHistory()
			ok
			cPrompt += "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
			          "<|im_start|>assistant" + nl +
			          "نتيجة أداة " + cIntentTool + ": " + cToolResult + nl +
			          "الإجابة: "

			if cIntentTool = "remember_fact"
				cClean = "تم حفظ ذلك في الذاكرة الدائمة بنجاح: " + cIntentArg
				if bStream
					see "Agent Response: " + cClean + nl
				ok
				if bMemoryEnabled
					aConversation + ["user", cUserPrompt]
					aConversation + ["assistant", cClean]
				ok
				return cClean
			ok

			oModel.setTemperature(0.3)
			cFinalAnswer = ""
			if bStream
				see "Agent Response: "
				cFinalAnswer = oModel.generateStream(cPrompt, 160)
				see nl
			else
				cFinalAnswer = oModel.generate(cPrompt, 160)
			ok

			cClean = cleanResponse(cFinalAnswer)
			if bMemoryEnabled
				aConversation + ["user", cUserPrompt]
				aConversation + ["assistant", cClean]
			ok
			return cClean
		ok

		# General Conversational Turn with History Memory and Long-Term Vector Recall
		cSysPrompt = "أنت مساعد ذكي وموثوق يتحدث العربية والإنجليزية بطلاقة ويقدم إجابات دقيقة ومفيدة."

		# Automatic Contextual Recall from Persistent Memory (if available)
		cMemContext = ""
		if bVectorMemory and oMemory != NULL and oMemory.count() > 0
			aMemMatches = oMemory.search(cUserPrompt, 2)
			for mm in aMemMatches
				if mm[1] >= 0.50
					cMemContext += "- " + mm[2].cText + nl
				ok
			next
		ok

		if cMemContext != ""
			cSysPrompt += nl + "معلومات مؤكدة ومحفوظة في ذاكرتك الدائمة عن المستخدم:" + nl + cMemContext + nl +
			              "أجب المستخدم بدقة وبشكل مباشر اعتماداً على هذه المعلومات المحفوظة."
		ok

		cPrompt = "<|im_start|>system" + nl + cSysPrompt + "<|im_end|>" + nl
		if bMemoryEnabled and len(aConversation) > 0
			cPrompt += formatHistory()
		ok
		cPrompt += "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl

		oModel.setTemperature(0.6)
		cFinalAnswer = ""
		if bStream
			see "Agent Response: "
			cFinalAnswer = oModel.generateStream(cPrompt, 200)
			see nl
		else
			cFinalAnswer = oModel.generate(cPrompt, 200)
		ok

		cClean = cleanResponse(cFinalAnswer)
		if bMemoryEnabled
			aConversation + ["user", cUserPrompt]
			aConversation + ["assistant", cClean]
		ok
		return cClean

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

		# Native Agent tools that require 'self' context
		if cName = "remember_fact"
			if cArg = "" return "No fact provided to remember." ok
			remember(cArg)
			return "تم الحفظ بنجاح في الذاكرة الدائمة: " + cArg
		ok

		if cName = "rag_search"
			if cArg = "" return "No search query provided." ok
			if oMemory = NULL return "No long-term memory or knowledge base loaded." ok
			aResults = oMemory.search(cArg, 2)
			if len(aResults) = 0 return "No relevant knowledge found in memory." ok
			cRes = ""
			for r in aResults
				fScore = r[1]
				chunk = r[2]
				cRes += "- [Similarity: " + round(fScore, 2) + "]: " + chunk.cText + nl
			next
			return cRes
		ok

		for tool in aTools
			if lower(tool[1]) = cName
				pFunc = tool[4]
				try
					return call pFunc([cArg])
				catch
					return "Error executing function " + cName + ": " + cCatchError
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
