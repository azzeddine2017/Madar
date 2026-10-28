# ====================================================================
#   MadarAgent - Production-Grade Autonomous AI Agent Application
#   تطبيق الوكيل الذكي المتكامل: هيكلية شيئية نقية (OOP Architecture)
#   توجيه دلالي هجين (Semantic Routing) + استجابات Zero-LLM فورية
# ====================================================================

load "stdlibcore.ring"
load "ringregex.ring"
load "madar_ai.ring"
load "rag.ring"
load "config.ring"
load "tools/base_tool.ring"
load "tools/system_tools.ring"
load "tools/dev_tools.ring"
load "skills/base_skill.ring"
load "core/memory_tier.ring"
load "core/tool_caller.ring"
load "core/command_router.ring"
load "core/intent_registry.ring"
load "core/semantic_router.ring"
load "core/entity_extractor.ring"
load "ui_style.ring"

class AgentApp
	oConfig          = NULL
	oModel           = NULL
	oEmbeddingModel  = NULL
	oMemory          = NULL
	oRegistry        = NULL
	oSkillManager    = NULL
	oToolCaller      = NULL
	oRouter          = NULL
	oIntentRegistry  = NULL
	oSemanticRouter  = NULL
	oEntityExtractor = NULL

	aHistory         = []
	bGPU             = true
	bDebug           = true
	nRagTopK         = 1
	nRagMaxChars     = 800
	bUseSlidingWindow = true
	nHistoryWindow    = 2
	nTemperature     = 0.30
	nMaxContext      = 8192
	nMaxGenTokens    = 1500
	bRunning         = true

	func init(aArgs = [])
		uiBanner("MadarAgent - Autonomous Multi-Modal AI Agent", "High-Precision Ring 1.27 Cognitive Architecture")

		# 1. Configuration & Discovery
		oConfig = new AgentConfig(aArgs)
		bGPU = oConfig.bGPU
		bDebug = oConfig.bDebug
		nRagTopK = oConfig.nRagTopK
		nRagMaxChars = oConfig.nRagMaxChars
		bUseSlidingWindow = oConfig.bUseSlidingWindow
		nHistoryWindow = oConfig.nHistoryWindow
		nTemperature = oConfig.nTemperature
		nMaxContext = oConfig.nMaxContext
		nMaxGenTokens = oConfig.nMaxGenTokens

		if oConfig.cModelPath = ""
			? uiError("  [Error] No suitable LLM model (.gguf) found. Please place a model in models/ folder.")
			bRunning = false
			return self
		ok

		? uiInfo(f"  [LLM Model]       {oConfig.cModelPath}")
		if oConfig.cEmbeddingPath != ""
			? uiInfo(f"  [Embedding Model] {oConfig.cEmbeddingPath}")
		ok

		# 2. Setup Cognitive Skill Manager
		setupSkills()

		# 3. Initialize Models
		initModels()

		# 4. Initialize Two-Tier Memory
		setupMemory()

		# 5. Setup Tool Registry
		setupTools()

		# 6. Initialize Tool Caller & Command Router
		oToolCaller = new ToolCallingEngine(oRegistry)
		oRouter = new CommandRouter(self)

		# 7. Initialize Semantic Router & Entity Extractor (Rasa / PCRE2 Pattern)
		setupIntents()

		? uiSuccess("  [Agent State]     Ready for interaction.")
		uiDivider()
		return self

	func setupTools()
		oRegistry = new ToolRegistry
		oRegistry.register(new TimeTool())
		oRegistry.register(new ListFilesTool())
		oRegistry.register(new ReadFileTool())
		oRegistry.register(new WriteFileTool())
		oRegistry.register(new CalcTool())
		oRegistry.register(new RingRunTool())
		oRegistry.register(new RememberTool(oMemory))
		oRegistry.register(new CreateSkillTool(oSkillManager))
		? uiInfo(f"  [Tools]           Loaded {oRegistry.count()} active tools.")

	func setupSkills()
		oSkillManager = new SkillManager(oConfig.cSkillsDir)
		nCount = oSkillManager.loadSkillsFromFolder()
		? uiInfo(f"  [Skills]          Loaded {nCount} specialized cognitive skills from '{oConfig.cSkillsDir}'.")

	func initModels()
		? uiInfo("  [Loading Models]...")
		# Load Primary LLM using library factory
		oModel = model_open(oConfig.cModelPath)
		oModel.setTemperature(nTemperature)
		if bGPU
			oModel.setGPU(1)
		ok

		# Load Dedicated Embedding Model if available
		if oConfig.cEmbeddingPath != ""
			try
				oEmbeddingModel = new BgeModel(oConfig.cEmbeddingPath)
				if bGPU
					oEmbeddingModel.setGPU(1)
				ok
			catch
				? uiWarn("  [Embedding Warning] Could not load BGE-M3, falling back to LLM hidden states.")
				oEmbeddingModel = oModel
			done
		else
			oEmbeddingModel = oModel
		ok

	func setupMemory()
		oMemory = new TwoTierMemory(oEmbeddingModel, oConfig.cBaseKbPath, oConfig.cWorkingKbPath)

	func setupIntents()
		oIntentRegistry = new IntentRegistry()
		oEntityExtractor = new EntityExtractor
		oSemanticRouter = new SemanticRouter(oEmbeddingModel, oIntentRegistry, oConfig.cIntentCachePath, oConfig.nIntentThreshold)
		? uiInfo(f"  [Intents Router]  Active with {len(oIntentRegistry.aIntents)} intent archetypes (BGE-M3 + PCRE2).")

	func estimateTokenCount()
		nChars = 0
		for m in aHistory
			nChars += len(m["content"])
		next
		return ceil(nChars / 3.5)

	# Build Scoped & Ephemeral Prompt based on Detected Intent
	func buildScopedPrompt(cUserInput, oIntent = NULL)
		# 1. Compact Base System Persona
		cSystemPrompt = "You are MadarAgent, a precise, intelligent, and autonomous AI assistant." + nl +
			"Always be helpful, concise, technically rigorous, and speak fluent Arabic and English as requested." + nl

		# 2. Target Specific Skill if intent activates one
		cTargetSkill = ""
		aAllowedTools = []
		bNeedsRag = false

		if oIntent != NULL
			cTargetSkill = oIntent.cSkillName
			aAllowedTools = oIntent.aScopedTools
			bNeedsRag = oIntent.bNeedsRag
		ok

		# Apply skill instructions
		if cTargetSkill != ""
			oSkill = oSkillManager.getSkill(cTargetSkill)
			if oSkill != NULL
				? uiSkillBadge(oSkill.cName)
				cSystemPrompt += nl + "# Active Skill: " + oSkill.cName + nl + oSkill.getPromptOverlay() + nl
				# If intent did not specify tools, inherit from skill
				if len(aAllowedTools) = 0 and len(oSkill.getTools()) > 0
					aAllowedTools = oSkill.getTools()
				ok
			ok
		ok

		# 3. Inject only the scoped tools for this intent
		if len(aAllowedTools) > 0
			cToolSchema = oRegistry.buildSchemaPrompt("xml", aAllowedTools)
			if cToolSchema != ""
				cSystemPrompt += nl + cToolSchema + nl
			ok
		ok

		# 4. Ephemeral RAG Retrieval (Targeted knowledge chunk)
		cRagContext = ""
		if bNeedsRag and nRagTopK > 0
			t_rag0 = clock()
			aRetrieved = oMemory.search(cUserInput, nRagTopK)
			nRagDuration = (clock() - t_rag0) / clockspersecond()
			if len(aRetrieved) > 0
				? uiRagBadge(len(aRetrieved))
				if bDebug
					? uiMuted(f"    (RAG Search took {round(nRagDuration, 3)}s)")
				ok
				for item in aRetrieved
					cChunkData = item[2]
					if len(cChunkData) > nRagMaxChars
						cChunkData = left(cChunkData, nRagMaxChars) + nl + "... [Truncated for brevity]"
					ok
					cRagContext += "--- [Knowledge Chunk] ---" + nl + cChunkData + nl
				next
			ok
		ok

		# 5. Build ChatML formatted prompt
		cPrompt = "<|im_start|>system" + nl + cSystemPrompt + "<|im_end|>" + nl

		# Sliding Window Conversation History
		nStartHist = 1
		if bUseSlidingWindow and len(aHistory) > (nHistoryWindow * 2)
			nStartHist = len(aHistory) - (nHistoryWindow * 2) + 1
		ok
		for i = nStartHist to len(aHistory)
			m = aHistory[i]
			cPrompt += f"<|im_start|>{m['role']}" + nl + m["content"] + "<|im_end|>" + nl
		next

		# Append Ephemeral RAG strictly into Current User Turn (Never saved in history)
		cUserContent = cUserInput
		if cRagContext != ""
			cUserContent = "# Reference Guidance (Ground Truth):" + nl + cRagContext + nl +
				"User Question: " + cUserInput
		ok

		cPrompt += "<|im_start|>user" + nl + cUserContent + "<|im_end|>" + nl
		cPrompt += "<|im_start|>assistant" + nl

		return cPrompt

	func processTurn(cUserInput)
		cUserInput = trim(cUserInput)
		if cUserInput = "" return ok

		# 1. Fast Slash Commands
		if oRouter.isCommand(cUserInput)
			oRouter.route(cUserInput)
			return
		ok

		# 2. Semantic Intent Classification via BGE-M3 (< 40ms)
		t_intent0 = clock()
		aRoute = oSemanticRouter.route(cUserInput)
		nIntentSec = (clock() - t_intent0) / clockspersecond()

		oIntent = NULL
		if aRoute != NULL
			oIntent = aRoute[1]
			fScore  = aRoute[2]
			cTrig   = aRoute[3]
			if bDebug
				? uiInfo(f"  🎯 [Intent: {oIntent.cName} ({oIntent.cType}) | Match: '{cTrig}' | Score: {round(fScore, 2)} | {round(nIntentSec * 1000, 1)}ms]")
			ok

			# -------------------------------------------------------------
			# Path 1: Instant Zero-LLM Direct Response
			# -------------------------------------------------------------
			if oIntent.cType = "direct_response"
				see uiAgentPrompt("MadarAgent")
				? oIntent.cResponse
				aHistory + ["role" = "user", "content" = cUserInput]
				aHistory + ["role" = "assistant", "content" = oIntent.cResponse]
				return
			ok

			# -------------------------------------------------------------
			# Path 2: Instant Zero-LLM Direct Tool Execution
			# -------------------------------------------------------------
			if oIntent.cType = "direct_tool"
				if oIntent.cToolName = "calc"
					cExpr = oEntityExtractor.extractMathExpression(cUserInput)
					if cExpr != ""
						? uiToolCallBadge("calc", cExpr)
						cRes = oRegistry.execute("calc", [cExpr])
						? uiToolResultBlock("calc", cRes)
						cDirectResp = f"الناتج الحسابي لـ ({cExpr}) هو: {cRes}"
						see uiAgentPrompt("MadarAgent")
						? cDirectResp
						aHistory + ["role" = "user", "content" = cUserInput]
						aHistory + ["role" = "assistant", "content" = cDirectResp]
						return
					ok
				ok
			ok
		ok

		# -----------------------------------------------------------------
		# Path 3: Scoped LLM Execution (Lightweight Focused Prompt)
		# -----------------------------------------------------------------
		cPrompt = buildScopedPrompt(cUserInput, oIntent)
		nPromptChars = len(cPrompt)
		nEstPromptTokens = ceil(nPromptChars / 3.5)

		if bDebug
			? uiMuted(f"  [Evaluating Scoped Prompt: ~{nEstPromptTokens} tokens ({nPromptChars} chars)...]")
		ok

		t_prefill0 = clock()
		nPromptTokens = oModel.prefill(cPrompt, nMaxGenTokens)
		nPrefillSec = (clock() - t_prefill0) / clockspersecond()

		if bDebug
			? uiMuted(f"  [Prefill Finished in {round(nPrefillSec, 2)}s ({nPromptTokens} tokens | {round(nPromptTokens / (nPrefillSec + 0.001), 1)} tok/s)]")
		ok

		see uiAgentPrompt("MadarAgent")
		t_gen0 = clock()
		cResponse = ""
		nGenTokens = 0
		while oModel.hasMore()
			cChunk = oModel.step()
			if cChunk != ""
				see cChunk
				cResponse += cChunk
				nGenTokens++
			ok
		end
		see nl
		nGenSec = (clock() - t_gen0) / clockspersecond()
		fTokPerSec = 0.0
		if nGenSec > 0 fTokPerSec = nGenTokens / nGenSec ok

		if bDebug
			uiDivider()
			? uiInfo("  ⏱ [Performance Profiler]")
			? "    ├─ " + uiMuted("Prompt Processing (Prefill): ") + f"{round(nPrefillSec, 2)}s ({nPromptTokens} tokens, {round(nPromptTokens / (nPrefillSec + 0.001), 1)} tok/s)"
			? "    └─ " + uiMuted("Generation Stream:           ") + f"{round(nGenSec, 2)}s ({nGenTokens} tokens, {round(fTokPerSec, 1)} tok/s)"
			uiDivider()
		ok

		# Check for Tool Calls
		if oToolCaller.hasToolCall(cResponse)
			aCalls = oToolCaller.extractToolCalls(cResponse)
			if len(aCalls) > 0
				? ""
				cToolOutput = ""
				for callItem in aCalls
					cToolName = callItem[1]
					aArgs     = callItem[2]
					cArgsStr  = ""
					for a in aArgs cArgsStr += "" + a + ", " next
					if len(cArgsStr) > 2 cArgsStr = left(cArgsStr, len(cArgsStr) - 2) ok

					? uiToolCallBadge(cToolName, cArgsStr)
					cRes = oRegistry.execute(cToolName, aArgs)
					? uiToolResultBlock(cToolName, cRes)
					cToolOutput += f"<tool_response name='{cToolName}'>" + nl + cRes + nl + "</tool_response>" + nl
				next

				# Feed tool results back into model for final synthesis
				cSynthesisPrompt = cPrompt + cResponse + "<|im_end|>" + nl +
					"<|im_start|>user" + nl +
					"Tool Results:" + nl + cToolOutput + nl +
					"Please provide the final synthesized response based on the tool results." +
					"<|im_end|>" + nl +
					"<|im_start|>assistant" + nl

				see uiAgentPrompt("MadarAgent (Synthesized)")
				cFinal = oModel.generateStream(cSynthesisPrompt, nMaxGenTokens)
				see nl
				cResponse = cResponse + nl + cToolOutput + nl + cFinal
			ok
		ok

		# Update Clean Conversation History (Without ephemeral RAG bloat)
		aHistory + ["role" = "user", "content" = cUserInput]
		aHistory + ["role" = "assistant", "content" = cResponse]

	func run()
		if !bRunning return ok

		? uiHighlight("MadarAgent Terminal Interface. Type your prompt, or /help for commands, 'exit' to quit.") + nl

		while bRunning
			see uiUserPrompt()
			give cInput
			cInput = trim(cInput)

			if cInput = "" loop ok

			cLower = lower(cInput)
			if cLower = "exit" or cLower = "quit" or cLower = "bye" or cLower = "وداعا" or cLower = "خروج"
				? nl + uiSuccess("Farewell from MadarAgent! Goodbye.")
				bRunning = false
				exit
			ok

			processTurn(cInput)
		end
