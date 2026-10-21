# ====================================================================
# Madar AI - Lightweight Vector Store & RAG Pipeline
# Leverages Madar's native continuous tensors, f-strings, default args,
# list comprehensions, and advanced slicing.
# ====================================================================

load "stdlibCore.ring"

class DocumentChunk
	cId = ""
	cText = ""
	tEmbedding = ""
	aMetadata = []

	func init(cChunkId, cChunkText, tEmb = "", aMeta = [])
		cId = cChunkId
		cText = cChunkText
		tEmbedding = tEmb
		aMetadata = aMeta
		return self

class VectorStore
	model = ""
	aChunks = []
	nDim = 896

	func init(modelObj)
		model = modelObj
		return self

	# 1. Add Text with automatic embedding calculation (Leverages Default Args)
	func addText(cText, cId = "", aMeta = [])
		if cText = "" or trim(cText) = ""
			return false
		ok
		if cId = ""
			cId = f"chunk_{len(aChunks) + 1}"
		ok

		# Compute embedding using native continuous tensor
		tEmb = model.embedding(cText)
		chunk = new DocumentChunk(cId, cText, tEmb, aMeta)
		aChunks + chunk
		return chunk

	# 2. Add multiple text chunks
	func addTexts(aTextList)
		for text in aTextList
			addText(text)
		next

	# 3. Add text file and split into paragraph chunks
	func addFile(cFilePath, nMinChars = 40)
		if not fexists(cFilePath)
			raise(f"File not found: {cFilePath}")
		ok
		cContent = read(cFilePath)
		aParagraphs = split(cContent, nl + nl)

		# Use list comprehension to filter empty / short paragraphs
		aValidParagraphs = [ trim(p) for p in aParagraphs if len(trim(p)) >= nMinChars ]

		nCount = 0
		for p in aValidParagraphs
			addText(p, f"{cFilePath}_p{nCount + 1}", ["source" = cFilePath])
			nCount++
		next
		return nCount

	# 4. Semantic Search (Leverages Default Args, List Comprehensions & Advanced Slicing)
	func search(cQuery, nTopK = 3, fMinScore = 0.0)
		if len(aChunks) = 0
			return []
		ok

		# Compute query embedding
		qVec = model.embedding(cQuery)

		# Compute similarity scores for all chunks using list comprehension & native tensor cosine similarity
		aScored = [ [tensor_cosine_similarity(qVec, ch.tEmbedding), ch] for ch in aChunks ]

		# Filter by minimum score threshold using list comprehension
		aFiltered = [ item for item in aScored if item[1] >= fMinScore ]

		# Sort in descending order by similarity score
		aFiltered = sort(aFiltered, 1)
		aReversed = aFiltered[::-1] # Leverages Madar's native slicing reversal!

		# Take top-K results using Madar's native slicing
		if len(aReversed) > nTopK
			return aReversed[1:nTopK]
		ok
		return aReversed

	func count()
		return len(aChunks)

	func clear()
		aChunks = []

class RAGPipeline
	model = ""
	store = ""
	cSystemPrompt = ""

	func init(modelObj, storeObj = "")
		model = modelObj
		if storeObj != ""
			store = storeObj
		else
			store = new VectorStore(modelObj)
		ok
		cSystemPrompt = "You are a factual, concise AI assistant. Answer the user question using ONLY the provided reference context. If the answer cannot be found in the context, say that the information is not available."
		return self

	func setSystemPrompt(cPrompt)
		cSystemPrompt = cPrompt

	# Answer user question augmented by retrieved context (Leverages Default Args & f-strings)
	func ask(cQuestion, nTopK = 3, nMaxTokens = 128, bStream = false)
		# 1. Retrieve top matching chunks
		aResults = store.search(cQuestion, nTopK)

		if len(aResults) = 0
			# Fallback to direct model answering if no context stored
			return model.chat(cQuestion, nMaxTokens)
		ok

		# 2. Build Context String from retrieved chunks
		cContext = ""
		for res in aResults
			fScore = res[1]
			chunkObj = res[2]
			cContext += f"[Document Context (Score: {fScore})]:" + nl + chunkObj.cText + nl + nl
		next

		# 3. Construct Augmented Prompt using f-strings
		cPrompt = f"<|im_start|>system" + nl +
		          f"{cSystemPrompt}" + nl + nl +
		          f"Context Reference:" + nl +
		          f"{cContext}<|im_end|>" + nl +
		          f"<|im_start|>user" + nl +
		          f"{cQuestion}<|im_end|>" + nl +
		          f"<|im_start|>assistant" + nl

		# 4. Generate Answer
		if bStream
			return model.generateStream(cPrompt, nMaxTokens)
		else
			return model.generate(cPrompt, nMaxTokens)
		ok
