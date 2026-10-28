# ====================================================================
#   MadarAgent - Two-Tier Memory Architecture
#   نظام الذاكرة المعمارية ثنائية الطبقات (قاعدة معرفية أساسية + ذاكرة تشغيلية)
# ====================================================================

class TwoTierMemory
	oModel           = NULL
	oBaseKB          = NULL      # Tier 1: Fixed Long-Term Knowledge (e.g. Ring Language Manual)
	oWorkingKB       = NULL      # Tier 2: Dynamic Working Memory (User facts, learned files)
	cBaseKbPath      = ""
	cWorkingKbPath   = ""

	func init(oEmbeddingModel, cBasePath = "memory/ring_kb.bin", cWorkingPath = "memory/user_memory.bin")
		oModel = oEmbeddingModel
		cBaseKbPath = cBasePath
		cWorkingKbPath = cWorkingPath

		oBaseKB = new VectorStore(oModel)
		oWorkingKB = new VectorStore(oModel)

		loadBases()
		return self

	func loadBases()
		# Ensure memory directory exists
		if not direxists("memory")
			system("mkdir memory >nul 2>&1")
		ok

		# Load Tier 1 (Base KB) if exists
		if fexists(cBaseKbPath)
			nCount = oBaseKB.loadBinary(cBaseKbPath)
			see f"  [Memory Tier 1] Loaded {nCount} chunks from Base KB ({cBaseKbPath})" + nl
		else
			see f"  [Memory Tier 1] Base KB not found at ({cBaseKbPath}). Ready for manual placement." + nl
		ok

		# Load Tier 2 (Working KB) if exists
		if fexists(cWorkingKbPath)
			nCount = oWorkingKB.loadBinary(cWorkingKbPath)
			see f"  [Memory Tier 2] Loaded {nCount} user memories from ({cWorkingKbPath})" + nl
		ok

	func rememberFact(cFact, cCategory = "user_fact")
		if trim(cFact) = "" return false ok
		cId = f"fact_{len(oWorkingKB.aChunks) + 1}"
		oChunk = oWorkingKB.addText(cFact, cId, ["category" = cCategory, "time" = time(), "date" = date()])
		saveWorking()
		return (oChunk != NULL)

	func learnFile(cFilePath)
		if not fexists(cFilePath) return 0 ok
		nCount = oWorkingKB.addFile(cFilePath, 40)
		saveWorking()
		return nCount

	func saveWorking()
		if len(oWorkingKB.aChunks) > 0
			oWorkingKB.saveBinary(cWorkingKbPath)
			return true
		ok
		return false

	func clearWorking()
		oWorkingKB.aChunks = []
		if fexists(cWorkingKbPath)
			remove(cWorkingKbPath)
		ok
		return true

	func commitWorkingToBase()
		nMoved = 0
		for ch in oWorkingKB.aChunks
			oBaseKB.aChunks + ch
			nMoved++
		next
		oBaseKB.saveBinary(cBaseKbPath)
		clearWorking()
		return nMoved

	func search(cQuery, nTopK = 3)
		aCombined = []

		# 1. Search Working Memory first (Tier 2 - high temporal relevance)
		if len(oWorkingKB.aChunks) > 0
			aWorkResults = oWorkingKB.hybridSearch(cQuery, nTopK, 0.40)
			for res in aWorkResults
				cTxt = ""
				if isobject(res[2]) cTxt = res[2].cText else cTxt = "" + res[2] ok
				aCombined + [res[1], "[Working Memory] " + cTxt, res[2]]
			next
		ok

		# 2. Search Base KB (Tier 1 - foundation knowledge)
		if len(oBaseKB.aChunks) > 0
			aBaseResults = oBaseKB.hybridSearch(cQuery, nTopK, 0.50)
			for res in aBaseResults
				cTxt = ""
				if isobject(res[2]) cTxt = res[2].cText else cTxt = "" + res[2] ok
				aCombined + [res[1], "[Knowledge Base] " + cTxt, res[2]]
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

	func getStats()
		nBaseCount = len(oBaseKB.aChunks)
		nWorkCount = len(oWorkingKB.aChunks)
		return [
			"base_chunks" = nBaseCount,
			"working_chunks" = nWorkCount,
			"base_path" = cBaseKbPath,
			"working_path" = cWorkingKbPath
		]
