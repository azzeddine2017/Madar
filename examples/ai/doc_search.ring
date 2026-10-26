# ====================================================================
# Madar AI - Fast Document Semantic Search (CLI Tool)
# (أداة البحث الدلالي في المستندات والملفات المحلية عبر المعنى وليس الكلمات الحرفية)
#
# Usage:
#   bin\ring.exe examples\ai\doc_search.ring <document_path> "<query>"
# Or run without arguments for interactive file search mode.
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"

# 1. Locate Model
cModelPath = "models/qwen2.5-0.5b-instruct-q4_0.gguf"
if not fexists(cModelPath)
	cModelPath = "../../models/qwen2.5-0.5b-instruct-q4_0.gguf"
ok

if not fexists(cModelPath)
	see nl + "[ERROR] AI model not found in models/qwen2.5-0.5b-instruct-q4_0.gguf" + nl
	bye
ok

# 2. Parse CLI Arguments
cDocPath = ""
cQuery = ""

if len(sysargv) >= 2
	cDocPath = sysargv[2]
ok
if len(sysargv) >= 3
	cQuery = sysargv[3]
ok

see nl + "====================================================================" + nl
see "  Madar AI - Semantic Document Search Engine" + nl
see "  (محرك البحث الدلالي في المستندات المحلية عبر الذكاء الاصطناعي)" + nl
see "====================================================================" + nl

# If arguments not provided, ask interactively
if cDocPath = ""
	see "Enter file path to index (e.g. README.md or docs/ARCHITECTURE.md): "
	give cDocPath
	cDocPath = trim(cDocPath)
ok

if not fexists(cDocPath)
	see f"[ERROR] File '{cDocPath}' does not exist!" + nl
	bye
ok

# 3. Load Model & Vectorize File
see f"Loading model: {cModelPath} ..." + nl
aiModel = new QwenModel(cModelPath)
aiModel.setThreads(4)

store = new VectorStore(aiModel)

see f"Indexing document: {cDocPath} ..." + nl
t0 = clock()
nChunks = store.addFile(cDocPath, 30)
t1 = clock()
nSec = (t1 - t0) / clockspersecond()

see f"Document indexed: {nChunks} chunks processed in {nSec}s." + nl
see "====================================================================" + nl

func executeSearch(cSearchQuery)
	see nl + f"Searching for: '{cSearchQuery}' ..." + nl
	tS0 = clock()
	aMatches = store.search(cSearchQuery, 3)
	tS1 = clock()
	nDur = (tS1 - tS0) / clockspersecond()

	see f"Results ({nDur}s):" + nl
	if len(aMatches) = 0
		see "  No matches found." + nl
		return
	ok

	nRank = 1
	for res in aMatches
		fScore = res[1]
		chunk = res[2]
		see nl + f"--- Match #{nRank} [Cosine Similarity: {fScore}] ---" + nl
		see chunk.cText + nl
		nRank++
	next
	see "----------------------------------------------------" + nl

	# Real-Time Streaming Answer from top matched context
	if len(aMatches) > 0
		see nl + "AI Answer (Streaming):" + nl
		cTopChunk = aMatches[1][2].cText
		cPrompt = "<|im_start|>system" + nl +
		          "أجب عن السؤال باختصار وبدقة باللغة العربية بناءً على هذا النص المرجعي: " + cTopChunk + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + cSearchQuery + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
		aiModel.generateStream(cPrompt, 80)
		see nl + "----------------------------------------------------" + nl
	ok

if cQuery != ""
	executeSearch(cQuery)
	bye
ok

# Interactive Search Loop
while true
	see nl + "Enter search query (or 'exit'): "
	give cUserQ
	cUserQ = trim(cUserQ)
	if cUserQ = "" loop ok
	if lower(cUserQ) = "exit" or lower(cUserQ) = "quit"
		exit
	ok
	executeSearch(cUserQ)
end
