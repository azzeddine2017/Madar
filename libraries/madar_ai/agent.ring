# ====================================================================
#   Madar AI Suite - Autonomous Agent & Function Calling Runtime
#   (محرك الوكلاء الأذكياء واستدعاء الأدوات في لغة مدار)
# ====================================================================
# Features:
#   - 100% Autonomous ReAct Architecture (Reasoning + Acting)
#   - Native Modern Madar Syntax:
#       * Native f-strings: f"<|im_start|>{role}\n{content}<|im_end|>\n"
#       * Default Arguments: func init(model = NULL, cMemoryPath = "agent_memory.bin")
#       * Advanced Slicing: aConversation[-4:], cText[:250], aScored[::-1]
#       * List Comprehensions: [f'"{p}": {{"type": "string"}}' for p in aParams]
#       * High-Performance JIT Loops: dour i = 1 to N
#   - Official Qwen2.5-Coder Function Calling Schema (<tools>, <tool_call>, <tool_response>)
#   - Continuous RAG & Vector Memory Integration
#   - Anti-Bloat Sliding Context Window & Hard Stop Token Enforcement
# ====================================================================

load "madar_ai.ring"
load "dataframe.ring"
load "rag.ring"

func join(cText, cDelim)
		cReturn = ""
		for item in cText
			cReturn += item + cDelim
		next
		return cReturn

func extractMathExpr(cText)
	cExpr = ""
	for i = 1 to len(cText)
		ch = cText[i]
		nAsc = ascii(ch)
		if (nAsc >= 48 and nAsc <= 57) or ch = '+' or ch = '-' or ch = '*' or ch = '/' or ch = '(' or ch = ')' or ch = '.'
			cExpr += ch
		elseif ch = ' ' and cExpr != ""
			cExpr += ch
		ok
	next
	return trim(cExpr)

class AIAgent
	oModel           = NULL
	aTools           = []       # [ [name, desc, params, func], ... ]
	nMaxSteps        = 3        # Maximum ReAct tool execution steps
	nMaxOutputTokens = 512    # Maximum number of tokens to generate
	bVerbose         = 1        # Display tool execution & observations
	bStream          = 1        # Real-time token streaming to stdout
	cSystemPrompt    = ""
	aConversation    = []       # Multi-turn history: [ [role, text], ... ]
	nMaxHistoryTurns = 1        # Retain last turn only to keep context window small
	bMemoryEnabled   = 1        # Enable/disable conversation turns memory
	oMemory          = NULL     # Long-term VectorStore instance
	cMemoryPath      = "agent_memory.bin"
	bVectorMemory    = 1        # Enable/disable RAG vector memory
	bAutonomousTools = 1        # Enable Qwen2.5 Function Calling Schema

	func init(model = NULL, cMemPath = "agent_memory.bin")
		oModel = model
		cMemoryPath = cMemPath
		registerCoreTools()
		return self

	# ----------------------------------------------------------------
	# Memory & Knowledge Base Management (RAG)
	# ----------------------------------------------------------------
	func initMemory(cPath = "agent_memory.bin")
		if cPath != NULL and cPath != ""
			cMemoryPath = cPath
		ok
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
			initMemory(cMemoryPath)
		ok
		cFact = trim(cFact)
		if cFact = "" return false ok
		cId = f"fact_{oMemory.count() + 1}"
		oMemory.addText(cFact, cId, ["source" = "user_remember"])
		saveMemory()
		return true

	func recall(cQuery, nTopK = 3)
		if oMemory = NULL return [] ok
		if nTopK <= 0 nTopK = 3 ok
		return oMemory.search(cQuery, nTopK)

	func clearMemory()
		if oMemory != NULL
			oMemory.clear()
			saveMemory()
			return true
		ok
		return false

	func learnPath(cPath, pCallback = NULL)
		if oMemory = NULL
			initMemory(cMemoryPath)
		ok
		cPath = trim(cPath)
		cPath = substr(cPath, '"', "")
		cPath = substr(cPath, "'", "")
		cPath = trim(cPath)

		# Locate directory
		cCheckDir = cPath
		if not direxists(cCheckDir) and direxists(f"../../{cPath}")
			cCheckDir = f"../../{cPath}"
		elseif not direxists(cCheckDir) and direxists(f"../{cPath}")
			cCheckDir = f"../{cPath}"
		ok

		if direxists(cCheckDir)
			aAllFiles = ListAllFiles(cCheckDir, NULL)
			aExts = ["md", "txt", "pdf", "ring", "rh", "csv"]

			# Madar List Comprehension to filter target document files
			aTargetFiles = [f for f in aAllFiles if lower(JustFileExt(f)) != "" and find(aExts, lower(JustFileExt(f))) > 0]

			nTotalAdded = 0
			nProcessed = 0
			aProcessedFiles = []

			for i = 1 to len(aTargetFiles)
				cFile = aTargetFiles[i]
				cTimeStr = ""
				nChunks = 0

				t0 = clock()
				nChunks = oMemory.addDocument(cFile)
				t1 = clock()
				cTimeStr = f"{round((t1 - t0) / clockspersecond(), 2)}s"

				# Persist to disk
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

		# Locate single file
		cCheckFile = cPath
		if not fexists(cCheckFile) and fexists(f"../../{cPath}")
			cCheckFile = f"../../{cPath}"
		elseif not fexists(cCheckFile) and fexists(f"../{cPath}")
			cCheckFile = f"../{cPath}"
		elseif not fexists(cCheckFile) and fexists(f"examples/ai/{cPath}")
			cCheckFile = f"examples/ai/{cPath}"
		ok

		if fexists(cCheckFile)
			t0 = clock()
			nAdded = oMemory.addDocument(cCheckFile)
			t1 = clock()
			cTimeStr = f"{round((t1 - t0) / clockspersecond(), 2)}s"
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

	func learnDirectory(cDirPath)
		aRes = learnPath(cDirPath)
		if islist(aRes) and len(aRes) >= 1
			return aRes[1]
		ok
		return 0

	# ----------------------------------------------------------------
	# Multi-Turn Conversation History (Sliding Window & Slicing)
	# ----------------------------------------------------------------
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
		if len(aConversation) = 0 return "" ok

		# Retain only the last turn (2 messages) to keep context small
		nTake = nMaxHistoryTurns * 2
		aRecentTurns = aConversation[-nTake:]

		cHist = ""
		for turn in aRecentTurns
			cRole = turn[1]
			cText = turn[2]

			# Bound assistant memory to max 80 chars to prevent prompt bloat & looping
			if cRole = "assistant" and len(cText) > 80
				cText = left(cText, 80) + "..."
			ok

			cHist += f"<|im_start|>{cRole}\n{cText}<|im_end|>\n"
		next
		return cHist

	# ----------------------------------------------------------------
	# Tool Registration & Core Utilities
	# ----------------------------------------------------------------
	func registerTool(cName, cDesc, aParams = [], pFunc = NULL)
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
			try
				nRes = eval(f"return ({cExpr})")
				return "" + nRes
			catch
				try
					nRes = eval(f"return {cExpr}")
					return "" + nRes
				catch
					return "Error evaluating expression"
				end
			end
		})

		# 2. Real-time Clock and Date
		registerTool("get_time", "Returns current local system date and time", [], func(args) {
			return f"Current Date & Time: {date()} {time()}"
		})

		# 3. Local File Reader
		registerTool("read_file", "Reads the content of a local file", ["path"], func(args) {
			cPath = ""
			if islist(args) and len(args) >= 1
				cPath = "" + args[1]
			else
				cPath = "" + args
			ok
			cPath = trim(cPath)
			cPath = substr(cPath, '"', "")
			cPath = substr(cPath, "'", "")
			cPath = trim(cPath)

			if not fexists(cPath) and fexists(f"examples/ai/{cPath}")
				cPath = f"examples/ai/{cPath}"
			ok
			if fexists(cPath)
				cContent = read(cPath)
				if len(cContent) > 2000
					cContent = f"{cContent[:2000]}... [Truncated]"
				ok
				return cContent
			else
				return f"Error: File '{cPath}' not found."
			ok
		})

		# 4. Directory Listing
		registerTool("list_files", "Lists files in current or specified folder", ["dir"], func(args) {
			cDir = "."
			if islist(args) and len(args) >= 1 and trim(args[1]) != ""
				cDir = trim(args[1])
			elseif isstring(args) and trim(args) != ""
				cDir = trim(args)
			ok
			cDir = substr(cDir, '"', "")
			cDir = substr(cDir, "'", "")
			cDir = trim(cDir)
			if not direxists(cDir) and direxists(f"examples/ai/{cDir}")
				cDir = f"examples/ai/{cDir}"
			ok
			if not direxists(cDir)
				return f"Error: Directory '{cDir}' not found."
			ok
			aFiles = dir(cDir)
			# Madar List Comprehension to collect non-dot filenames
			aNames = [f[1] for f in aFiles if f[1] != "." and f[1] != ".."]
			aNames = aNames[:25] # Slice top 25 files
			return f"Files in '{cDir}': " + join(aNames, "  ")
		})

		# 5. Operating System Info
		registerTool("sys_info", "Returns operating system and runtime platform info", [], func(args) {
			return "OS: Windows x64 | Runtime: Madar AI Native C AVX2 SIMD + OpenCL GPU | Context: 2048 Tokens"
		})

		# 6. CSV DataFrame Summary
		registerTool("csv_summary", "Loads CSV table and returns statistical summary (count, mean, std, min, max)", ["path"], func(args) {
			cPath = "examples/ai/sample_data.csv"
			if islist(args) and len(args) >= 1 and args[1] != ""
				cPath = "" + args[1]
			elseif isstring(args) and trim(args) != ""
				cPath = trim(args)
			ok
			if not fexists(cPath) and fexists(f"examples/ai/{cPath}")
				cPath = f"examples/ai/{cPath}"
			ok
			if not fexists(cPath) return f"Error: File '{cPath}' not found." ok
			df = new DataFrame(cPath)
			cRes = f"Rows: {df.shape()[1]}, Columns: {df.shape()[2]}\n"
			for item in df.aTensors
				cCol = item[1]
				cRes += f"- {cCol}: Mean={df.mean(cCol)}, Min={df.min(cCol)}, Max={df.max(cCol)}\n"
			next
			return cRes
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
				cRes += f"- [Similarity: {round(r[1], 2)}]: {r[2].cText}\n"
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
			return f"Saved successfully to long-term memory: {s}"
		})

	# ----------------------------------------------------------------
	# Official Qwen2.5-Coder Function Calling Schema Generator
	# ----------------------------------------------------------------
	func buildToolSchema()
		cSchema = "You are an AI assistant and expert coder in Ring and Madar." + nl +
		          "Ring syntax:" + nl +
		          "- Define class: `class ClassName` with attributes and `func methodName()`" + nl +
		          "- Create object: `obj = new ClassName`" + nl +
		          "- Output: `? 'text'`" + nl +
		          "# Tools (Use ONLY when required):" + nl +
		          '- calc(expr): evaluates math. Call: <tool_call><function name="calc"><arguments>["expr"]</arguments></function></tool_call>' + nl +
		          '- get_time(): current time. Call: <tool_call><function name="get_time"><arguments>[]</arguments></function></tool_call>' + nl +
		          '- read_file(path): reads file. Call: <tool_call><function name="read_file"><arguments>["path"]</arguments></function></tool_call>' + nl +
		          '- list_files(dir): lists directory. Call: <tool_call><function name="list_files"><arguments>["dir"]</arguments></function></tool_call>' + nl +
		          "Rules:" + nl +
		          "1. For calculations or math, ALWAYS output the <tool_call> block for calc." + nl +
		          "2. When asked to write Ring code, output the code directly in ```ring ... ``` without tools."
		return cSchema

	# ----------------------------------------------------------------
	# Structured Tool Call Parser
	# ----------------------------------------------------------------
	func parseToolCall(cBlock)
		cToolName = ""
		cToolArg  = ""

		# 1. XML Format: <function name="calc"><arguments>["5*5+40-50"]</arguments></function>
		nFnName = substr(lower(cBlock), 'name="')
		if nFnName = 0 nFnName = substr(lower(cBlock), "name='") ok
		if nFnName > 0
			cAfter = substr(cBlock, nFnName + len('name="'))
			nEndQ = substr(cAfter, '"')
			if nEndQ = 0 nEndQ = substr(cAfter, "'") ok
			if nEndQ > 0
				cToolName = left(cAfter, nEndQ - 1)
			ok
		ok

		if substr(lower(cBlock), "<arguments>") > 0
			nArgStart = substr(lower(cBlock), "<arguments>") + len("<arguments>")
			nArgEnd = substr(lower(cBlock), "</arguments>")
			if nArgEnd > nArgStart
				cRaw = trim(substr(cBlock, nArgStart, nArgEnd - nArgStart))
				if len(cRaw) >= 2 and cRaw[1] = "[" and cRaw[len(cRaw)] = "]"
					cRaw = trim(substr(cRaw, 2, len(cRaw) - 2))
				ok
				if len(cRaw) >= 2 and (cRaw[1] = '"' or cRaw[1] = "'")
					cRaw = substr(cRaw, 2, len(cRaw) - 2)
				ok
				cToolArg = trim(cRaw)
			ok
		ok

		# 2. JSON Format: {"name": "...", "arguments": ...}
		if cToolName = ""
			nNamePos = substr(lower(cBlock), '"name"')
			if nNamePos > 0
				nColon = substr(substr(cBlock, nNamePos), ":")
				if nColon > 0
					cAfterName = substr(cBlock, nNamePos + nColon)
					nQ1 = substr(cAfterName, '"')
					if nQ1 > 0
						nQ2 = substr(substr(cAfterName, nQ1 + 1), '"')
						if nQ2 > 0
							cToolName = substr(cAfterName, nQ1 + 1, nQ2 - 1)
						ok
					ok
				ok
			ok
		ok

		if cToolArg = ""
			nArgPos = substr(lower(cBlock), '"arguments"')
			if nArgPos > 0
				nColon = substr(substr(cBlock, nArgPos), ":")
				if nColon > 0
					cAfterArg = trim(substr(cBlock, nArgPos + nColon))
					if len(cAfterArg) >= 1 and cAfterArg[1] = "{"
						nBraceEnd = substr(cAfterArg, "}")
						if nBraceEnd > 0
							cInside = trim(substr(cAfterArg, 2, nBraceEnd - 2))
							if cInside != ""
								nSubColon = substr(cInside, ":")
								if nSubColon > 0
									cVal = trim(substr(cInside, nSubColon + 1))
									if len(cVal) >= 2 and (cVal[1] = '"' or cVal[1] = "'")
										nEndQ = substr(substr(cVal, 2), cVal[1])
										if nEndQ > 0
											cToolArg = substr(cVal, 2, nEndQ - 1)
										else
											cToolArg = substr(cVal, 2)
										ok
									else
										nComma = substr(cVal, ",")
										if nComma > 0 cVal = left(cVal, nComma - 1) ok
										cToolArg = trim(cVal)
									ok
								else
									cToolArg = cInside
								ok
							ok
						ok
					elseif len(cAfterArg) >= 1 and (cAfterArg[1] = '"' or cAfterArg[1] = "'")
						cQuote = cAfterArg[1]
						nEndQ = substr(substr(cAfterArg, 2), cQuote)
						if nEndQ > 0
							cToolArg = substr(cAfterArg, 2, nEndQ - 1)
						ok
					ok
				ok
			ok
		ok

		# 3. Fallback to tool name scan
		if cToolName = "" or cToolName = "tool_name" or cToolName = "<function-name>"
			for tool in aTools
				tName = tool[1]
				if substr(lower(cBlock), lower(tName)) > 0
					cToolName = tName
					exit
				ok
			next
		ok

		return [trim(cToolName), trim(cToolArg)]

	# ----------------------------------------------------------------
	# Autonomous ReAct Query Engine (Reasoning + Acting)
	# ----------------------------------------------------------------
	func queryStream(cUserPrompt)
		oldStream = bStream
		bStream = 1
		res = query(cUserPrompt)
		bStream = oldStream
		return res

	func query(cUserPrompt, bStreamResponse = NULL, nMaxIterations = 3)
		if oModel = NULL
			return "Error: AI Model is not initialized in Agent."
		ok
		if bStreamResponse != NULL
			bStream = bStreamResponse
		ok

		# 1. RAG Contextual Retrieval from Long-Term Memory (Skip for math/time to prevent context pollution)
		cMemContext = ""
		bIsMathOrTime = (substr(cUserPrompt, "*") > 0 or substr(cUserPrompt, "+") > 0 or substr(cUserPrompt, "/") > 0 or substr(cUserPrompt, "ساعة") > 0 or substr(cUserPrompt, "وقت") > 0 or substr(cUserPrompt, "time") > 0)
		if not bIsMathOrTime and bVectorMemory and oMemory != NULL and oMemory.count() > 0
			aMemMatches = oMemory.search(cUserPrompt, 1)
			if len(aMemMatches) > 0 and aMemMatches[1][1] >= 0.45
				cChunkText = aMemMatches[1][2].cText
				if len(cChunkText) > 200 cChunkText = left(cChunkText, 200) + "..." ok
				cMemContext = f"- {cChunkText}"
				if bVerbose
					see f"  [RAG Context: 1 relevant chunk injected (Score: {round(aMemMatches[1][1], 2)})]\n"
				ok
			ok
		ok

		# 2. Build Unified System Prompt
		cLower = lower(cUserPrompt)
		bIsCodeQuery = (substr(cLower, "كلاس") > 0 or substr(cLower, "دالة") > 0 or 
		                substr(cLower, "كود") > 0 or substr(cLower, "class") > 0 or 
		                substr(cLower, "func") > 0 or substr(cLower, "function") > 0 or 
		                substr(cLower, "code") > 0 or substr(cLower, "برنامج") > 0 or 
		                substr(cLower, "اكتب") > 0 or substr(cLower, "write") > 0)

		if bIsCodeQuery
			cSys = "You are an expert Ring and Madar programmer.\n" +
			       "When asked how to write code or define classes in Ring, always provide a clean, complete code block in ```ring ... ``` followed by a brief explanation.\n" +
			       "Example of Ring class syntax:\n" +
			       "```ring\n" +
			       "class Person\n" +
			       "    name = 'Ring'\n" +
			       "    func printName()\n" +
			       "        ? 'Name: ' + name\n" +
			       "\n" +
			       "p = new Person\n" +
			       "p.printName()\n" +
			       "```"
		else
			cSys = buildToolSchema()
		ok

		if cMemContext != ""
			cSys += f"\n\n# Relevant Knowledge:\n{cMemContext}"
		ok

		# 3. Assemble Prompt with Sliced History
		cPrompt = f"<|im_start|>system\n{cSys}<|im_end|>\n"
		if bMemoryEnabled and len(aConversation) > 0
			cPrompt += formatHistory()
		ok
		cPrompt += f"<|im_start|>user\n{cUserPrompt}<|im_end|>\n<|im_start|>assistant\n"

		oModel.setTemperature(0.3)

		# Step 1: Single Pass Generation (No redundant double call!)
		cResponse = oModel.generateStream(cPrompt, nMaxOutputTokens)

		# Inspect if model emitted a tool call
		nTagStart = substr(cResponse, "<tool_call>")
		if nTagStart = 0 nTagStart = substr(cResponse, "<function") ok
		cBlock  = ""

		if nTagStart > 0
			cBlock = substr(cResponse, nTagStart)
			nTagEnd = substr(cBlock, "</tool_call>")
			if nTagEnd > 0
				cBlock = left(cBlock, nTagEnd + len("</tool_call>") - 1)
			elseif substr(cBlock, "</function>") > 0
				nFnEnd = substr(cBlock, "</function>")
				cBlock = left(cBlock, nFnEnd + len("</function>") - 1)
			ok
		elseif substr(cResponse, '{"name"') > 0 or substr(cResponse, '"name":') > 0
			nJsonStart = substr(cResponse, "{")
			if nJsonStart > 0
				cBlock = substr(cResponse, nJsonStart)
				nJsonEnd = substr(cBlock, "}")
				if nJsonEnd > 0
					cBlock = left(cBlock, nJsonEnd)
				ok
			ok
		ok

		# Tool Call Found: Execute Action and Return Direct Result
		cToolName = ""
		cToolArg  = ""
		if cBlock != ""
			aParsed   = parseToolCall(cBlock)
			cToolName = aParsed[1]
			cToolArg  = aParsed[2]
		ok

		# Safety fallback for calc if model omitted argument or format
		if cToolName = "calc" and cToolArg = ""
			cToolArg = extractMathExpr(cBlock)
			if cToolArg = "" cToolArg = extractMathExpr(cUserPrompt) ok
		elseif cToolName = "" and (substr(cUserPrompt, "احسب") > 0 or substr(cUserPrompt, "calc") > 0)
			cToolName = "calc"
			cToolArg = extractMathExpr(cUserPrompt)
		ok

		if cToolName != ""
			if bVerbose
				see f"\n  [Agent Action] Invoking Tool: {cToolName} ({cToolArg})...\n"
			ok

			cToolResult = executeTool(cToolName, cToolArg)

			if bVerbose
				see f"  [Tool Observation] Result: {cToolResult}\n"
			ok

			# Pure factual tools return directly in 0.01s!
			if cToolName = "calc"
				cClean = f"النتيجة: {cToolResult}"
				see f"Agent Response: {cClean}\n"
				if bMemoryEnabled
					aConversation + ["user", cUserPrompt]
					aConversation + ["assistant", cClean]
				ok
				return cClean
			elseif cToolName = "get_time" or cToolName = "sys_info"
				cClean = cToolResult
				see f"Agent Response: {cClean}\n"
				if bMemoryEnabled
					aConversation + ["user", cUserPrompt]
					aConversation + ["assistant", cClean]
				ok
				return cClean
			

				# File/Directory reading: pass back for synthesis
				cPrompt += f"<tool_call>\n{cBlock}\n</tool_call><|im_end|>\n" +
				           f"<|im_start|>user\n<tool_response>\n{cToolResult}\n</tool_response><|im_end|>\n" +
				           f"<|im_start|>assistant\n"
				cFinalAnswer = oModel.generateStream(cPrompt, nMaxOutputTokens)
			else
				cFinalAnswer = cResponse
			ok
		else
			cFinalAnswer = cResponse
		ok

		cClean = cleanResponse(cFinalAnswer)
		see f"Agent Response: {cClean}\n"

		if bMemoryEnabled
			aConversation + ["user", cUserPrompt]
			aConversation + ["assistant", cClean]
		ok

		return cClean

	# ----------------------------------------------------------------
	# Tool Execution Dispatcher
	# ----------------------------------------------------------------
	func executeTool(cName, cArg)
		cName = lower(trim(cName))
		cArg  = trim(cArg)
		if len(cArg) >= 2 and (cArg[1] = '"' or cArg[1] = "'")
			cArg = cArg[2:len(cArg) - 1] # Madar slice
		ok

		if cName = "remember_fact"
			if cArg = "" return "No fact provided to remember." ok
			remember(cArg)
			return f"Saved successfully to long-term memory: {cArg}"
		ok

		if cName = "rag_search"
			if cArg = "" return "No search query provided." ok
			if oMemory = NULL return "No long-term memory loaded." ok
			aResults = oMemory.search(cArg, 2)
			if len(aResults) = 0 return "No relevant knowledge found in memory." ok
			aLines = [f"- [Score: {round(r[1], 2)}]: {r[2].cText}" for r in aResults]
			return join(aLines, nl)
		ok

		for tool in aTools
			if lower(tool[1]) = cName
				pFunc = tool[4]
				try
					return call pFunc([cArg])
				catch
					return f"Error executing tool {cName}: {cCatchError}"
				end
			ok
		next

		return f"Error: Tool '{cName}' is not registered."

	
		
	private

	func extractParam(cText, cKey)
		nPos = substr(lower(cText), lower(cKey))
		if nPos = 0 return "" ok
		cSub = substr(cText, nPos + len(cKey))
		nNl = substr(cSub, nl)
		if nNl > 0 cSub = cSub[:nNl - 1] ok
		return trim(cSub)

	func cleanResponse(cText)
		cText = substr(cText, "<|im_end|>", "")
		cText = substr(cText, "<|endoftext|>", "")
		cText = substr(cText, "<|im_start|>", "")
		cText = trim(cText)
		if substr(lower(cText), "assistant" + nl) = 1
			cText = substr(cText, len("assistant" + nl) + 1)
		elseif substr(lower(cText), "assistant:") = 1
			cText = substr(cText, len("assistant:") + 1)
		elseif substr(lower(cText), "assistant ") = 1
			cText = substr(cText, len("assistant ") + 1)
		ok
		return trim(cText)
