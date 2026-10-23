# ====================================================================
# Madar AI - Lightweight Vector Store & RAG Pipeline
# Leverages Madar's native continuous tensors, f-strings, default args,
# list comprehensions, advanced slicing, and AlQalam integration:
#   - QalamReader: Direct PDF text extraction
#   - QalamInk: Zero-fragmentation C++ string accumulation
#   - QalamIndex: High-speed O(1) keyword lookup & Hybrid Search
#   - QalamChronos: Nanosecond-precision benchmarking
# ====================================================================


load "stdlibCore.ring"

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

	# Fast Cohesive Text Chunker using QalamInk
	func chunkText(cContent, nTargetChars = 500, nMinChars = 40)
		aParagraphs = split(cContent, nl + nl)
		aResultChunks = []
		cBuffer = ""

		try
			oInk = new QalamInk()
			for p in aParagraphs
				p = trim(p)
				if len(p) < nMinChars loop ok
				if oInk.size() > 0 and (oInk.size() + len(p)) > nTargetChars
					aResultChunks + oInk.reveal()
					oInk.wipe()
				ok
				if oInk.size() > 0
					oInk.inscribe(nl + nl)
				ok
				oInk.inscribe(p)
			next
			if oInk.size() >= nMinChars
				aResultChunks + oInk.reveal()
			ok
			oInk.wipe()
		catch
			# Fallback if AlQalam is not loaded
			for p in aParagraphs
				p = trim(p)
				if len(p) < nMinChars loop ok
				if len(cBuffer) > 0 and (len(cBuffer) + len(p)) > nTargetChars
					aResultChunks + cBuffer
					cBuffer = ""
				ok
				if len(cBuffer) > 0
					cBuffer += nl + nl
				ok
				cBuffer += p
			next
			if len(cBuffer) >= nMinChars
				aResultChunks + cBuffer
			ok
		done
		return aResultChunks

	# 3. Add text file and split into cohesive paragraph chunks
	func addFile(cFilePath, nMinChars = 40)
		if not fexists(cFilePath)
			raise(f"File not found: {cFilePath}")
		ok
		cContent = read(cFilePath)
		aValidParagraphs = chunkText(cContent, 500, nMinChars)
		cFileName = JustFileName(cFilePath)

		nCount = 0
		for p in aValidParagraphs
			addText(p, f"{cFileName}_p{nCount + 1}", ["source" = cFilePath])
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
			oReader = new QalamReader()
			cContent = oReader.extractPDFText(cFilePath)
		catch
			see f"  [Warning] QalamReader unavailable, fallback to direct read: {cFilePath}" + nl
			cContent = read(cFilePath)
		done

		if cContent = "" or trim(cContent) = ""
			return 0
		ok

		aValid = chunkText(cContent, 500, nMinChars)
		cFileName = JustFileName(cFilePath)

		nCount = 0
		for p in aValid
			addText(p, f"{cFileName}_p{nCount + 1}", ["source" = cFilePath, "type" = "pdf"])
			nCount++
		next
		return nCount

	# Fast Markdown-Aware Chunker splitting by #, ##, ### Headings
	func chunkMarkdown(cContent, cDocTitle = "", nMaxSectionChars = 800, nMinChars = 30)
		aLines = split(cContent, nl)
		aResultChunks = []
		cCurrentHeader = cDocTitle

		try
			oInk = new QalamInk()
			for line in aLines
				sLine = trim(line)
				bIsHeader = false
				if len(sLine) >= 2
					if left(sLine, 2) = "# "
						bIsHeader = true
					elseif len(sLine) >= 3 and left(sLine, 3) = "## "
						bIsHeader = true
					elseif len(sLine) >= 4 and left(sLine, 4) = "### "
						bIsHeader = true
					elseif len(sLine) >= 5 and left(sLine, 5) = "#### "
						bIsHeader = true
					ok
				ok

				if bIsHeader
					if oInk.size() >= nMinChars
						aResultChunks + oInk.reveal()
						oInk.wipe()
					ok
					cCurrentHeader = sLine
					if cDocTitle != "" and cDocTitle != sLine
						oInk.inscribe("[" + cDocTitle + " > " + sLine + "]" + nl + nl)
					else
						oInk.inscribe(sLine + nl + nl)
					ok
				else
					if oInk.size() > nMaxSectionChars and sLine = ""
						if oInk.size() >= nMinChars
							aResultChunks + oInk.reveal()
							oInk.wipe()
							if cCurrentHeader != ""
								oInk.inscribe(cCurrentHeader + " (cont.)" + nl + nl)
							ok
						ok
					else
						oInk.inscribe(line + nl)
					ok
				ok
			next

			if oInk.size() >= nMinChars
				aResultChunks + oInk.reveal()
			ok
			oInk.wipe()
		catch
			cBuffer = ""
			for line in aLines
				sLine = trim(line)
				bIsHeader = false
				if len(sLine) >= 2
					if left(sLine, 2) = "# " or (len(sLine) >= 3 and left(sLine, 3) = "## ") or (len(sLine) >= 4 and left(sLine, 4) = "### ")
						bIsHeader = true
					ok
				ok

				if bIsHeader
					if len(trim(cBuffer)) >= nMinChars
						aResultChunks + cBuffer
						cBuffer = ""
					ok
					cCurrentHeader = sLine
					if cDocTitle != "" and cDocTitle != sLine
						cBuffer = "[" + cDocTitle + " > " + sLine + "]" + nl + nl
					else
						cBuffer = sLine + nl + nl
					ok
				else
					if len(cBuffer) > nMaxSectionChars and sLine = ""
						if len(trim(cBuffer)) >= nMinChars
							aResultChunks + cBuffer
							cBuffer = cCurrentHeader + " (cont.)" + nl + nl
						ok
					else
						cBuffer += line + nl
					ok
				ok
			next

			if len(trim(cBuffer)) >= nMinChars
				aResultChunks + cBuffer
			ok
		done

		return aResultChunks

	# 4. Add Markdown file with heading-aware chunking
	func addMarkdown(cFilePath, nMinChars = 30)
		if not fexists(cFilePath)
			raise(f"Markdown file not found: {cFilePath}")
		ok
		cContent = read(cFilePath)
		cDocName = JustFileName(cFilePath)

		aChunksList = chunkMarkdown(cContent, cDocName, 800, nMinChars)

		nCount = 0
		for ch in aChunksList
			addText(trim(ch), f"{cDocName}_h{nCount + 1}", ["source" = cFilePath, "type" = "markdown"])
			nCount++
		next
		return nCount

	# 5. Add single document (auto-routes .pdf to addPDF, .md to addMarkdown, others to addFile)
	func addDocument(cFilePath, nMinChars = 40)
		if not fexists(cFilePath)
			raise(f"Document file not found: {cFilePath}")
		ok
		cExt = lower(JustFileExt(cFilePath))
		if cExt = "pdf"
			return addPDF(cFilePath, nMinChars)
		elseif cExt = "md" or cExt = "markdown"
			return addMarkdown(cFilePath, nMinChars)
		else
			return addFile(cFilePath, nMinChars)
		ok

	# 6. Add directory of documents recursively (.md, .txt, .pdf, .ring, etc.)
	func addDirectory(cDirPath, aExts = ["md", "txt", "pdf", "ring", "rh"], nMinChars = 40, pCallback = NULL)
		if not direxists(cDirPath)
			raise(f"Directory not found: {cDirPath}")
		ok

		aAllFiles = ListAllFiles(cDirPath, NULL)
		nTotalAdded = 0
		nFilesProcessed = 0
		aProcessedFiles = []

		for cFile in aAllFiles
			cExt = lower(JustFileExt(cFile))
			if cExt != "" and find(aExts, cExt) > 0
				nChunks = addDocument(cFile, nMinChars)
				if nChunks > 0
					nTotalAdded += nChunks
					nFilesProcessed++
					aProcessedFiles + [cFile, nChunks]
					if pCallback != NULL
						call pCallback(cFile, nChunks)
					ok
				ok
			ok
		next

		return [nTotalAdded, nFilesProcessed, aProcessedFiles]

	# 5. High-Precision Hybrid Semantic & Lexical Search (Production RAG Engine)
	func search(cQuery, nTopK = 3, fMinScore = 0.0)
		return hybridSearch(cQuery, nTopK, 0.50)

	# 6. Hybrid Search: Dense Vector Semantic Similarity + Calibrated Lexical Overlap
	func hybridSearch(cQuery, nTopK = 3, fAlpha = 0.50)
		if len(aChunks) = 0
			return []
		ok

		# 1. Compute Semantic Vector Query
		qVec = model.embedding(cQuery)

		# 2. Extract Meaningful Keywords (Exclude Arabic & English Stopwords)
		aStopwords = [
			"ما", "هو", "هي", "ماهو", "ماهي", "ماذا", "هل", "من", "في", "على", 
			"إلى", "الي", "عن", "مع", "هذا", "هذه", "تلك", "ذلك", "كان", "أن", 
			"ان", "أو", "او", "ثم", "كيف", "اين", "أين", "متى", "كم", "لماذا",
			"the", "is", "at", "which", "on", "a", "an", "and", "or", "what", "how", "who", "where"
		]

		cCleanQuery = lower(trim(cQuery))
		cCleanQuery = substr(cCleanQuery, "؟", "")
		cCleanQuery = substr(cCleanQuery, "?", "")
		cCleanQuery = substr(cCleanQuery, ".", "")
		cCleanQuery = substr(cCleanQuery, ",", "")
		cCleanQuery = substr(cCleanQuery, "،", "")
		cCleanQuery = substr(cCleanQuery, ":", "")

		aRawTokens = split(cCleanQuery, " ")
		aKeywords = []
		for tok in aRawTokens
			tok = trim(tok)
			if len(tok) >= 2 and find(aStopwords, tok) = 0
				aKeywords + tok
			ok
		next

		nKeyCount = len(aKeywords)
		aScored = []

		for ch in aChunks
			# Raw cosine similarity from causal LLM hidden states (anisotropic base ~0.70)
			fRawSim = tensor_cosine_similarity(qVec, ch.tEmbedding)

			# Rescale semantic similarity from [0.70, 1.00] baseline to [0.0, 1.0] dynamic range
			fNormSem = (fRawSim - 0.70) / 0.30
			if fNormSem < 0.0 fNormSem = 0.0 ok
			if fNormSem > 1.0 fNormSem = 1.0 ok

			# Lexical Keyword Matching
			nMatches = 0.0
			cChunkLower = lower(ch.cText + " " + ch.cId)
			if nKeyCount > 0
				for kw in aKeywords
					# Direct substring match
					if substr(cChunkLower, kw) > 0
						nMatches += 1.0
					elseif len(kw) >= 4 and substr(cChunkLower, left(kw, len(kw) - 1)) > 0
						# Stem prefix match (e.g. هاتفي -> هاتف, منصة -> منص)
						nMatches += 0.85
					elseif len(kw) >= 5 and substr(cChunkLower, left(kw, len(kw) - 2)) > 0
						nMatches += 0.60
					ok
				next
				fLexScore = nMatches / nKeyCount
				if fLexScore > 1.0 fLexScore = 1.0 ok
			else
				fLexScore = 0.0
			ok

			# Calibrated Hybrid Score
			if nKeyCount > 0
				fFinalScore = (fAlpha * fNormSem) + ((1.0 - fAlpha) * fLexScore)
			else
				fFinalScore = fNormSem
			ok

			aScored + [fFinalScore, ch, fRawSim, fLexScore]
		next

		# Sort in descending order
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
		# Header: Magic "MDVR" + version (2)
		fwrite(fp, "MDVR" + char(2) + nl)
		fwrite(fp, "" + len(aChunks) + nl)

		nOldDec = 7
		decimals(nOldDec)
		for ch in aChunks
			cId = ch.cId
			cText = ch.cText
			aFloats = tensor_to_list(ch.tEmbedding)
			fwrite(fp, "" + len(cId) + " " + len(cText) + " " + len(aFloats) + nl)
			fwrite(fp, cId + nl)
			fwrite(fp, cText + nl)
			cLine = ""
			for val in aFloats
				cLine += "" + val + " "
			next
			fwrite(fp, cLine + nl)
		next
		decimals(2)
		fclose(fp)
		return true

	# 8. Binary Persistence: Load vector store directly from disk
	func loadBinary(cFilePath)
		if !fexists(cFilePath)
			return 0
		ok
		fp = fopen(cFilePath, "rb")
		if !fp
			return 0
		ok
		cHeader = fgetc(fp) + fgetc(fp) + fgetc(fp) + fgetc(fp)
		if cHeader != "MDVR"
			fclose(fp)
			return 0
		ok
		nVer = ascii(fgetc(fp))
		# Read past rest of header line
		while true
			c = fgetc(fp)
			if c = char(10) or c = NULL exit ok
		end

		# Read chunk count line
		cLine = ""
		while true
			c = fgetc(fp)
			if c = char(10) or c = NULL exit ok
			if c != char(13) cLine += c ok
		end
		nCount = 0 + trim(cLine)
		aChunks = []

		if nVer = 2
			for i = 1 to nCount
				cMetaLine = ""
				while true
					c = fgetc(fp)
					if c = char(10) or c = NULL exit ok
					if c != char(13) cMetaLine += c ok
				end
				aMetaParts = split(trim(cMetaLine), " ")
				if len(aMetaParts) < 2 loop ok
				nIdLen = 0 + aMetaParts[1]
				nTextLen = 0 + aMetaParts[2]

				cId = fread(fp, nIdLen)
				cNext = fgetc(fp)
				if cNext = char(13) cNext = fgetc(fp) ok

				cTxt = fread(fp, nTextLen)
				cNext = fgetc(fp)
				if cNext = char(13) cNext = fgetc(fp) ok

				cFloatsLine = ""
				while true
					c = fgetc(fp)
					if c = char(10) or c = NULL exit ok
					if c != char(13) cFloatsLine += c ok
				end
				aFloatStrs = split(trim(cFloatsLine), " ")
				aFloats = []
				for s in aFloatStrs
					if s != "" aFloats + (0.0 + s) ok
				next

				tEmb = tensor_from_list(aFloats, "float32")
				aChunks + new DocumentChunk(cId, cTxt, tEmb, [])
			next
		else
			# Version 1 compatibility fallback
			for i = 1 to nCount
				cMetaLine = ""
				while true
					c = fgetc(fp)
					if c = char(10) or c = NULL exit ok
					if c != char(13) cMetaLine += c ok
				end
				aLengths = split(trim(cMetaLine), " ")
				nIdLen = 0 + aLengths[1]
				nTextLen = 0 + aLengths[2]

				cBoth = fread(fp, nIdLen + nTextLen)
				cNext = fgetc(fp)
				if cNext = char(13) cNext = fgetc(fp) ok
				cId = left(cBoth, nIdLen)
				cTxt = right(cBoth, nTextLen)

				cFloatsLine = ""
				while true
					c = fgetc(fp)
					if c = char(10) or c = NULL exit ok
					if c != char(13) cFloatsLine += c ok
				end
				aFloatStrs = split(trim(cFloatsLine), " ")
				aFloats = []
				for s in aFloatStrs
					if s != "" aFloats + (0.0 + s) ok
				next

				tEmb = tensor_from_list(aFloats, "float32")
				aChunks + new DocumentChunk(cId, cTxt, tEmb, [])
			next
		ok

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
