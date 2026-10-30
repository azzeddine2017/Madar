# ====================================================================
# Madar AI - Fast Document Semantic Search (CLI Tool)
# (أداة البحث الدلالي في المستندات والملفات المحلية عبر المعنى وليس الكلمات الحرفية)
#
# Usage:
#   bin\ring.exe examples\ai\doc_search.ring <document_path> "<query>"
#   ring --json-errors examples\ai\doc_search.ring README.md "gpu"
# Or run without arguments for interactive file search mode.
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"
load "chronos.ring"

func main {
	# 1. Multi-Path Model Locator
	cModelPath = findModel([
		"qwen2.5-0.5b-instruct-q4_0.gguf",
		"deepseek-r1-distill-qwen-1.5b-q4_0.gguf",
		"qwen2.5-coder-1.5b-instruct-q4_0.gguf"
	])

	if cModelPath = "" {
		? nl + "[ERROR] AI model not found in models/ directory!"
		? "Please run 'tools\download_model.bat' to download a supported model."
		bye
	}

	# 2. Parse CLI Positional Arguments (Smart Filter ignoring --flags and script name)
	aArgs = getScriptArgs()
	cDocPath = ""
	cQuery = ""

	if len(aArgs) >= 1 {
		cDocPath = aArgs[1]
	}
	if len(aArgs) >= 2 {
		cQuery = aArgs[2]
	}

	? nl + "===================================================================="
	? "  Madar AI - Semantic Document Search Engine"
	? "  (محرك البحث الدلالي في المستندات المحلية عبر الذكاء الاصطناعي)"
	? "===================================================================="

	# If arguments not provided, ask interactively
	if cDocPath = "" {
		see "Enter file path to index (e.g. README.md or docs/INSTALL.md): "
		give cDocPath
		cDocPath = trim(cDocPath)
	}

	if not fexists(cDocPath) {
		? f"[ERROR] File '{cDocPath}' does not exist!"
		bye
	}

	# 3. Load Model & Vectorize File
	? f"Loading model: {cModelPath} ..."
	oModel = new QwenModel(cModelPath)
	oModel.setThreads(4)

	oStore = new VectorStore(oModel)
	oTimer = new Chronos()

	? f"Indexing document: {cDocPath} ..."
	oTimer.reset()
	nChunks = oStore.addFile(cDocPath, 30)
	oTimer.stop()

	? f"Document indexed: {nChunks} chunks processed in {oTimer.elapsed()}."
	? "===================================================================="

	if cQuery != "" {
		executeSearch(oModel, oStore, cQuery)
		bye
	}

	# 4. Interactive Search Loop
	while true {
		? nl + "Enter search query (or 'exit'): "
		give cUserQ
		cUserQ = trim(cUserQ)
		if cUserQ = "" { loop }
		if lower(cUserQ) = "exit" or lower(cUserQ) = "quit" {
			exit
		}
		executeSearch(oModel, oStore, cUserQ)
	}
}

# --------------------------------------------------------------------
# Helper Functions
# --------------------------------------------------------------------

func executeSearch(oModel, oStore, cSearchQuery) {
	? nl + f"Searching for: '{cSearchQuery}' ..."
	oSearchTimer = new Chronos()
	oSearchTimer.reset()
	aMatches = oStore.search(cSearchQuery, 3)
	oSearchTimer.stop()

	? f"Results ({oSearchTimer.elapsed()}):"
	if len(aMatches) = 0 {
		? "  No matches found."
		return
	}

	nRank = 1
	for res in aMatches {
		fScore = res[1]
		chunk = res[2]
		? nl + f"--- Match #{nRank} [Cosine Similarity: {round(fScore, 4)}] ---"
		? chunk.cText
		nRank++
	}
	? "----------------------------------------------------"

	# Real-Time Streaming Answer from top matched context
	if len(aMatches) > 0 {
		? nl + "AI Answer (Streaming):"
		cTopChunk = aMatches[1][2].cText
		cPrompt = "<|im_start|>system" + nl +
		          "أجب عن السؤال باختصار وبدقة باللغة العربية بناءً على هذا النص المرجعي: " + cTopChunk + "<|im_end|>" + nl +
		          "<|im_start|>user" + nl + cSearchQuery + "<|im_end|>" + nl +
		          "<|im_start|>assistant" + nl
		oModel.generateStream(cPrompt, 80)
		? ""
		? "----------------------------------------------------"
	}
}

func getScriptArgs() {
	aCleanArgs = []
	for i = 2 to len(sysargv) {
		cArg = sysargv[i]
		# Skip flags like --json-errors, -e, /f
		if left(cArg, 1) = "-" or left(cArg, 1) = "/" {
			loop
		}
		# Skip the running ring script if sysargv included it
		if substr(lower(cArg), ".ring") > 0 {
			loop
		}
		aCleanArgs + cArg
	}
	return aCleanArgs
}

func findModel(aCandidates) {
	aSearchDirs = ["models/", "../../models/", "../models/", "../../../models/"]
	for cName in aCandidates {
		for cDir in aSearchDirs {
			cFullPath = cDir + cName
			if fexists(cFullPath) { return cFullPath }
		}
	}
	return ""
}
