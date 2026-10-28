# ====================================================================
#   MadarAgent - Production-Grade Autonomous AI Agent Application
#   تطبيق الوكيل الذكي المتكامل: هيكلية شيئية نقية (OOP Architecture)
# ====================================================================

load "stdlibcore.ring"
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

	aHistory         = []
	bGPU             = true
	nTemperature     = 0.30
	nMaxContext      = 8192
	nMaxGenTokens    = 1500
	bRunning         = true

	func init(aArgs = [])
		uiBanner("MadarAgent - Autonomous Multi-Modal AI Agent", "High-Precision Ring 1.27 Cognitive Architecture")

		# 1. Configuration & Discovery
		oConfig = new AgentConfig(aArgs)
		bGPU = oConfig.bGPU
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

		# 5. Setup Tool Registry (with Memory & SkillManager wired in)
		setupTools()

		# 6. Initialize Tool Caller & Router
		oToolCaller = new ToolCallingEngine(oRegistry)
		oRouter = new CommandRouter(self)

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

	func estimateTokenCount()
		# Approximate token counting (1 token ~= 3.5 chars)
		nChars = 0
		for m in aHistory
			nChars += len(m["content"])
		next
		return ceil(nChars / 3.5)

	func buildPrompt(cUserInput)
		# 1. Base System Persona
		cSystemPrompt = "You are MadarAgent, a precise, intelligent, and autonomous AI assistant." + nl +
			"You are an expert software engineer and specialist in the Ring programming language." + nl +
			"Always be helpful, concise, technically rigorous, and speak fluent Arabic and English as requested." + nl +
			"When you need to execute code, inspect files, remember facts, or create skills, use the available tools." + nl +
			"- Autonomous Memory: When the user shares personal preferences, project conventions, or asks you to remember something, call 'remember_fact'." + nl +
			"- Autonomous Skills: When you formulate a reusable procedure, or when the user teaches you a new pattern and asks to save it as a skill, call 'create_skill'." + nl

		# 2. Append Tool Schemas
		cSystemPrompt += nl + oRegistry.buildSchemaPrompt("xml") + nl

		# 3. Dynamic Skill Overlay
		aActiveSkills = oSkillManager.detectActiveSkills(cUserInput)
		for s in aActiveSkills
			? uiSkillBadge(s.cName)
		next
		cSkillOverlay = oSkillManager.buildCombinedOverlay(cUserInput)
		if cSkillOverlay != ""
			cSystemPrompt += nl + cSkillOverlay + nl
		ok

		# 4. RAG Retrieval from Two-Tier Memory
		aRetrieved = oMemory.search(cUserInput, 2)
		if len(aRetrieved) > 0
			? uiRagBadge(len(aRetrieved))
			cSystemPrompt += nl + "# Ground Truth Knowledge & Retrieved Context:" + nl
			for item in aRetrieved
				# item format: [fScore, cText, chunk]
				cSystemPrompt += "--- [Knowledge Chunk] ---" + nl
				cSystemPrompt += item[2] + nl
			next
			cSystemPrompt += "--- [End of Context] ---" + nl
		ok

		# 5. Build ChatML formatted prompt
		cPrompt = "<|im_start|>system" + nl + cSystemPrompt + "<|im_end|>" + nl

		# Append conversation history (limited to last 6 turns to conserve context)
		nStartHist = 1
		if len(aHistory) > 6
			nStartHist = len(aHistory) - 5
		ok
		for i = nStartHist to len(aHistory)
			m = aHistory[i]
			cPrompt += f"<|im_start|>{m['role']}" + nl + m["content"] + "<|im_end|>" + nl
		next

		# Append current user message
		cPrompt += "<|im_start|>user" + nl + cUserInput + "<|im_end|>" + nl
		cPrompt += "<|im_start|>assistant" + nl

		return cPrompt

	func processTurn(cUserInput)
		cUserInput = trim(cUserInput)
		if cUserInput = "" return ok

		# Check for Slash Commands
		if oRouter.isCommand(cUserInput)
			oRouter.route(cUserInput)
			return
		ok

		# Build Prompt with Skills + Tools + RAG
		cPrompt = buildPrompt(cUserInput)

		see uiAgentPrompt("MadarAgent")
		cResponse = oModel.generateStream(cPrompt, nMaxGenTokens)
		see nl

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

		# Update Conversation History
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
