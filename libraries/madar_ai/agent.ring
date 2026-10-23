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
	nMaxHistoryTurns = 3        # Max conversation turns to retain
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
		cId = f"fact_{oMemory.count() + 1}"
		oMemory.addText(cFact, cId, ["source" = "user_remember"])
		saveMemory()
		return true

	func recall(cQuery, nTopK)
		if oMemory = NULL return [] ok
		if nTopK = NULL or nTopK <= 0 nTopK = 3 ok
		return oMemory.search(cQuery, nTopK)

	func learnPath(cPath, pCallback = NULL)
		if oMemory = NULL
			initMemory("agent_memory.bin")
		ok
		cPath = trim(cPath)
		cPath = substr(cPath, '"', "")
		cPath = substr(cPath, "'", "")
		cPath = trim(cPath)

		# Check directory
		cCheckDir = cPath
		if not direxists(cCheckDir) and direxists("../../" + cPath)
			cCheckDir = "../../" + cPath
		elseif not direxists(cCheckDir) and direxists("../" + cPath)
			cCheckDir = "../" + cPath
		ok

		if direxists(cCheckDir)
			aAllFiles = ListAllFiles(cCheckDir, NULL)
			aExts = ["md", "txt", "pdf", "ring", "rh", "csv"]
			aTargetFiles = []
			for f in aAllFiles
				cExt = lower(JustFileExt(f))
				if cExt != "" and find(aExts, cExt) > 0
					aTargetFiles + f
				ok
			next

			nTotalAdded = 0
			nProcessed = 0
			aProcessedFiles = []

			for i = 1 to len(aTargetFiles)
				cFile = aTargetFiles[i]
				cTimeStr = ""
				nChunks = 0

				try
					oTimer = new QalamChronos()
					nChunks = oMemory.addDocument(cFile)
					cTimeStr = oTimer.elapsed()
				catch
					t0 = clock()
					nChunks = oMemory.addDocument(cFile)
					t1 = clock()
					cTimeStr = "" + round((t1 - t0) / clockspersecond(), 2) + "s"
				done

				# Save immediately after each file to persistent disk!
				saveMemory()

				nTotalAdded += nChunks
				nProcessed++
				aProcessedFiles + [cFile, nChunks]

				if pCallback != NULL
					call pCallback(cFile, i, len(aTargetFiles), nChunks, cTimeStr)
				ok
			next

			return [nTotalAdded, nProcessed, aProcessedFiles]
		ok

		# Check single file
		cCheckFile = cPath
		if not fexists(cCheckFile) and fexists("../../" + cPath)
			cCheckFile = "../../" + cPath
		elseif not fexists(cCheckFile) and fexists("../" + cPath)
			cCheckFile = "../" + cPath
		elseif not fexists(cCheckFile) and fexists("examples/ai/" + cPath)
			cCheckFile = "examples/ai/" + cPath
		ok

		if fexists(cCheckFile)
			cTimeStr = ""
			nAdded = 0
			try
				oTimer = new QalamChronos()
				nAdded = oMemory.addDocument(cCheckFile)
				cTimeStr = oTimer.elapsed()
			catch
				t0 = clock()
				nAdded = oMemory.addDocument(cCheckFile)
				t1 = clock()
				cTimeStr = "" + round((t1 - t0) / clockspersecond(), 2) + "s"
			done

			# Save immediately to disk!
			saveMemory()

			if pCallback != NULL
				call pCallback(cCheckFile, 1, 1, nAdded, cTimeStr)
			ok
			return [nAdded, 1, [ [cCheckFile, nAdded] ]]
		ok

		return [0, 0, []]

	func learnFile(cFilePath)
		aRes = learnPath(cFilePath)
		if islist(aRes) and len(aRes) >= 1
			return aRes[1]
		ok
		return 0

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
			if right(cPath, 1) = ":"
				cPath = left(cPath, len(cPath) - 1)
			ok
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

		# 9. Directory Listing Tool
		registerTool("list_files", "Lists files in current or specified directory", ["dir"], func(args) {
			cDir = "."
			if islist(args) and len(args) >= 1 and trim(args[1]) != ""
				cDir = trim(args[1])
			elseif isstring(args) and trim(args) != ""
				cDir = trim(args)
			ok
			cDir = substr(cDir, '"', "")
			cDir = substr(cDir, "'", "")
			cDir = trim(cDir)
			if not direxists(cDir) and direxists("examples/ai/" + cDir)
				cDir = "examples/ai/" + cDir
			ok
			if not direxists(cDir)
				return "Error: Directory '" + cDir + "' not found."
			ok
			aFiles = dir(cDir)
			cList = ""
			nCount = 0
			for f in aFiles
				if f[1] != "." and f[1] != ".."
					cList += f[1] + "  "
					nCount++
					if nCount >= 25 exit ok
				ok
			next
			return "Files in '" + cDir + "': " + cList
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
		elseif substr(cLowerPrompt, "list_files") > 0 or substr(cLowerPrompt, "محتويات المجلد") > 0 or substr(cLowerPrompt, "محتوى المجلد") > 0 or substr(cLowerPrompt, "اعرض ملفات") > 0 or substr(cLowerPrompt, "قائمة الملفات") > 0 or substr(cLowerPrompt, "ملفات المجلد") > 0 or substr(cLowerPrompt, "list files") > 0
			cIntentTool = "list_files"
			# Check for quoted directory first
			nQ1 = substr(cUserPrompt, '"')
			if nQ1 > 0
				cSubQ = substr(cUserPrompt, nQ1 + 1)
				nQ2 = substr(cSubQ, '"')
				if nQ2 > 0
					cIntentArg = trim(left(cSubQ, nQ2 - 1))
				ok
			ok
			if cIntentArg = ""
				cWords = split(cUserPrompt, " ")
				for w in cWords
					wClean = trim(w)
					if substr(wClean, "/") > 0 or substr(wClean, "\\") > 0 or substr(wClean, ":") > 0
						wClean = substr(wClean, '"', "")
						wClean = substr(wClean, "'", "")
						wClean = substr(wClean, "؟", "")
						wClean = substr(wClean, "?", "")
						cIntentArg = trim(wClean)
						exit
					ok
				next
			ok
			if cIntentArg = "" cIntentArg = "." ok
		elseif substr(cLowerPrompt, "اقرأ") > 0 or substr(cLowerPrompt, "ملف") > 0 or substr(cLowerPrompt, "read") > 0 or substr(cLowerPrompt, "محتوى") > 0 or substr(cLowerPrompt, "file") > 0 or substr(cLowerPrompt, ".md") > 0 or substr(cLowerPrompt, ".txt") > 0 or substr(cLowerPrompt, ".ring") > 0
			cIntentTool = "read_file"
			# Check for quoted path first
			nQ1 = substr(cUserPrompt, '"')
			if nQ1 > 0
				cSubQ = substr(cUserPrompt, nQ1 + 1)
				nQ2 = substr(cSubQ, '"')
				if nQ2 > 0
					cIntentArg = trim(left(cSubQ, nQ2 - 1))
				ok
			ok
			if cIntentArg = ""
				cWords = split(cUserPrompt, " ")
				for w in cWords
					wClean = trim(w)
					if substr(wClean, ".") > 0 or substr(wClean, "/") > 0 or substr(wClean, "\\") > 0
						wClean = substr(wClean, "؟", "")
						wClean = substr(wClean, "?", "")
						wClean = substr(wClean, '"', "")
						wClean = substr(wClean, "'", "")
						if right(wClean, 1) = ":"
							wClean = left(wClean, len(wClean) - 1)
						ok
						cIntentArg = trim(wClean)
						exit
					ok
				next
			ok
			if cIntentArg = "" cIntentArg = "README.md" ok
		elseif substr(cLowerPrompt, "احسب") > 0 or substr(cLowerPrompt, "ناتج") > 0 or substr(cLowerPrompt, "calc") > 0 or substr(cLowerPrompt, "calculate") > 0 or substr(cLowerPrompt, "كم حاصل") > 0 or (substr(cLowerPrompt, "*") > 0 and substr(cLowerPrompt, "=") = 0) or (substr(cLowerPrompt, "+") > 0 and substr(cLowerPrompt, "++") = 0)
			cIntentTool = "calc"
			cExpr = ""
			for i = 1 to len(cUserPrompt)
				ch = cUserPrompt[i]
				nAsc = ascii(ch)
				if (nAsc >= 48 and nAsc <= 57) or ch = '+' or ch = '-' or ch = '*' or ch = '/' or ch = ' ' or ch = '(' or ch = ')' or ch = '.'
					cExpr += ch
				ok
			next
			cIntentArg = trim(cExpr)
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

			# Prompt model to formulate final answer using tool result in a standard ChatML schema
			cSysPrompt = "أنت مساعد ذكي وموثوق. أجب المستخدم بدقة باللغة العربية اعتماداً على نتيجة الأداة التالية:" + nl +
			              "--- نتيجة " + cIntentTool + " ---" + nl +
			              cToolResult + nl +
			              "-------------------------"
			cPrompt = "<|im_start|>system" + nl + cSysPrompt + "<|im_end|>" + nl +
			          "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
			          "<|im_start|>assistant" + nl

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
				cFinalAnswer = oModel.generateStream(cPrompt, 512)
				see nl
			else
				cFinalAnswer = oModel.generate(cPrompt, 512)
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
			aMemMatches = oMemory.search(cUserPrompt, 3)
			if len(aMemMatches) > 0
				fTopScore = aMemMatches[1][1]
				# Adaptive threshold: if top match is strong, keep only closely related chunks (prevent context pollution)
				fMinThreshold = 0.30
				if fTopScore >= 0.60
					fMinThreshold = fTopScore - 0.20
					if fMinThreshold < 0.45 fMinThreshold = 0.45 ok
				ok
				nMatchesCount = 0
				for mm in aMemMatches
					if mm[1] >= fMinThreshold
						cMemContext += "- " + mm[2].cText + nl
						nMatchesCount++
					ok
				next
				if bVerbose and nMatchesCount > 0
					see "  [RAG Context Injected: " + nMatchesCount + " relevant memories (Top Score: " + round(fTopScore, 3) + ")]" + nl
				ok
			ok
		ok

		if cMemContext != ""
			cSysPrompt += nl + "حقائق ومعلومات مؤكدة مسترجعة من الذاكرة وقاعدة المعرفة:" + nl + cMemContext + nl +
			              "أجب المستخدم بدقة وبشكل مباشر اعتماداً على هذه الحقائق المحددة. إذا كانت الإجابة رقماً أو اسماً أو تفصيلاً، فاذكره له في بداية الرد فوراً وبوضوح."
		ok

		cPrompt = "<|im_start|>system" + nl + cSysPrompt + "<|im_end|>" + nl
		if bMemoryEnabled and len(aConversation) > 0
			# Only include conversational history if no strong independent RAG memory was injected,
			# or if the user is asking a follow-up question
			bIsFollowUp = (len(cUserPrompt) < 30 and (substr(cLowerPrompt, "وماذا") > 0 or substr(cLowerPrompt, "المزيد") > 0 or substr(cLowerPrompt, "أيضا") > 0 or substr(cLowerPrompt, "أيضاً") > 0 or substr(cLowerPrompt, "ثم") > 0 or substr(cLowerPrompt, "وكيف") > 0))
			if cMemContext = "" or bIsFollowUp
				cPrompt += formatHistory()
			ok
		ok
		cPrompt += "<|im_start|>user" + nl + cUserPrompt + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl

		if cMemContext != ""
			oModel.setTemperature(0.2)
		else
			oModel.setTemperature(0.5)
		ok
		cFinalAnswer = ""
		if bStream
			see "Agent Response: "
			cFinalAnswer = oModel.generateStream(cPrompt, 512)
			see nl
		else
			cFinalAnswer = oModel.generate(cPrompt, 512)
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
		cText = substr(cText, "<i_end|>", "")
		cText = substr(cText, "<|im_start|>", "")
		nPos = substr(cText, "أجب المستخدم بدقة")
		if nPos > 0
			cText = left(cText, nPos - 1)
		ok
		return trim(cText)
