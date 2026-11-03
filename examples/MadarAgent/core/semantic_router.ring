# ====================================================================
#   MadarAgent - Semantic Intent Router (محرك التوجيه الدلالي)
#   تحديد نية المستخدم عبر BGE-M3 وحساب التشابه الدلالي (Cosine Similarity)
#   تخزين مؤقت ثنائي فائق السرعة عبر MadarVectorDB (.vec, .idx, .meta)
# ====================================================================

load "stdlibcore.ring"

class SemanticRouter
	oModel      = NULL
	oRegistry   = NULL
	oStore      = NULL
	cCachePath  = "memory/intent_cache/intent_cache"
	nThreshold  = 0.52
	bVerbose    = false

	func init(oEmbeddingModel, oIntentRegistry, cCacheFile = "memory/intent_cache/intent_cache", nMinScore = 0.52)
		oModel     = ref(oEmbeddingModel)
		oRegistry  = ref(oIntentRegistry)
		nThreshold = nMinScore

		# Normalize cache path (support folder or direct prefix)
		cCache = cCacheFile
		if right(cCache, 4) = ".bin"
			cCache = left(cCache, len(cCache) - 4)
		ok
		if direxists(cCache)
			cCache = cCache + "/intent_cache"
		ok
		cCachePath = cCache

		nDim = 1024
		try
			if isAttribute(oModel, "nDim")
				nDim = oModel.nDim
			ok
		catch
		done

		oStore = new MadarVectorDB(nDim, cCachePath)
		initRouter()
		return self

	func initRouter()
		# Calculate expected trigger count from registry
		nExpected = 0
		for oIt in oRegistry.aIntents
			nExpected += len(oIt.aTriggers)
		next

		# 1. Check if pre-computed binary cache exists (.vec and .idx)
		if fexists(cCachePath + ".vec") and fexists(cCachePath + ".idx")
			nCount = oStore.loadDB(cCachePath)
			if nCount = nExpected and nCount > 0
				if bVerbose
					see f"  [SemanticRouter] Loaded {nCount} intent triggers from '{cCachePath}' (AVX2 Ready)\n"
				ok
				return true
			ok
		ok

		# 2. Re-index from scratch if no cache, corrupted, or seed count changed
		reindex()
		return true

	# Force Re-indexing of all intents and persist to decoupled storage
	func reindex()
		oStore.clear()
		if fexists(cCachePath + ".meta") remove(cCachePath + ".meta") ok
		if fexists(cCachePath + ".vec")  remove(cCachePath + ".vec")  ok
		if fexists(cCachePath + ".idx")  remove(cCachePath + ".idx")  ok

		# Ensure target directory exists
		cDir = JustFilePath(cCachePath)
		if cDir != "" and not direxists(cDir)
			system(f'mkdir \"{cDir}\" >nul 2>&1')
		ok

		nTotal = 0
		for oIntent in oRegistry.aIntents
			for cTrigger in oIntent.aTriggers
				cTrigger = trim(cTrigger)
				if cTrigger != ""
					oVec = oModel.embedding(cTrigger)
					oStore.addDocument(oIntent.cName + "__" + cTrigger, oVec)
					nTotal++
				ok
			next
		next

		# Persist to disk (.vec, .idx, .meta)
		oStore.saveDB(cCachePath)
		if bVerbose
			see f"  [SemanticRouter] Indexed {nTotal} intent triggers and cached to '{cCachePath}' (.vec, .idx, .meta)\n"
		ok
		return nTotal

	# Route user input to best intent
	# Returns: [oIntent, fScore, cTriggerText] or NULL if below threshold
	func route(cQuery)
		if trim(cQuery) = "" or oStore.count() = 0
			return NULL
		ok

		# Search top-1 semantic match via AVX2 cosine similarity
		oQueryVec = oModel.embedding(cQuery)
		aHits = oStore.query(oQueryVec, 1)
		if len(aHits) = 0
			return NULL
		ok

		fScore = aHits[1][:score]

		# Check confidence threshold
		if fScore < nThreshold
			return NULL
		ok

		# Extract Intent Name from text (format: "intent_name__trigger_text")
		cFullText   = aHits[1][:text]
		cIntentName = cFullText
		cTriggerTxt = cFullText
		nPos = substr(cFullText, "__")
		if nPos > 0
			cIntentName = left(cFullText, nPos - 1)
			cTriggerTxt = substr(cFullText, nPos + 2)
		ok

		oIntent = oRegistry.getIntent(cIntentName)
		if oIntent = NULL
			return NULL
		ok

		return [oIntent, fScore, cTriggerTxt]
