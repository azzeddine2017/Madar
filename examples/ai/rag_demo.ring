# ====================================================================
# Madar AI - Local Semantic Search & RAG Knowledge Assistant
# (مدار للذكاء الاصطناعي - نظام استرجاع المعلومات وتوليد الإجابات الدقيقة)
#
# Leverages Madar's native:
#   1. Continuous C Tensors (RingTensor) for embeddings & Cosine Similarity
#   2. Fast GGUF inference & sub-token BPE tokenizer (Arabic/English)
#   3. Advanced slicing (aList[::-1], aList[1:k])
#   4. List comprehensions ([x for x in list if cond])
#   5. f-strings & default argument functions
# ====================================================================

load "stdlibCore.ring"
load "madar_ai.ring"
load "rag.ring"

# 1. Locate Model File
cModelPath = ""
aCandidates = [
	"models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"../../models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"../models/qwen2.5-0.5b-instruct-q4_0.gguf",
	"models/deepseek-r1-distill-qwen-1.5b-q4_0.gguf"
]

for cCand in aCandidates
	if fexists(cCand)
		cModelPath = cCand
		exit
	ok
next

if cModelPath = ""
	see nl + "====================================================================" + nl
	see "  [ERROR] No AI model found in models/ directory!" + nl
	see "====================================================================" + nl
	see "  Please ensure models/qwen2.5-0.5b-instruct-q4_0.gguf is available." + nl
	see "====================================================================" + nl
	bye
ok

# 2. Initialize Model & RAG Pipeline
see nl + "====================================================================" + nl
see "  Madar AI - RAG Knowledge Engine & Semantic Search" + nl
see "  (نظام البحث الدلالي والإجابة الدقيقة من المستندات المحلية)" + nl
see "====================================================================" + nl
see f"  Loading Model: {cModelPath}" + nl

t0 = clock()
aiModel = new QwenModel(cModelPath)
aiModel.setThreads(4)
aiModel.setTemperature(0.2) # Low temperature for factual RAG responses

store = new VectorStore(aiModel)
rag = new RAGPipeline(aiModel, store)
rag.setSystemPrompt("You are an accurate, factual AI assistant. Answer the user question concisely using ONLY the provided Document Context. If the context does not contain the answer, state clearly that the information is not in the knowledge base.")

t1 = clock()
nLoadSec = (t1 - t0) / clockspersecond()
see f"  Model loaded in {nLoadSec} seconds." + nl

# 3. Seed Initial Bilingual Knowledge Base
see "  Indexing initial knowledge base into native continuous vector store..." + nl

aSeedKnowledge = [
	"لغة مدار (Madar) هي بيئة برمجية وتطويرية عربية حديثة خفيفة الوزن مبنية على لغة رينج (Ring)، تدعم المصفوفات الممتدة ومحرك استنتاج ذكاء اصطناعي محلي خفيف الوزن فائق السرعة مدمج بلغة C99.",
	"Madar programming language features native continuous tensors, high-performance vectorized operations, GGUF model execution, f-strings, list comprehensions, and default arguments without external dependencies.",
	"محرك الاستنتاج في مدار يدعم نماذج Qwen2.5 و DeepSeek-R1 بصيغة GGUF المكممة (Q4_0 و Q8_0) مع استهلاك ذاكرة منخفض جداً أقل من 400 ميغابايت.",
	"عاصمة الجمهورية العربية السورية هي مدينة دمشق، وتعتبر من أقدم العواصم المأهولة باستمرار في التاريخ الإنساني.",
	"The speed of light in vacuum is approximately 299,792,458 meters per second (about 300,000 km/s).",
	"تأسست مكتبة الإسكندرية القديمة في مصر في القرن الثالث قبل الميلاد وكانت أكبر وأهم مكتبة في العالم القديم.",
	"Vector Search in Madar works by computing L2-normalized last-token hidden states directly from the LLM, followed by native C cosine similarity on continuous tensors.",
	"جبل إفرست هو أعلى قمة جبلية على وجه الأرض بارتفاع يبلغ 8,848.86 متراً فوق سطح البحر، ويقع في سلسلة جبال الهيمالايا."
]

for cFact in aSeedKnowledge
	store.addText(cFact)
next

see f"  Indexed {store.count()} document chunks successfully." + nl
see "====================================================================" + nl
see "  Commands:" + nl
see "    /search <text>     : Semantic search only (shows matching chunks & similarity)" + nl
see "    /add <fact>        : Add new knowledge to vector database dynamically" + nl
see "    /file <path>       : Ingest an entire text/markdown file into knowledge base" + nl
see "    /list              : Display all indexed knowledge chunks" + nl
see "    /clear             : Clear vector memory" + nl
see "    exit / quit        : Close application" + nl
see "====================================================================" + nl

# 4. Interactive RAG Query Loop
while true
	see nl + "Query / السؤال > "
	give cInput
	cInput = trim(cInput)

	if cInput = ""
		loop
	ok

	cLower = lower(cInput)

	# Exit command
	if cLower = "exit" or cLower = "quit" or cLower = "bye"
		see nl + "Closing Madar AI Engine. Goodbye! (وداعاً)" + nl
		aiModel.close()
		exit
	ok

	# Clear memory
	if cLower = "/clear"
		store.clear()
		see "  [System] Vector memory has been cleared." + nl
		loop
	ok

	# List chunks
	if cLower = "/list"
		see f"  [Knowledge Store: {store.count()} chunks]" + nl
		nCount = 1
		for ch in store.aChunks
			see f"    [{nCount}] {ch.cId}: " + substr(ch.cText, 1, 80)
			if len(ch.cText) > 80 see "..." ok
			see nl
			nCount++
		next
		loop
	ok

	# Add knowledge fact dynamically
	if substr(cLower, "/add ") = 1
		cNewFact = trim(substr(cInput, 6))
		if cNewFact != ""
			tEmb0 = clock()
			store.addText(cNewFact)
			tEmb1 = clock()
			nEmbSec = (tEmb1 - tEmb0) / clockspersecond()
			see f"  [Indexed] Added new chunk into vector store in {nEmbSec}s (Total: {store.count()})." + nl
		ok
		loop
	ok

	# Add file
	if substr(cLower, "/file ") = 1
		cFilePath = trim(substr(cInput, 7))
		if not fexists(cFilePath)
			see f"  [Error] File not found: {cFilePath}" + nl
		else
			tF0 = clock()
			nAdded = store.addFile(cFilePath)
			tF1 = clock()
			nSec = (tF1 - tF0) / clockspersecond()
			see f"  [File Ingested] {cFilePath}: Added {nAdded} chunks in {nSec}s (Total: {store.count()})." + nl
		ok
		loop
	ok

	# Pure Semantic Search (No generation)
	if substr(cLower, "/search ") = 1
		cQuery = trim(substr(cInput, 9))
		tS0 = clock()
		aMatches = store.search(cQuery, 3)
		tS1 = clock()
		nSearchSec = (tS1 - tS0) / clockspersecond()

		see f"  [Semantic Search Results ({nSearchSec}s)]:" + nl
		if len(aMatches) = 0
			see "    No matching chunks found." + nl
		else
			nRank = 1
			for m in aMatches
				fScore = m[1]
				chunkObj = m[2]
				see f"    #{nRank} [Similarity: {fScore}] {chunkObj.cId}:" + nl
				see f"       {chunkObj.cText}" + nl
				nRank++
			next
		ok
		loop
	ok

	# Standard RAG Query (Retrieve + Generate Answer)
	see nl + "  [Retrieving relevant knowledge...]" + nl
	tQ0 = clock()
	aMatches = store.search(cInput, 2)
	tQ1 = clock()
	nRetSec = (tQ1 - tQ0) / clockspersecond()

	if len(aMatches) > 0
		see f"  [Retrieved {len(aMatches)} relevant chunks in {nRetSec}s | Top similarity: {aMatches[1][1]}]" + nl
	else
		see "  [No relevant context found in local store, answering directly...]" + nl
	ok

	see nl + "Answer / الإجابة:" + nl + "----------------------------------------------------" + nl
	tG0 = clock()
	cAnswer = rag.ask(cInput, 2, 128, true)
	tG1 = clock()
	see nl + "----------------------------------------------------" + nl
	nGenSec = (tG1 - tG0) / clockspersecond()
	if nGenSec > 0
		aTokens = aiModel.tokenize(cAnswer)
		fTps = len(aTokens) / nGenSec
		see f"  [Performance: {len(aTokens)} tokens in {nGenSec}s ({fTps} tokens/sec)]" + nl
	ok
end
