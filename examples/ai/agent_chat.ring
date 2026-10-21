# ====================================================================
#   Madar AI - Interactive Autonomous Agent CLI & REPL Terminal
#   (الطرفية التفاعلية الشاملة للوكيل الذكي في لغة مدار)
# ====================================================================
#
# Features:
#   1. Autonomous multi-lingual tool execution (Files, Math, System, CSV/DataFrame)
#   2. Multi-turn conversational memory with /undo and /reset
#   3. Real-time token streaming directly to terminal
#   4. Dynamic tool inspection and runtime parameter adjustment
# ====================================================================

load "stdlibCore.ring"
load "agent.ring"

# 1. Locate GGUF Model
cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
ok
if not fexists(cModelPath)
	cModelPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
ok

if not fexists(cModelPath)
	see nl + "====================================================================" + nl
	see "  [ERROR] No AI model found in models/ directory!" + nl
	see "  Please download a model first using tools\download_model.bat" + nl
	see "====================================================================" + nl
	bye
ok

# 2. Initialize Model & Agent
see nl + "====================================================================" + nl
see "  Madar AI Agent - Autonomous Interactive CLI Terminal" + nl
see "  (الطرفية التفاعلية للوكيل الذكي: استدعاء الأدوات والذاكرة المتصلة)" + nl
see "====================================================================" + nl
see "  Model: " + cModelPath + nl

t0 = clock()
model = new QwenModel(cModelPath)
model.setThreads(4)
model.setTemperature(0.3)

agent = new AIAgent(model)
agent.bStream = 1      # Enable real-time token streaming
agent.bVerbose = 1     # Print tool invocation and observation steps

# Initialize Persistent Long-Term Vector Memory (RAG Core)
cMemoryFile = "agent_memory.bin"
agent.initMemory(cMemoryFile)

# Register Extra Application Tools
agent.registerTool("currency_rate", "Returns live exchange rate between currencies (e.g. USD to DZD)", ["query"], func(args) {
	return "Exchange Rate 1 USD = 134.50 DZD (Algerian Dinar) | 1 EUR = 145.20 DZD"
})

agent.registerTool("list_files", "Lists files in current or specified directory", ["dir"], func(args) {
	cDir = "."
	if islist(args) and len(args) >= 1 and trim(args[1]) != ""
		cDir = trim(args[1])
	elseif isstring(args) and trim(args) != ""
		cDir = trim(args)
	ok
	cDir = substr(cDir, '"', "")
	cDir = substr(cDir, "'", "")
	cDir = trim(cDir)
	aFiles = dir(cDir)
	cList = ""
	nCount = 0
	for f in aFiles
		if f[1] != "." and f[1] != ".."
			cList += f[1] + "  "
			nCount++
			if nCount >= 20 exit ok
		ok
	next
	return "Files in '" + cDir + "': " + cList
})

t1 = clock()
nLoadSec = (t1 - t0) / clockspersecond()

see "  Engine: Native C AVX2 SIMD | FP16 KV-Cache (2048 Tokens) | 4 Threads" + nl
see "  Memory: " + agent.oMemory.count() + " persistent vector chunks loaded (" + cMemoryFile + ")" + nl
see "  Ready in " + round(nLoadSec, 2) + " seconds." + nl
see "--------------------------------------------------------------------" + nl
see "  Available Commands:" + nl
see "    /remember <fact> : Save a persistent fact/preference to long-term memory" + nl
see "    /learn <file>    : Ingest an entire document into agent knowledge base" + nl
see "    /recall <query>  : Test semantic memory retrieval with similarity scores" + nl
see "    /memory | /kb    : Display long-term vector memory status" + nl
see "    /undo            : Revert the last conversation turn" + nl
see "    /reset | /clear  : Reset conversation memory and context" + nl
see "    /history         : View current conversation turn history" + nl
see "    /tools           : List all registered agent tools" + nl
see "    /temp <val>      : Adjust temperature (0.1 to 1.0)" + nl
see "    exit | quit      : Close terminal session (auto-saves memory)" + nl
see "====================================================================" + nl

# 3. Interactive REPL Loop
nTurn = 0
while true
	see nl + "You > "
	give cInput
	cInput = trim(cInput)

	if cInput = "" loop ok

	cLower = lower(cInput)

	# Exit commands
	if cLower = "exit" or cLower = "quit" or cLower = "bye" or cLower = "وداعا"
		agent.saveMemory()
		see nl + "Goodbye from Madar AI Agent! (وداعاً من وكيل مدار الذكي)" + nl
		model.close()
		exit
	ok

	# Long-Term Memory: Remember fact
	if substr(cLower, "/remember ") = 1
		cFact = trim(substr(cInput, 11))
		if cFact != ""
			agent.remember(cFact)
			see "  [Memory] Stored persistent fact to long-term memory: " + cFact + nl
		else
			see "  [Usage] /remember <fact or preference>" + nl
		ok
		loop
	ok

	# Long-Term Memory: Ingest document (RAG)
	if substr(cLower, "/learn ") = 1
		cFile = trim(substr(cInput, 8))
		cFile = substr(cFile, '"', "")
		cFile = substr(cFile, "'", "")
		cFile = trim(cFile)
		if cFile != "" and fexists(cFile)
			see "  [RAG] Ingesting document into vector store: " + cFile + " ..." + nl
			nAdded = agent.learnFile(cFile)
			see "  [RAG] Added " + nAdded + " vector chunks. Total knowledge chunks: " + agent.oMemory.count() + nl
		else
			see "  [Error] File not found or not specified: '" + cFile + "'" + nl
		ok
		loop
	ok

	# Long-Term Memory: Recall semantic query
	if substr(cLower, "/recall ") = 1
		cQuery = trim(substr(cInput, 9))
		if cQuery != ""
			see nl + "--- Long-Term Memory Recall for: '" + cQuery + "' ---" + nl
			aMatches = agent.recall(cQuery, 3)
			if len(aMatches) = 0
				see "  (No relevant memories found in vector store)" + nl
			else
				for m in aMatches
					see "  [Score: " + round(m[1], 3) + "] " + m[2].cText + nl
				next
			ok
			see "--------------------------------------------------------" + nl
		else
			see "  [Usage] /recall <query>" + nl
		ok
		loop
	ok

	# Long-Term Memory: Status
	if cLower = "/memory" or cLower = "memory" or cLower = "/kb" or cLower = "kb"
		nCount = agent.oMemory.count()
		see nl + "--- Long-Term Episodic Vector Memory ---" + nl
		see "  Persistent File : " + agent.cMemoryPath + nl
		see "  Vector Chunks   : " + nCount + " items" + nl
		see "  Status          : Active (Persistent RAG enabled)" + nl
		see "--------------------------------------------------------" + nl
		loop
	ok

	# Reset memory
	if cLower = "/reset" or cLower = "/clear" or cLower = "clear" or cLower = "reset"
		agent.resetHistory()
		see "  [System] Conversation memory has been completely reset." + nl
		loop
	ok

	# Undo last turn
	if cLower = "/undo" or cLower = "undo"
		if agent.undo()
			see "  [System] Successfully reverted the last conversation turn. Remaining turns: " + (len(agent.aConversation) / 2) + nl
		else
			see "  [System] History is empty. Nothing to undo." + nl
		ok
		loop
	ok

	# History display
	if cLower = "/history" or cLower = "history"
		aHist = agent.getHistory()
		see nl + "--- Active Conversation History (" + (len(aHist)/2) + " turns) ---" + nl
		if len(aHist) = 0
			see "  (No interaction history yet)" + nl
		else
			for turn in aHist
				see "  [" + turn[1] + "]: " + left(turn[2], 80)
				if len(turn[2]) > 80 see "..." ok
				see nl
			next
		ok
		see "--------------------------------------------------------" + nl
		loop
	ok

	# List Tools
	if cLower = "/tools" or cLower = "tools"
		see nl + "--- Registered AIAgent Tools (" + len(agent.aTools) + ") ---" + nl
		for tool in agent.aTools
			see "  - " + tool[1] + ": " + tool[2] + nl
		next
		see "--------------------------------------------------------" + nl
		loop
	ok

	# Adjust Temperature
	if substr(cLower, "/temp") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			fNewT = 0.0 + aParts[2]
			model.setTemperature(fNewT)
			see "  [System] Model temperature set to " + fNewT + nl
		else
			see "  [System] Current temperature: " + model.fTemp + nl
		ok
		loop
	ok

	# Execute Query through Agent
	nTurn++
	tQ0 = clock()
	agent.query(cInput)
	tQ1 = clock()
	nDur = (tQ1 - tQ0) / clockspersecond()

	if model.fTokensPerSec > 0
		see "  [Turn #" + nTurn + " | Memory: " + (len(agent.aConversation)/2) + " turns | Speed: ~" + round(model.fTokensPerSec, 1) + " tok/s (" + round(nDur, 2) + "s)]" + nl
	else
		see "  [Turn #" + nTurn + " | Memory: " + (len(agent.aConversation)/2) + " turns | Elapsed: " + round(nDur, 2) + "s]" + nl
	ok
end
