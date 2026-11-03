# ====================================================================
# Madar AI - High-Performance Decoupled Vector Database (MadarVectorDB)
# Architecture:
#   1. <path>.vec  : Direct binary float32 tensor buffer (Contiguous Memory)
#   2. <path>.idx  : Binary integer offset table (O(1) random disk seeks)
#   3. <path>.meta : Append-only text storage (Zero RAM text footprint)
# ====================================================================

load "stdlibcore.ring"

class MadarVectorDB

    nDim          = 768
    cDBPath       = "data/memory/vector_store"
    nCount        = 0
    
    # In-Memory Storage:
    # ONLY dense mathematical tensors and byte offsets live in RAM.
    # Text strings remain 100% on disk.
    aVectors      = []  # List of 1D RingTensors (or contiguous matrix view)
    aOffsets      = []  # List of integer byte offsets pointing into .meta file
    
    # Staging Buffer for atomic commits / working memory
    aStagingArea  = []  # [ [:text=..., :vector=..., :meta=...] ]

    func init(nEmbeddingDim = 768, cPath = "data/memory/vector_store")
        nDim    = nEmbeddingDim
        cDBPath = cPath
        aVectors = []
        aOffsets = []
        aStagingArea = []
        nCount = 0
        return self

    # ----------------------------------------------------------------
    # Staging Area Protocol (Working Memory before disk commit)
    # ----------------------------------------------------------------
    func stageDocument(cText, oVector, aMeta = [])
        if cText = "" or isNull(oVector)
            return 0
        ok
        aStagingArea + [
            :text   = cText,
            :vector = oVector,
            :meta   = aMeta
        ]
        return len(aStagingArea)

    func commitStage(nStageIdx)
        if nStageIdx < 1 or nStageIdx > len(aStagingArea)
            raise("MadarVectorDB: Invalid staging index")
        ok
        oItem = aStagingArea[nStageIdx]
        addDocument(oItem[:text], oItem[:vector])
        del(aStagingArea, nStageIdx)
        return true

    func commitAll()
        nTotal = len(aStagingArea)
        for i = 1 to nTotal
            oItem = aStagingArea[1]
            addDocument(oItem[:text], oItem[:vector])
            del(aStagingArea, 1)
        next
        return nTotal

    # ----------------------------------------------------------------
    # Ingestion: Adds document vector to RAM, text to .meta on disk
    # ----------------------------------------------------------------
    func addDocument(cText, oVector)
        if cText = "" or isNull(oVector)
            return false
        ok

        # Ensure directory exists
        cDir = JustFilePath(cDBPath)
        if cDir != "" and !direxists(cDir)
            # Create directory if needed
        ok

        cMetaPath = cDBPath + ".meta"
        cCleanText = substr(cText, nl, " ")
        cCleanText = substr(cCleanText, char(13), "")

        # 1. Append text to .meta and record the byte offset
        fp = fopen(cMetaPath, "ab")
        if fp = NULL
            raise(f"MadarVectorDB: Cannot open metadata file '{cMetaPath}' for writing")
        ok
        fseek(fp, 0, 2) # Seek to end
        nBytePos = ftell(fp)
        fputs(fp, cCleanText + nl)
        fclose(fp)

        # 2. Store offset and vector in RAM
        aOffsets + nBytePos
        aVectors + oVector
        nCount++

        return nCount

    # ----------------------------------------------------------------
    # Search: Fast AVX2 Cosine Similarity -> Top-K Disk Fetch
    # ----------------------------------------------------------------
    func query(oQueryVec, nTopK = 3, fMinScore = 0.0)
        if nCount = 0
            return []
        ok

        # 1. Cosine similarity scoring over dense in-memory vectors
        aScored = []
        for i = 1 to nCount
            oDocVec = aVectors[i]
            fSim = tensor_cosine_similarity(oQueryVec, oDocVec)
            if fSim >= fMinScore
                aScored + [fSim, i]
            ok
        next

        if len(aScored) = 0
            return []
        ok

        # 2. Sort descending by similarity score
        aScored = sort(aScored, 1)
        aRanked = aScored[::-1] # Madar native slice reversal

        nLimit = min(nTopK, len(aRanked))

        # 3. Precision Disk Fetch: Read ONLY the Top-K texts from .meta
        cMetaPath = cDBPath + ".meta"
        fp = fopen(cMetaPath, "rb")
        if fp = NULL
            raise(f"MadarVectorDB: Cannot open metadata file '{cMetaPath}' for reading")
        ok

        aFinal = []
        for k = 1 to nLimit
            fScore = aRanked[k][1]
            nIdx   = aRanked[k][2]
            nOffset = aOffsets[nIdx]

            # Direct jump to target document byte position
            fseek(fp, nOffset, 0)
            cLine = fgets(fp, 65536)
            cLine = substr(cLine, char(13), "")
            cLine = substr(cLine, char(10), "")
            cText = trim(cLine)

            aFinal + [
                :id     = nIdx,
                :score  = fScore,
                :text   = cText,
                :offset = nOffset
            ]
        next

        fclose(fp)
        return aFinal

    # ----------------------------------------------------------------
    # Fetch a single document by index directly from disk
    # ----------------------------------------------------------------
    func fetchText(nIdx)
        if nIdx < 1 or nIdx > len(aOffsets)
            return ""
        ok
        cMetaPath = cDBPath + ".meta"
        if !fexists(cMetaPath)
            return ""
        ok
        fp = fopen(cMetaPath, "rb")
        if fp = NULL return "" ok

        nOffset = aOffsets[nIdx]
        fseek(fp, nOffset, 0)
        cLine = fgets(fp, 65536)
        fclose(fp)
        cLine = substr(cLine, char(13), "")
        cLine = substr(cLine, char(10), "")
        return trim(cLine)

    # ----------------------------------------------------------------
    # Binary Persistence: Saves .vec (Raw Floats) and .idx (Binary Offsets)
    # ----------------------------------------------------------------
    func saveDB(cPath = "")
        if cPath != ""
            cDBPath = cPath
        ok
        if nCount = 0
            return false
        ok

        # 1. Save .vec file: Magic 'MDVC' + nDim(4B) + nCount(4B) + raw float data
        cVecPath = cDBPath + ".vec"
        fpVec = fopen(cVecPath, "wb")
        if fpVec = NULL
            raise(f"MadarVectorDB: Cannot open '{cVecPath}' for writing")
        ok
        fwrite(fpVec, "MDVC")
        fwrite(fpVec, Int2Bytes(nDim))
        fwrite(fpVec, Int2Bytes(nCount))

        for i = 1 to nCount
            oVec = aVectors[i]
            aFloats = tensor_to_list(oVec)
            cBuffer = ""
            for f in aFloats
                cBuffer += Float2Bytes(f)
            next
            fwrite(fpVec, cBuffer)
        next
        fclose(fpVec)

        # 2. Save .idx file: Magic 'MDID' + nCount(4B) + uint32/double offsets
        cIdxPath = cDBPath + ".idx"
        fpIdx = fopen(cIdxPath, "wb")
        if fpIdx = NULL
            raise(f"MadarVectorDB: Cannot open '{cIdxPath}' for writing")
        ok
        fwrite(fpIdx, "MDID")
        fwrite(fpIdx, Int2Bytes(nCount))

        cIdxBuf = ""
        for nPos in aOffsets
            cIdxBuf += Double2Bytes(nPos)
        next
        fwrite(fpIdx, cIdxBuf)
        fclose(fpIdx)

        return true

    # ----------------------------------------------------------------
    # Binary Persistence: Loads .vec and .idx instantly from disk
    # ----------------------------------------------------------------
    func loadDB(cPath = "")
        if cPath != ""
            cDBPath = cPath
        ok
        cVecPath = cDBPath + ".vec"
        cIdxPath = cDBPath + ".idx"

        if !fexists(cVecPath) or !fexists(cIdxPath)
            return false
        ok

        # 1. Load .idx binary file (Offsets)
        fpIdx = fopen(cIdxPath, "rb")
        if fpIdx = NULL return false ok

        cMagic = fread(fpIdx, 4)
        if cMagic != "MDID"
            fclose(fpIdx)
            return false
        ok
        nTotalDocs = Bytes2Int(fread(fpIdx, 4))
        aOffsets = []
        for i = 1 to nTotalDocs
            cBytes = fread(fpIdx, 8) # 8 bytes for Double2Bytes
            aOffsets + Bytes2Double(cBytes)
        next
        fclose(fpIdx)

        # 2. Load .vec binary file (Vectors)
        fpVec = fopen(cVecPath, "rb")
        if fpVec = NULL return false ok

        cMagic = fread(fpVec, 4)
        if cMagic != "MDVC"
            fclose(fpVec)
            return false
        ok
        nLoadedDim   = Bytes2Int(fread(fpVec, 4))
        nLoadedCount = Bytes2Int(fread(fpVec, 4))

        nDim = nLoadedDim
        nCount = nLoadedCount
        aVectors = []

        nVecBytes = nDim * 4 # 4 bytes per float32
        for i = 1 to nCount
            cBuf = fread(fpVec, nVecBytes)
            aFloats = []
            for j = 1 to nDim
                cSub = substr(cBuf, (j - 1) * 4 + 1, 4)
                aFloats + Bytes2Float(cSub)
            next
            oTensor = tensor_from_list(aFloats, "float32")
            aVectors + oTensor
        next
        fclose(fpVec)

        return nCount

    func count()
        return nCount

    func clear()
        aVectors = []
        aOffsets = []
        aStagingArea = []
        nCount = 0

