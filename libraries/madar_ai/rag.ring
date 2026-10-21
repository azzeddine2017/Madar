# ====================================================================
# Madar AI - Lightweight Vector Store & RAG Pipeline
# Leverages Madar's native continuous tensors, f-strings, default args,
# list comprehensions, advanced slicing, and AlQalam integration:
#   - QalamReader: Direct PDF text extraction
#   - QalamInk: Zero-fragmentation C++ string accumulation
#   - QalamIndex: High-speed O(1) keyword lookup & Hybrid Search
#   - QalamChronos: Nanosecond-precision benchmarking
# ====================================================================



# Safely load AlQalam if available
try
	load "alqalam.ring"
catch
	# Running without AlQalam
done

# --------------------------------------------------------------------
# Global Function: vector_search
# Performs fast cosine similarity search over chunks or document tensors.
# If nTopK = 1, returns the text string of the best matching chunk directly!
# --------------------------------------------------------------------
func vector_search(query_vector, doc_source, nTopK = 1)
	aChunksList = []

	# Check if doc_source is a VectorStore instance
	if isobject(doc_source)
		aChunksList = doc_source.aChunks
	elseif islist(doc_source)
		aChunksList = doc_source
	ok

	if len(aChunksList) = 0
		if nTopK = 1
			return ""
		ok
		return []
	ok

	# Score all items using native tensor cosine similarity
	aScored = []
	for item in aChunksList
		tEmb = ""
		cTxt = ""
		if isobject(item)
			tEmb = item.tEmbedding
			cTxt = item.cText
		elseif islist(item)
			if len(item) >= 2
				cTxt = item[1]
				tEmb = item[2]
			ok
		ok

		if ispointer(tEmb)
			fSim = tensor_cosine_similarity(query_vector, tEmb)
			aScored + [fSim, cTxt, item]
		ok
	next

	if len(aScored) = 0
		if nTopK = 1
			return ""
		ok
		return []
	ok

	# Sort descending by score
	aScored = sort(aScored, 1)
	aRanked = aScored[::-1] # Madar native slice reversal

	if nTopK = 1
		# Return the single best chunk text directly
		return aRanked[1][2]
	ok

	if len(aRanked) > nTopK
		return aRanked[1:nTopK]
	ok
	return aRanked

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

	# 4. Add PDF file using AlQalam QalamReader integration
	func addPDF(cFilePath, nMinChars = 40)
		if not fexists(cFilePath)
			raise(f"PDF File not found: {cFilePath}")
		ok

		cContent = ""
		try
			oReader = new QalamReader
			cContent = oReader.extractPDFText(cFilePath)
		catch
			see f"  [Warning] QalamReader unavailable, fallback to direct read: {cFilePath}" + nl
			cContent = read(cFilePath)
		done

		if cContent = "" or trim(cContent) = ""
			return 0
		ok

		aParagraphs = split(cContent, nl + nl)
		aValid = [ trim(p) for p in aParagraphs if len(trim(p)) >= nMinChars ]

		nCount = 0
		for p in aValid
			addText(p, f"{cFilePath}_p{nCount + 1}", ["source" = cFilePath, "type" = "pdf"])
			nCount++
		next
		return nCount

	# 5. Semantic Search (Leverages Default Args, List Comprehensions & Advanced Slicing)
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

	# 6. Hybrid Search (Semantic Dense Vectors + AlQalam QalamIndex Lexical Search)
	func hybridSearch(cQuery, nTopK = 3, fAlpha = 0.7)
		if len(aChunks) = 0
			return []
		ok

		# 1. Compute Semantic Vector Scores
		qVec = model.embedding(cQuery)
		aTokens = split(lower(cQuery), " ")

		aScored = []
		for ch in aChunks
			fSemSim = tensor_cosine_similarity(qVec, ch.tEmbedding)

			# 2. Compute Lexical Keyword Overlap
			nMatches = 0
			cChunkLower = lower(ch.cText)
			for tok in aTokens
				tok = trim(tok)
				if len(tok) >= 3 and substr(cChunkLower, tok) > 0
					nMatches++
				ok
			next
			if len(aTokens) > 0
				fLexScore = nMatches / len(aTokens)
			else
				fLexScore = 0.0
			ok

			# 3. Combine scores: fAlpha * Semantic + (1 - fAlpha) * Lexical
			fFinalScore = (fAlpha * fSemSim) + ((1.0 - fAlpha) * fLexScore)
			aScored + [fFinalScore, ch, fSemSim, fLexScore]
		next

		aScored = sort(aScored, 1)
		aReversed = aScored[::-1]

		if len(aReversed) > nTopK
			return aReversed[1:nTopK]
		ok
		return aReversed

	# 7. Binary Persistence: Save vector store directly to disk
	func saveBinary(cFilePath)
		fp = fopen(cFilePath, "wb")
		if !fp
			return false
		ok
		# Header: Magic "MDVR" + version (1)
		fwrite(fp, "MDVR" + char(1) + nl)
		fwrite(fp, "" + len(aChunks) + nl)

		for ch in aChunks
			fwrite(fp, "" + len(ch.cId) + " " + len(ch.cText) + nl)
			fwrite(fp, ch.cId + ch.cText + nl)
			aFloats = tensor_to_list(ch.tEmbedding)
			cLine = ""
			for val in aFloats
				cLine += "" + val + " "
			next
			fwrite(fp, cLine + nl)
		next
		fclose(fp)
		return true

	# 8. Binary Persistence: Load vector store directly from disk
	func loadBinary(cFilePath)
		if !fexists(cFilePath)
			return 0
		ok
		fp = fopen(cFilePath, "r")
		if !fp
			return 0
		ok
		cHeader = fgetc(fp) + fgetc(fp) + fgetc(fp) + fgetc(fp)
		if cHeader != "MDVR"
			fclose(fp)
			return 0
		ok
		cVer = fgetc(fp)
		fgetc(fp) # Skip newline

		# Read chunk count
		cLine = fgets(fp, 64)
		nCount = 0 + trim(cLine)
		aChunks = []

		for i = 1 to nCount
			cMetaLine = fgets(fp, 64)
			aLengths = split(trim(cMetaLine), " ")
			nIdLen = 0 + aLengths[1]
			nTextLen = 0 + aLengths[2]

			# Read text content
			cBoth = fread(fp, nIdLen + nTextLen)
			fgetc(fp) # newline
			cId = left(cBoth, nIdLen)
			cTxt = right(cBoth, nTextLen)

			# Read embedding floats line
			cFloatsLine = fgets(fp, 131072)
			aFloatStrs = split(trim(cFloatsLine), " ")
			aFloats = []
			for s in aFloatStrs
				if s != "" aFloats + (0.0 + s) ok
			next

			tEmb = tensor_from_list(aFloats, "float32")
			aChunks + new DocumentChunk(cId, cTxt, tEmb, [])
		next

		fclose(fp)
		return len(aChunks)

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

	# Answer user question augmented by retrieved context (Leverages QalamInk & f-strings)
	func ask(cQuestion, nTopK = 3, nMaxTokens = 128, bStream = false)
		# 1. Retrieve top matching chunks
		aResults = store.search(cQuestion, nTopK)

		if len(aResults) = 0
			# Fallback to direct model answering if no context stored
			return model.chat(cQuestion, nMaxTokens)
		ok

		# 2. Build Context String using QalamInk for zero-fragmentation
		cContext = ""
		try
			oInk = new QalamInk()
			for res in aResults
				fScore = res[1]
				chunkObj = res[2]
				oInk.inscribe(f"[Document Context (Score: {fScore})]:" + nl + chunkObj.cText + nl + nl)
			next
			cContext = oInk.reveal()
			oInk.wipe()
		catch
			for res in aResults
				fScore = res[1]
				chunkObj = res[2]
				cContext += f"[Document Context (Score: {fScore})]:" + nl + chunkObj.cText + nl + nl
			next
		done

		# 3. Construct Augmented Prompt using QalamInk
		cPrompt = ""
		try
			oInkPrompt = new QalamInk()
			oInkPrompt.inscribe("<|im_start|>system" + nl + cSystemPrompt + nl + nl + "Context Reference:" + nl + cContext + "<|im_end|>" + nl + "<|im_start|>user" + nl + cQuestion + "<|im_end|>" + nl + "<|im_start|>assistant" + nl)
			cPrompt = oInkPrompt.reveal()
			oInkPrompt.wipe()
		catch
			cPrompt = f"<|im_start|>system" + nl +
			          f"{cSystemPrompt}" + nl + nl +
			          f"Context Reference:" + nl +
			          f"{cContext}<|im_end|>" + nl +
			          f"<|im_start|>user" + nl +
			          f"{cQuestion}<|im_end|>" + nl +
			          f"<|im_start|>assistant" + nl
		done

		# 4. Generate Answer
		if bStream
			return model.generateStream(cPrompt, nMaxTokens)
		else
			return model.generate(cPrompt, nMaxTokens)
		ok
