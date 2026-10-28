# ====================================================================
#   MadarAgent - Semantic Intent Router (محرك التوجيه الدلالي)
#   تحديد نية المستخدم عبر BGE-M3 وحساب التشابه الدلالي (Cosine Similarity)
#   يدعم التخزين المؤقت في ملف ثنائي (.bin) لتجنب إعادة الحساب عند الإقلاع
# ====================================================================



class SemanticRouter
	oModel      = NULL
	oRegistry   = NULL
	oStore      = NULL
	cCachePath  = "memory/intent_cache.bin"
	nThreshold  = 0.52
	bVerbose    = false

	func init(oEmbeddingModel, oIntentRegistry, cCacheFile = "memory/intent_cache.bin", nMinScore = 0.52)
		oModel     = oEmbeddingModel
		oRegistry  = oIntentRegistry
		cCachePath = cCacheFile
		nThreshold = nMinScore
		oStore     = new VectorStore(oModel)

		initRouter()
		return self

	func initRouter()
		# Calculate expected trigger count from registry
		nExpected = 0
		for oIt in oRegistry.aIntents
			nExpected += len(oIt.aTriggers)
		next

		# 1. Check if pre-computed binary cache exists and matches current seeds
		if fexists(cCachePath)
			nCount = oStore.loadBinary(cCachePath)
			if nCount = nExpected and nCount > 0
				if bVerbose
					see f"  [SemanticRouter] Loaded {nCount} intent triggers from cache '{cCachePath}'\n"
				ok
				return true
			ok
		ok

		# 2. Re-index from scratch if no cache, corrupted, or seed count changed
		reindex()
		return true

	# Force Re-indexing of all intents and persist to binary file
	func reindex()
		oStore.aChunks = []
		nTotal = 0

		for oIntent in oRegistry.aIntents
			nIdx = 1
			for cTrigger in oIntent.aTriggers
				cId = oIntent.cName + "__" + nIdx
				# Add trigger phrase with embedding
				oStore.addText(cTrigger, cId, ["intent" = oIntent.cName])
				nTotal++
				nIdx++
			next
		next

		# Persist to disk
		oStore.saveBinary(cCachePath)
		if bVerbose
			see f"  [SemanticRouter] Indexed {nTotal} intent triggers and cached to '{cCachePath}'\n"
		ok
		return nTotal

	# Route user input to best intent
	# Returns: [oIntent, fScore, cTriggerText] or NULL if below threshold
	func route(cQuery)
		if trim(cQuery) = "" or len(oStore.aChunks) = 0
			return NULL
		ok

		# Search top-1 semantic match (alpha = 0.70 dense semantic bias)
		aHits = oStore.hybridSearch(cQuery, 1, 0.70)
		if len(aHits) = 0
			return NULL
		ok

		fScore = aHits[1][1]
		oChunk = aHits[1][2]

		# Check confidence threshold
		if fScore < nThreshold
			return NULL
		ok

		# Extract Intent Name from Chunk ID (e.g. "ring_coding__2" -> "ring_coding")
		cChunkId = oChunk.cId
		cIntentName = cChunkId
		nPos = substr(cChunkId, "__")
		if nPos > 0
			cIntentName = left(cChunkId, nPos - 1)
		ok

		oIntent = oRegistry.getIntent(cIntentName)
		if oIntent = NULL
			return NULL
		ok

		return [oIntent, fScore, oChunk.cText]
