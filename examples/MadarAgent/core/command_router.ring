# ====================================================================
#   MadarAgent - Slash Command Router
#   موجه أوامر التحكم المباشرة بالوكيل (الأدوات، المهارات، الذاكرة، الإعدادات)
# ====================================================================

class CommandRouter
	oApp

	func init(oAgentApp)
		oApp = ref(oAgentApp)
		return self

	func isCommand(cInput)
		cInput = trim(cInput)
		return (left(cInput, 1) = "/")

	func route(cInput)
		cInput = trim(cInput)
		aParts = split(cInput, " ")
		cCmd = lower(aParts[1])
		cArgs = ""
		if len(aParts) > 1
			cArgs = trim(substr(cInput, len(cCmd) + 1))
		ok

		switch cCmd
			case "/help"
				showHelp()
			case "/tools"
				showTools()
			case "/skills"
				showSkills()
			case "/reload_skills"
				handleReloadSkills()
			case "/memory"
				showMemory()
			case "/stats"
				showMemory()
			case "/remember"
				handleRemember(cArgs)
			case "/recall"
				handleRecall(cArgs)
			case "/learn"
				handleLearn(cArgs)
			case "/clear_memory"
				handleClearMemory()
			case "/commit_memory"
				handleCommitMemory()
			case "/gpu"
				handleGpu(cArgs)
			case "/temp"
				handleTemp(cArgs)
			case "/tokens"
				handleTokens()
			case "/history"
				handleHistory()
			case "/debug"
				handleDebug(cArgs)
			case "/rag_topk"
				handleRagTopK(cArgs)
			case "/intents"
				handleIntents()
			case "/reindex_intents"
				handleReindexIntents()
			case "/history_window"
				handleHistoryWindow(cArgs)
			case "/reset"
				handleReset()
			case "/clear"
				handleReset()
			else
				see f"  [Unknown Command] '{cCmd}'. Type /help for available commands." + nl
		end

	func showHelp()
		uiBanner("MadarAgent Interactive Commands", "Real-time Controls & Slash Directives")
		? "  " + uiInfo("/tools") + "             - List all registered system, dev & autonomous tools"
		? "  " + uiInfo("/skills") + "            - List registered cognitive skills"
		? "  " + uiInfo("/reload_skills") + "     - Reload all skills from agentSkills/ markdown files"
		? "  " + uiInfo("/memory, /stats") + "    - Show Base KB & Working Memory status"
		? "  " + uiInfo("/remember <fact>") + "   - Add fact/note to persistent Working Memory"
		? "  " + uiInfo("/recall <query>") + "    - Test search across Two-Tier Memory"
		? "  " + uiInfo("/learn <file>") + "      - Ingest & embed a document into Working Memory"
		? "  " + uiInfo("/clear_memory") + "      - Clear session Working Memory (Base KB safe)"
		? "  " + uiInfo("/commit_memory") + "     - Permanently merge Working Memory into Base KB"
		? "  " + uiInfo("/gpu [on|off]") + "      - Check or toggle GPU OpenCL acceleration"
		? "  " + uiInfo("/temp <float>") + "      - Set sampling temperature (e.g. /temp 0.2)"
		? "  " + uiInfo("/debug [on|off]")  + "    - Toggle real-time millisecond latency profiler"
		? "  " + uiInfo("/rag_topk <num>")  + "    - Set number of RAG chunks to retrieve (e.g. 1 or 2)"
		? "  " + uiInfo("/history") + "           - Show summary of current conversation turns"
		? "  " + uiInfo("/reset, /clear") + "     - Reset conversation history (Base KB preserved)"
		? "  " + uiWarn("exit, quit, bye") + "    - Terminate agent session"
		uiDivider()

	func showTools()
		uiSectionHeader("Registered Tools (" + oApp.oRegistry.count() + ")")
		for t in oApp.oRegistry.list()
			? "  " + uiSuccess("⚙ " + t.cName) + C_BBLACK + " - " + C_RESET + t.cDescription
		next
		uiDivider()

	func showSkills()
		uiSectionHeader("Registered Cognitive Skills (" + oApp.oSkillManager.count() + ") [Folder: " + oApp.oConfig.cSkillsDir + "]")
		for s in oApp.oSkillManager.list()
			? "  " + uiAccent("⚡ " + s.cName) + C_BBLACK + " - " + C_RESET + s.cDescription
			if len(s.aTriggerKeywords) > 0
				cTrigs = ""
				for i = 1 to len(s.aTriggerKeywords)
					cTrigs += s.aTriggerKeywords[i]
					if i < len(s.aTriggerKeywords) cTrigs += ", " ok
				next
				? "      " + uiMuted("Triggers: ") + C_BCYAN + cTrigs + C_RESET
			ok
			if len(s.aSkillToolNames) > 0
				cTools = ""
				for i = 1 to len(s.aSkillToolNames)
					cTools += s.aSkillToolNames[i]
					if i < len(s.aSkillToolNames) cTools += ", " ok
				next
				? "      " + uiMuted("Bound Tools: ") + C_BYELLOW + cTools + C_RESET
			ok
		next
		uiDivider()

	func handleReloadSkills()
		oApp.oSkillManager.aSkills = []
		nCount = oApp.oSkillManager.loadSkillsFromFolder()
		? uiSuccess(f"  [Skills] Reloaded {nCount} cognitive skills from '{oApp.oConfig.cSkillsDir}'.")

	func showMemory()
		aStats = oApp.oMemory.getStats()
		uiSectionHeader("Two-Tier Memory Architecture Status")
		? "  " + uiInfo("● Tier 1 (Base KB):") + f"    {aStats['base_chunks']} chunks " + uiMuted("[" + aStats['base_path'] + "]")
		? "  " + uiInfo("● Tier 2 (Working KB):") + f" {aStats['working_chunks']} chunks " + uiMuted("[" + aStats['working_path'] + "]")
		uiDivider()

	func handleRemember(cFact)
		if cFact = ""
			see "  Usage: /remember <fact or rule to store in memory>" + nl
			return
		ok
		if oApp.oMemory.rememberFact(cFact)
			see "  [Memory] Fact stored successfully in Working Memory." + nl
		else
			see "  [Memory Error] Failed to store fact." + nl
		ok

	func handleRecall(cQuery)
		if cQuery = ""
			see "  Usage: /recall <search query>" + nl
			return
		ok
		aRes = oApp.oMemory.search(cQuery, 3)
		see nl + f"Search Results for '{cQuery}' ({len(aRes)} matches):" + nl
		if len(aRes) = 0
			see "  No matching chunks found." + nl
		else
			for i = 1 to len(aRes)
				fScore = aRes[i][1]
				cTxt = aRes[i][2]
				see f"  [{i}] (Score: {fScore}):" + nl
				see "      " + substr(cTxt, nl, nl + "      ") + nl
			next
		ok
		see nl

	func handleLearn(cFilePath)
		if cFilePath = "" or not fexists(cFilePath)
			see f"  [Learn Error] File not found: '{cFilePath}'" + nl
			return
		ok
		see f"  [Learning] Ingesting and embedding '{cFilePath}'..." + nl
		nAdded = oApp.oMemory.learnFile(cFilePath)
		see f"  [Learned] Added {nAdded} chunks to Working Memory." + nl

	func handleClearMemory()
		oApp.oMemory.clearWorking()
		see "  [Memory] Working Memory cleared. (Base KB remains untouched)." + nl

	func handleCommitMemory()
		nMoved = oApp.oMemory.commitWorkingToBase()
		see f"  [Memory] Committed {nMoved} working chunks to Base KB." + nl

	func handleGpu(cArg)
		cArg = lower(trim(cArg))
		if cArg = "on" or cArg = "1"
			oApp.bGPU = true
			if oApp.oModel != NULL oApp.oModel.setGPU(1) ok
			see "  [GPU] OpenCL Acceleration Enabled." + nl
		elseif cArg = "off" or cArg = "0"
			oApp.bGPU = false
			if oApp.oModel != NULL oApp.oModel.setGPU(0) ok
			see "  [GPU] GPU Acceleration Disabled (Running on CPU)." + nl
		else
			see f"  [GPU Status] Enabled: {oApp.bGPU}" + nl
		ok

	func handleTemp(cArg)
		nVal = 0.0 + cArg
		if nVal > 0.0 and nVal <= 2.0
			oApp.nTemperature = nVal
			see f"  [Config] Temperature set to: {oApp.nTemperature}" + nl
		else
			see f"  [Config] Current Temperature: {oApp.nTemperature} (Valid: 0.1 - 2.0)" + nl
		ok

	func handleTokens()
		nTokens = oApp.estimateTokenCount()
		see f"  [Context Budget] Estimated prompt tokens: {nTokens} / {oApp.nMaxContext}" + nl

	func handleHistory()
		see nl + f"Conversation History ({len(oApp.aHistory)} messages):" + nl
		for i = 1 to len(oApp.aHistory)
			m = oApp.aHistory[i]
			see f"  [{m['role']}]: {left(m['content'], 80)}..." + nl
		next
		see nl

	func handleReset()
		oApp.aHistory = []
		see "  [Reset] Conversation history cleared. Ready for a new topic." + nl

	func handleDebug(cArg)
		cArg = lower(trim(cArg))
		if cArg = "on" or cArg = "1"
			oApp.bDebug = true
			? uiSuccess("  [Profiler] Debug Latency Profiler Enabled.")
		elseif cArg = "off" or cArg = "0"
			oApp.bDebug = false
			? uiWarn("  [Profiler] Debug Latency Profiler Disabled.")
		else
			oApp.bDebug = !oApp.bDebug
			if oApp.bDebug
				? uiSuccess("  [Profiler] Debug Latency Profiler Toggled ON.")
			else
				? uiWarn("  [Profiler] Debug Latency Profiler Toggled OFF.")
			ok
		ok

	func handleRagTopK(cArg)
		nVal = 0 + cArg
		if nVal >= 0 and nVal <= 5
			oApp.nRagTopK = nVal
			? uiSuccess(f"  [Config] RAG Top-K set to: {oApp.nRagTopK} chunks.")
		else
			? uiInfo(f"  [Config] Current RAG Top-K: {oApp.nRagTopK} (Usage: /rag_topk 1)")
		ok

	func handleIntents()
		if oApp.oIntentRegistry = NULL
			? uiWarn("  [Intents] Intent Registry is not initialized.")
			return
		ok
		uiBanner("Registered Intent Matrix (Rasa/Semantic Router)", "Hybrid Zero-LLM & Scoped Execution")
		for item in oApp.oIntentRegistry.aIntents
			? "  " + uiHighlight(f"[{item.cName}]") + " (" + uiInfo(item.cType) + ")"
			? "    ├─ Triggers: " + uiMuted("" + len(item.aTriggers) + " examples")
			if item.cType = "direct_response"
				? "    └─ Action:   " + uiSuccess("Direct Instant Answer (Zero-LLM)")
			elseif item.cType = "direct_tool"
				? "    └─ Action:   " + uiSuccess(f"Direct Tool Execution: {item.cToolName} (Zero-LLM)")
			else
				cToolsStr = ""
				for t in item.aScopedTools cToolsStr += t + " " next
				? "    └─ Action:   " + uiInfo(f"Scoped LLM | Skill: '{item.cSkillName}' | Tools: [{trim(cToolsStr)}] | RAG: {item.bNeedsRag}")
			ok
		next
		uiDivider()

	func handleReindexIntents()
		if oApp.oSemanticRouter = NULL
			? uiWarn("  [Intents] Semantic Router is not active.")
			return
		ok
		? uiInfo("  [Re-indexing] Computing trigger embeddings with BGE-M3 and updating cache...")
		t0 = clock()
		nCount = oApp.oSemanticRouter.reindex()
		nSec = round((clock() - t0) / clockspersecond(), 2)
		? uiSuccess(f"  [Intents Cached] Successfully indexed {nCount} triggers into '{oApp.oSemanticRouter.cCachePath}' in {nSec}s.")

	func handleHistoryWindow(cArg)
		nVal = 0 + cArg
		if nVal >= 1 and nVal <= 10
			oApp.nHistoryWindow = nVal
			oApp.bUseSlidingWindow = true
			? uiSuccess(f"  [History Window] Sliding window set to last {oApp.nHistoryWindow} conversational turns.")
		else
			? uiInfo(f"  [History Window] Current window: {oApp.nHistoryWindow} turns (Active: {oApp.bUseSlidingWindow}). Usage: /history_window 2")
		ok

