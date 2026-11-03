# ====================================================================
# Madar AI - Advanced RAG Pipeline (MadarRAG)
# Combines:
#   1. MadarVectorDB      : Decoupled zero-RAM text vector storage
#   2. MadarChunker       : Overlapping semantic sliding window
#   3. MadarContextManager: Dynamic token budgeting & Lost-in-the-Middle mitigation
#   4. Hybrid Search      : Dense Semantic (AVX2) + Lexical Overlap (RRF)
# ====================================================================

class MadarRAG

    oEmbedder        = NULL  # Embedding model (BGE, BERT, or LLM embedding)
    oGenerator       = NULL  # Generative LLM (Qwen, BitNet, etc.)
    oVectorDB        = NULL  # Decoupled Vector Storage
    oChunker         = NULL  # Text Chunker
    oContextManager  = NULL  # Context Budgeting & Formatting

    cSystemPrompt    = "You are a precise, factual AI assistant. Answer the user question accurately using ONLY the provided reference context. If the answer cannot be found in the context, state that the information is not available."
    nTopK            = 3
    fHybridWeight    = 0.65  # 0.65 Dense Vector, 0.35 Lexical Keyword
    nMaxGenTokens    = 256

    func init(oEmbedderModel, oGenModel = NULL, cDBPath = "data/memory/rag_store")
        oEmbedder       = oEmbedderModel
        oGenerator      = oGenModel
        oChunker        = new MadarChunker(150, 30) # 150 words per chunk, 30 words overlap
        oContextManager = new MadarContextManager(4096, nMaxGenTokens)
        
        # Determine embedding dimension
        nDim = 768
        if !isNull(oEmbedder)
            try
                if isAttribute(oEmbedder, "nEmbeddingDim")
                    nDim = oEmbedder.nEmbeddingDim
                elseif isAttribute(oEmbedder, "nDim")
                    nDim = oEmbedder.nDim
                ok
            catch
            done
        ok

        oVectorDB = new MadarVectorDB(nDim, cDBPath)
        return self

    # ----------------------------------------------------------------
    # Ingestion: Ingest Text with Semantic Overlapping Chunking
    # ----------------------------------------------------------------
    func addText(cText)
        if cText = "" or isNull(oEmbedder) return 0 ok
        aChunks = oChunker.chunkText(cText)
        nCount = 0
        for cChunk in aChunks
            oVec = oEmbedder.embedding(cChunk)
            oVectorDB.addDocument(cChunk, oVec)
            nCount++
        next
        return nCount

    # Ingest a text or markdown file
    func addFile(cFilePath)
        if !fexists(cFilePath)
            raise(f"MadarRAG: File not found: {cFilePath}")
        ok
        cContent = read(cFilePath)
        cExt = lower(JustFileExt(cFilePath))

        aChunks = []
        if cExt = "md" or cExt = "markdown"
            aChunks = oChunker.chunkMarkdown(cContent, JustFileName(cFilePath))
        else
            aChunks = oChunker.chunkText(cContent)
        ok

        nCount = 0
        for cChunk in aChunks
            oVec = oEmbedder.embedding(cChunk)
            oVectorDB.addDocument(cChunk, oVec)
            nCount++
        next
        return nCount

    # ----------------------------------------------------------------
    # Hybrid Retrieval: Dense Vectors + Lexical Keywords (RRF)
    # ----------------------------------------------------------------
    func retrieve(cQuestion, nK = 0)
        if nK <= 0 nK = nTopK ok
        if isNull(oEmbedder) or oVectorDB.count() = 0
            return []
        ok

        # 1. Dense Semantic Query Vector
        oQueryVec = oEmbedder.embedding(cQuestion)

        # Retrieve a broader candidate pool for re-ranking (e.g. 2x to 3x of nK)
        nPoolSize = min(oVectorDB.count(), nK * 3)
        aDenseResults = oVectorDB.query(oQueryVec, nPoolSize)

        if len(aDenseResults) <= 1 or fHybridWeight >= 1.0
            if len(aDenseResults) > nK
                return aDenseResults[1:nK]
            ok
            return aDenseResults
        ok

        # 2. Extract Query Keywords (Filtered Stopwords)
        aKeywords = extractKeywords(cQuestion)

        # 3. Reciprocal Rank Fusion / Calibrated Scoring
        aHybridScored = []
        nDocRank = 1
        for item in aDenseResults
            fDenseScore = item[:score]
            cDocText    = lower(item[:text])

            # Lexical match score
            nMatches = 0.0
            if len(aKeywords) > 0
                for kw in aKeywords
                    if substr(cDocText, kw) > 0
                        nMatches += 1.0
                    ok
                next
                fLexScore = nMatches / len(aKeywords)
            else
                fLexScore = 0.0
            ok

            # Combined Calibrated Score
            fFinalScore = (fHybridWeight * fDenseScore) + ((1.0 - fHybridWeight) * fLexScore)

            aHybridScored + [
                fFinalScore,
                item[:id],
                item[:text],
                fDenseScore,
                fLexScore
            ]
            nDocRank++
        next

        # Sort descending by numeric hybrid score (column 1)
        aSorted = sort(aHybridScored, 1)
        aRanked = aSorted[::-1]

        nLimit = min(nK, len(aRanked))
        aFinal = []
        for k = 1 to nLimit
            aFinal + [
                :score = aRanked[k][1],
                :id    = aRanked[k][2],
                :text  = aRanked[k][3],
                :dense = aRanked[k][4],
                :lex   = aRanked[k][5]
            ]
        next
        return aFinal

    # ----------------------------------------------------------------
    # Ask: Complete RAG Pipeline from Question to Generated Answer
    # ----------------------------------------------------------------
    func ask(cQuestion, nK = 0, bStream = false)
        if nK <= 0 nK = nTopK ok

        # 1. Retrieve most relevant context chunks
        aContextDocs = retrieve(cQuestion, nK)

        # If no documents exist or nothing retrieved, fall back to generator
        if len(aContextDocs) = 0
            if !isNull(oGenerator)
                return oGenerator.chat(cQuestion, nMaxGenTokens)
            ok
            return "No relevant context found in database."
        ok

        # 2. Pack and budget context into prompt
        cPrompt = oContextManager.buildPrompt(aContextDocs, cQuestion, cSystemPrompt)

        # 3. Generate Answer via LLM
        if !isNull(oGenerator)
            if bStream
                return oGenerator.generateStream(cPrompt, nMaxGenTokens)
            else
                return oGenerator.generate(cPrompt, nMaxGenTokens)
            ok
        ok

        # If generator not attached, return assembled prompt for external use
        return cPrompt

    # ----------------------------------------------------------------
    # Stopword-Filtered Keyword Extraction (Arabic & English)
    # ----------------------------------------------------------------
    private
    func extractKeywords(cQuery)
        aStopwords = [
            "ما", "هو", "هي", "ماهو", "ماهي", "ماذا", "هل", "من", "في", "على", 
            "إلى", "الي", "عن", "مع", "هذا", "هذه", "تلك", "ذلك", "كان", "أن", 
            "ان", "أو", "او", "ثم", "كيف", "اين", "أين", "متى", "كم", "لماذا",
            "the", "is", "at", "which", "on", "a", "an", "and", "or", "what", "how", "who", "where"
        ]
        cClean = lower(trim(cQuery))
        cClean = substr(cClean, "؟", "")
        cClean = substr(cClean, "?", "")
        cClean = substr(cClean, ".", "")
        cClean = substr(cClean, ",", "")
        cClean = substr(cClean, "،", "")

        aTokens = split(cClean, " ")
        aKeywords = []
        for tok in aTokens
            tok = trim(tok)
            if len(tok) >= 2 and find(aStopwords, tok) = 0
                aKeywords + tok
            ok
        next
        return aKeywords
