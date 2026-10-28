# ====================================================================
#   Madar AI - Interactive Autonomous Agent CLI & REPL Terminal
#   (الطرفية التفاعلية الشاملة للوكيل الذكي في لغة مدار)
# ====================================================================
#
# Features:
#   1. Autonomous multi-lingual tool execution (Files, Math, System, CSV/DataFrame)
#   2. Multi-turn conversational memory with /undo and /reset
#   3. Real-time token streaming directly to terminal
#   4. High-Precision BGE-M3 Dual-Engine RAG Pipeline (1024-dim Normalized Embeddings)
#   5. Dynamic tool inspection and runtime parameter adjustment
# ====================================================================

load "stdlibCore.ring"
load "agent.ring"

# 1. Locate GGUF Models & CLI Options
cModelPath = ""
bPreferCoder = false
bPreferDeepSeek = false
bPrefer05B = false
bPrefer3B = false

for arg in sysargv
	cArg = lower(arg)
	if substr(cArg, "coder") > 0 or substr(cArg, "qwen") > 0
		bPreferCoder = true
	ok
	if substr(cArg, "deepseek") > 0 or substr(cArg, "r1") > 0
		bPreferDeepSeek = true
	ok
	if substr(cArg, "0.5") > 0
		bPrefer05B = true
	ok
	if substr(cArg, "3b") > 0
		bPrefer3B = true
	ok
next

if bPreferDeepSeek
	aCandidates = [
		"models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"../../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"models/deepseek-r1-distill-qwen-7b-q4_0.gguf",
		"../../models/deepseek-r1-distill-qwen-7b-q4_0.gguf"
	]
elseif bPrefer05B
	aCandidates = [
		"models/qwen2.5-0.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-0.5b-instruct-q4_0.gguf",
		"../models/qwen2.5-0.5b-instruct-q4_0.gguf"
	]
elseif bPrefer3B
	aCandidates = [
		"models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"../../models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"../models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"models/qwen2.5-3b-instruct-q4_0.gguf",
		"../../models/qwen2.5-3b-instruct-q4_0.gguf"
	]
else
	# Default preference order: Coder 1.5B -> DeepSeek 1.5B -> 0.5B -> 3B -> 7B
	aCandidates = [
		"models/qwen2.5-coder-1.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf",
		"../models/qwen2.5-coder-1.5b-instruct-q4_0.gguf",
		"models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"../../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"../models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"models/qwen2.5-1.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-1.5b-instruct-q4_0.gguf",
		"models/qwen2.5-0.5b-instruct-q4_0.gguf",
		"../../models/qwen2.5-0.5b-instruct-q4_0.gguf",
		"models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"../../models/qwen2.5-coder-3b-instruct-q4_0.gguf",
		"models/qwen2.5-7b-instruct-q4_0.gguf",
		"../../models/qwen2.5-7b-instruct-q4_0.gguf"
	]
ok

for cCand in aCandidates
	if fexists(cCand)
		cModelPath = cCand
		exit
	ok
next

if not fexists(cModelPath)
	see nl + "====================================================================" + nl
	see "  [ERROR] No AI chat model found in models/ directory!" + nl
	see "  Please download a model first using tools\download_model.bat" + nl
	see "====================================================================" + nl
	bye
ok

# 2. Locate Dedicated BGE-M3 Embedding Model
cBgePath = ""
aBgeCandidates = [
	"models/bge-m3-q4_0.gguf",
	"../../models/bge-m3-q4_0.gguf",
	"../models/bge-m3-q4_0.gguf"
]
for cCand in aBgeCandidates
	if fexists(cCand)
		cBgePath = cCand
		exit
	ok
next

# 3. Locate Knowledge Base Memory File (agent_memory.bin)
cMemoryFile = "agent_memory.bin"
aMemCandidates = [
	"agent_memory.bin",
	"examples/ai/agent_memory.bin",
	"../../examples/ai/agent_memory.bin",
	"../agent_memory.bin",
	"../../agent_memory.bin"
]
for cCand in aMemCandidates
	if fexists(cCand)
		cMemoryFile = cCand
		exit
	ok
next

# 4. Initialize Models & Agent (Dual-Engine Architecture)
see nl + "====================================================================" + nl
see "  Madar AI Agent - Autonomous Interactive CLI Terminal" + nl
see "  (الطرفية التفاعلية للوكيل الذكي: استدعاء الأدوات والذاكرة المتصلة)" + nl
see "====================================================================" + nl
see "  Chat Model: " + cModelPath + nl

t0 = clock()
if substr(lower(cModelPath), "deepseek") > 0
	oChatModel = new DeepSeekModel(cModelPath)
else
	oChatModel = new QwenModel(cModelPath)
ok
oChatModel.setThreads(4)
oChatModel.setTemperature(0.3)
oChatModel.setGPU(1)

embed_model = NULL
if cBgePath != ""
	see "  Embedding Engine: BGE-M3 (1024-dim, OpenCL GPU Accelerated) -> " + cBgePath + nl
	embed_model = model_open(cBgePath)
	embed_model.setThreads(4)
	embed_model.setGPU(1)
else
	see "  Embedding Engine: Shared Chat Model Embeddings (BGE-M3 not found)" + nl
ok

agent = new AIAgent(oChatModel, embed_model)
agent.bStream = 1          # Enable real-time token streaming
agent.bVerbose = 1         # Print tool invocation and observation steps
agent.bAutonomousTools = 1 # Official Qwen2.5-Coder Function Calling Schema

# Initialize Persistent Long-Term Vector Memory (RAG Core)
agent.initMemory(cMemoryFile)

# Register Core Tools
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

see "  Memory: " + agent.oMemory.count() + " knowledge chunks loaded (" + cMemoryFile + ")" + nl
see "  Ready in " + round(nLoadSec, 2) + " seconds." + nl
see "--------------------------------------------------------------------" + nl
see "  Available Commands:" + nl
see "    /remember <fact> : Save a persistent fact/preference to long-term memory" + nl
see "    /learn <file/dir>: Ingest document or directory (.md, .txt, .pdf, .ring)" + nl
see "    /recall <query>  : Test semantic memory retrieval with similarity scores" + nl
see "    /memory | /kb    : Display long-term vector memory status" + nl
see "    /undo            : Revert the last conversation turn" + nl
see "    /reset | /clear  : Reset conversation memory and context" + nl
see "    /clear_memory    : Clear all persistent RAG vector memory" + nl
see "    /history         : View current conversation turn history" + nl
see "    /tools           : List all registered agent tools" + nl
see "    /tokens <N>      : Set maximum generation tokens (64 - 4096)" + nl
see "    /temp <val>      : Adjust temperature (0.1 to 1.0)" + nl
see "    /gpu on | off    : Toggle GPU OpenCL acceleration" + nl
see "    exit | quit      : Close terminal session (auto-saves memory)" + nl
see "====================================================================" + nl

# 5. Interactive REPL Loop
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
		oChatModel.close()
		if embed_model != NULL embed_model.close() ok
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

	# Long-Term Memory: Ingest document or directory (RAG)
	if substr(cLower, "/learn ") = 1
		cTarget = trim(substr(cInput, 8))
		cTarget = substr(cTarget, '"', "")
		cTarget = substr(cTarget, "'", "")
		cTarget = trim(cTarget)

		# Auto-resolve relative paths if needed
		cResolved = cTarget
		if not fexists(cResolved) and not direxists(cResolved)
			if fexists("../../" + cTarget) or direxists("../../" + cTarget)
				cResolved = "../../" + cTarget
			elseif fexists("../" + cTarget) or direxists("../" + cTarget)
				cResolved = "../" + cTarget
			ok
		ok

		if cResolved != "" and (fexists(cResolved) or direxists(cResolved))
			if direxists(cResolved)
				see nl + "  [RAG] Detected directory. Scanning for documents (.md, .txt, .pdf, .ring)..." + nl
				see "  [RAG] Path: " + cResolved + nl
				tLearn0 = clock()
				aRes = agent.learnPath(cResolved, func(fPath, nIdx, nTotal, nChunks, cElapsed) {
					see "    [" + nIdx + "/" + nTotal + "] Ingested: " + JustFileName(fPath) + " (+" + nChunks + " chunks in " + cElapsed + ") | RAG: " + agent.oMemory.count() + " chunks (Saved to disk)" + nl
				})
				tLearn1 = clock()
				nSec = (tLearn1 - tLearn0) / clockspersecond()
				see "  [RAG] Directory ingestion complete in " + round(nSec, 2) + "s." + nl
				see "  [RAG] Successfully processed " + aRes[2] + " files, added " + aRes[1] + " vector chunks." + nl
				see "  [RAG] Total knowledge chunks in persistent vector store: " + agent.oMemory.count() + nl
			else
				cExt = lower(JustFileExt(cResolved))
				see nl + "  [RAG] Ingesting document [" + upper(cExt) + "]: " + cResolved + " ..." + nl
				aRes = agent.learnPath(cResolved, func(fPath, nIdx, nTotal, nChunks, cElapsed) {
					see "    -> Ingested: " + JustFileName(fPath) + " (+" + nChunks + " chunks in " + cElapsed + ") | RAG: " + agent.oMemory.count() + " chunks (Saved to disk)" + nl
				})
				see "  [RAG] Ingested " + aRes[1] + " vector chunks. Total knowledge chunks: " + agent.oMemory.count() + nl
			ok
		else
			see "  [Error] File or directory not found: '" + cTarget + "'" + nl
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
		see "  Status          : Active (Persistent BGE-M3 RAG enabled)" + nl
		see "--------------------------------------------------------" + nl
		loop
	ok

	# Reset memory
	if cLower = "/reset" or cLower = "/clear" or cLower = "clear" or cLower = "reset"
		agent.resetHistory()
		see "  [System] Conversation memory has been completely reset." + nl
		loop
	ok

	# Clear Persistent Vector Memory
	if cLower = "/clear_memory" or cLower = "/clearmemory" or cLower = "/reset_kb" or cLower = "/reset_memory"
		agent.oMemory.clear()
		agent.saveMemory()
		see "  [RAG] Vector knowledge base has been completely reset (" + agent.cMemoryPath + " cleared)." + nl
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
			oChatModel.setTemperature(fNewT)
			see "  [System] Model temperature set to " + fNewT + nl
		else
			see "  [System] Current temperature: " + oChatModel.fTemp + nl
		ok
		loop
	ok

	# Adjust Max Tokens
	if substr(cLower, "/tokens") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			nNewTok = 0 + aParts[2]
			if nNewTok < 16 nNewTok = 16 ok
			if nNewTok > 4096 nNewTok = 4096 ok
			agent.nMaxOutputTokens = nNewTok
			see "  [System] Max output tokens set to " + nNewTok + nl
		else
			see "  [System] Current max tokens: " + agent.nMaxOutputTokens + nl
		ok
		loop
	ok

	# Adjust GPU Acceleration
	if substr(cLower, "/gpu") = 1
		aParts = split(cInput, " ")
		if len(aParts) >= 2
			cMode = lower(aParts[2])
			if cMode = "off" or cMode = "0"
				oChatModel.setGPU(0)
				if embed_model != NULL embed_model.setGPU(0) ok
				see "  [System] GPU acceleration disabled (Running on CPU AVX2)." + nl
			else
				oChatModel.setGPU(1)
				if embed_model != NULL embed_model.setGPU(1) ok
				see "  [System] GPU acceleration enabled." + nl
			ok
		else
			see "  [System] Usage: /gpu on | /gpu off" + nl
		ok
		loop
	ok

	# Execute Query through Agent
	nTurn++
	tQ0 = clock()
	agent.query(cInput)
	tQ1 = clock()
	nDur = (tQ1 - tQ0) / clockspersecond()

	if oChatModel.fTokensPerSec > 0
		see "  [Turn #" + nTurn + " | Memory: " + (len(agent.aConversation)/2) + " turns | Speed: ~" + round(oChatModel.fTokensPerSec, 1) + " tok/s (" + round(nDur, 2) + "s)]" + nl
	else
		see "  [Turn #" + nTurn + " | Memory: " + (len(agent.aConversation)/2) + " turns | Elapsed: " + round(nDur, 2) + "s]" + nl
	ok
end
