# ====================================================================
#   MadarAgent - Decoupled Two-Tier Memory Architecture
#   نظام الذاكرة المعمارية ثنائية الطبقات (قاعدة معرفية أساسية + ذاكرة تشغيلية)
#   تخزين متجهي منفصل (Zero RAM Text Footprint) + تقطيع متداخل (Overlap)
# ====================================================================

load "stdlibcore.ring"

class TwoTierMemory
	oModel
	oBaseKB                 # Tier 1: Fixed Long-Term Knowledge (e.g. Ring Language Manual)
	oWorkingKB              # Tier 2: Dynamic Working Memory (User facts, learned files)
	oChunker                # Semantic & Overlapping Chunker
	cBaseKbPath      = ""
	cWorkingKbPath   = ""

	func init(oEmbeddingModel, cBasePath = "memory/ring_kb/ring_kb", cWorkingPath = "memory/user_memory/user_memory")
		oModel = ref(oEmbeddingModel)

		# Normalize path extensions (strip legacy .bin)
		if right(cBasePath, 4) = ".bin"
			cBasePath = left(cBasePath, len(cBasePath) - 4)
		ok
		if right(cWorkingPath, 4) = ".bin"
			cWorkingPath = left(cWorkingPath, len(cWorkingPath) - 4)
		ok

		# Support directory paths
		if direxists(cBasePath)
			cBasePath = cBasePath + "/ring_kb"
		ok
		if direxists(cWorkingPath)
			cWorkingPath = cWorkingPath + "/user_memory"
		ok

		cBaseKbPath = cBasePath
		cWorkingKbPath = cWorkingPath

		nDim = 1024
		try
			if isAttribute(oModel, "nDim")
				nDim = oModel.nDim
			ok
		catch
		done

		oBaseKB    = new MadarVectorDB(nDim, cBaseKbPath)
		oWorkingKB = new MadarVectorDB(nDim, cWorkingKbPath)
		oChunker   = new MadarChunker(150, 30) # 150 words per chunk, 30 words overlap

		loadBases()
		return self

	func loadBases()
		# Ensure memory directory exists
		if not direxists("memory")
			system("mkdir memory >nul 2>&1")
		ok

		# Load Tier 1 (Base KB) if exists (.vec + .idx)
		if fexists(cBaseKbPath + ".vec") and fexists(cBaseKbPath + ".idx")
			nCount = oBaseKB.loadDB(cBaseKbPath)
			see f"  [Memory Tier 1] Loaded {nCount} chunks from Base KB ({cBaseKbPath}) [Zero RAM Text]" + nl
		else
			see f"  [Memory Tier 1] Base KB not found at ({cBaseKbPath}). Ready for generation." + nl
		ok

		# Load Tier 2 (Working KB) if exists (.vec + .idx)
		if fexists(cWorkingKbPath + ".vec") and fexists(cWorkingKbPath + ".idx")
			nCount = oWorkingKB.loadDB(cWorkingKbPath)
			see f"  [Memory Tier 2] Loaded {nCount} user memories from ({cWorkingKbPath})" + nl
		ok

	func rememberFact(cFact, cCategory = "user_fact")
		if trim(cFact) = "" return false ok
		oVec = oModel.embedding(cFact)
		oWorkingKB.addDocument(cFact, oVec)
		saveWorking()
		return true

	async func rememberFactAsync(cFact, cCategory = "user_fact")
		return await rememberFact(cFact, cCategory)

	func learnFile(cFilePath)
		if not fexists(cFilePath) return 0 ok
		cContent = read(cFilePath)
		cExt = lower(JustFileExt(cFilePath))

		aChunks = []
		if cExt = "md" or cExt = "markdown"
			aChunks = oChunker.chunkMarkdown(cContent, JustFileName(cFilePath))
		else
			aChunks = oChunker.chunkText(cContent)
		ok

		nCount = 0
		for ch in aChunks
			oVec = oModel.embedding(ch)
			oWorkingKB.addDocument(ch, oVec)
			nCount++
		next

		saveWorking()
		return nCount

	async func learnFileAsync(cFilePath)
		return await learnFile(cFilePath)

	func saveWorking()
		if oWorkingKB.count() > 0
			oWorkingKB.saveDB(cWorkingKbPath)
			return true
		ok
		return false

	func clearWorking()
		oWorkingKB.clear()
		if fexists(cWorkingKbPath + ".vec")  remove(cWorkingKbPath + ".vec")  ok
		if fexists(cWorkingKbPath + ".idx")  remove(cWorkingKbPath + ".idx")  ok
		if fexists(cWorkingKbPath + ".meta") remove(cWorkingKbPath + ".meta") ok
		return true

	func commitWorkingToBase()
		nMoved = 0
		for i = 1 to oWorkingKB.count()
			cText = oWorkingKB.fetchText(i)
			oVec  = oWorkingKB.aVectors[i]
			oBaseKB.addDocument(cText, oVec)
			nMoved++
		next
		oBaseKB.saveDB(cBaseKbPath)
		clearWorking()
		return nMoved

	func search(cQuery, nTopK = 3)
		aCombined = []
		oQueryVec = oModel.embedding(cQuery)

		# 1. Search Working Memory first (Tier 2 - high temporal relevance)
		if oWorkingKB.count() > 0
			aWorkResults = oWorkingKB.query(oQueryVec, nTopK)
			for res in aWorkResults
				# res is [:id=..., :score=..., :text=..., :offset=...]
				aCombined + [res[:score], "[Working Memory] " + res[:text], res[:text]]
			next
		ok

		# 2. Search Base KB (Tier 1 - foundation knowledge)
		if oBaseKB.count() > 0
			aBaseResults = oBaseKB.query(oQueryVec, nTopK)
			for res in aBaseResults
				aCombined + [res[:score], "[Knowledge Base] " + res[:text], res[:text]]
			next
		ok

		if len(aCombined) = 0 return [] ok

		# Sort combined results by score descending
		aCombined = sort(aCombined, 1)
		aReversed = aCombined[::-1]

		if len(aReversed) > nTopK
			return aReversed[1:nTopK]
		ok
		return aReversed

	async func searchAsync(cQuery, nTopK = 3)
		return await search(cQuery, nTopK)

	func getStats()
		nBaseCount = oBaseKB.count()
		nWorkCount = oWorkingKB.count()
		return [
			"base_chunks" = nBaseCount,
			"working_chunks" = nWorkCount,
			"base_path" = cBaseKbPath,
			"working_path" = cWorkingKbPath
		]
