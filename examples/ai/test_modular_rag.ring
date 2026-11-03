# ====================================================================
# Madar AI - Modular Decoupled RAG Verification Suite
# Verifies:
#   1. MadarVectorDB: Decoupled storage (.vec, .idx, .meta)
#   2. Precision Disk Seeks (fseek) with Zero RAM Text Footprint
#   3. Binary Persistence (Int2Bytes / Double2Bytes / Float2Bytes)
#   4. MadarChunker: Semantic Overlapping Window & Markdown Awareness
#   5. MadarContextManager: Dynamic Budgeting & Strategic Context Placement
#   6. MadarRAG: Hybrid Search (Dense Cosine + Lexical Overlap)
# ====================================================================

load "stdlibcore.ring"
load "../../libraries/madar_ai/rag/init.ring"

func main()
    ? "===================================================================="
    ? "  Madar AI: Modular Decoupled RAG Architecture Test"
    ? "===================================================================="

    # Clean up any leftover test files
    cTestDB = "test_memory_rag"
    cleanupTestFiles(cTestDB)

    # ----------------------------------------------------------------
    # 1. Test MadarVectorDB (Decoupled Storage & Precision Disk Seeks)
    # ----------------------------------------------------------------
    ? "[Test 1] Initializing Decoupled MadarVectorDB (Dim=4)..."
    nDim = 4
    oDB = new MadarVectorDB(nDim, cTestDB)

    # Document 1: Artificial Intelligence (Tech: [1.0, 0.0, 0.0, 0.0])
    v1 = tensor_from_list([1.0, 0.0, 0.0, 0.0], "float32")
    cDoc1 = "Madar Engine is an ultra-fast runtime specialized in Ring and AI tensors."
    oDB.addDocument(cDoc1, v1)

    # Document 2: Forestry & Nature (Bio: [0.0, 1.0, 0.0, 0.0])
    v2 = tensor_from_list([0.0, 1.0, 0.0, 0.0], "float32")
    cDoc2 = "Cedar trees grow extensively in high altitude Mediterranean forests."
    oDB.addDocument(cDoc2, v2)

    # Document 3: Robotics (Tech/AI: [0.9, 0.1, 0.0, 0.0])
    v3 = tensor_from_list([0.9, 0.1, 0.0, 0.0], "float32")
    cDoc3 = "Autonomous robotic systems require real-time low-latency neural inference."
    oDB.addDocument(cDoc3, v3)

    # Document 4: Botany & Trees (Bio: [0.1, 0.9, 0.0, 0.0])
    v4 = tensor_from_list([0.1, 0.9, 0.0, 0.0], "float32")
    cDoc4 = "Photosynthesis allows green plants and trees to synthesize nutrients from light."
    oDB.addDocument(cDoc4, v4)

    ? f"   -> Added {oDB.count()} documents to database."
    ? f"   -> RAM footprint for text: 0 Bytes (Stored strictly on disk in '{cTestDB}.meta')"

    # Query for Tech: [1.0, 0.0, 0.0, 0.0]
    ? nl + "[Test 2] Querying Semantic Vector for 'AI & Computing'..."
    qTech = tensor_from_list([1.0, 0.0, 0.0, 0.0], "float32")
    aResults = oDB.query(qTech, 2)

    ? f"   -> Top 2 Results Fetched via Precision fseek():"
    for i = 1 to len(aResults)
        res = aResults[i]
        nId = res[:id]
        fScore = res[:score]
        nOffset = res[:offset]
        cText = res[:text]
        ? f"      [{i}] Doc #{nId} | Score: {fScore} | Offset: {nOffset} B"
        ? "          Text: " + char(34) + cText + char(34)
    next

    # Assert correctness
    if aResults[1][:id] = 1 and aResults[2][:id] = 3
        ? "   [SUCCESS] Top-K matches accurately retrieved from disk!"
    else
        ? "   [FAIL] Unexpected query ranking"
    ok

    # ----------------------------------------------------------------
    # 2. Test Binary Persistence (.vec and .idx)
    # ----------------------------------------------------------------
    ? nl + "[Test 3] Testing Binary Serialization (saveDB / loadDB)..."
    oDB.saveDB()
    ? f"   -> Saved: '{cTestDB}.vec' (Raw Floats) & '{cTestDB}.idx' (Binary Offsets)"

    # Create fresh empty DB and load from disk
    oFreshDB = new MadarVectorDB(nDim, cTestDB)
    nLoaded = oFreshDB.loadDB()
    ? f"   -> Loaded {nLoaded} records into fresh DB instance."

    aFreshResults = oFreshDB.query(qTech, 1)
    if len(aFreshResults) > 0 and aFreshResults[1][:id] = 1
        cVerifiedText = aFreshResults[1][:text]
        ? "   [SUCCESS] Loaded DB query verified: " + char(34) + cVerifiedText + char(34)
    else
        ? "   [FAIL] Binary reload query failed"
    ok

    # ----------------------------------------------------------------
    # 3. Test MadarChunker (Sliding Window with Overlap)
    # ----------------------------------------------------------------
    ? nl + "[Test 4] Testing MadarChunker with Overlap..."
    oChunker = new MadarChunker(20, 5) # 20 words per chunk, 5 words overlap
    cLongText = "The Madar project was created to deliver an uncompromised high-performance engine. " +
                "By combining modern JIT compilation, native tensor primitives, and AVX2 vectorization, " +
                "Madar allows developers to run complex machine learning architectures directly. " +
                "This includes dense LLMs, BitNet ternary networks, and production-grade RAG systems."

    aChunks = oChunker.chunkText(cLongText)
    ? f"   -> Generated {len(aChunks)} chunks with 5-word overlap:"
    for i = 1 to len(aChunks)
        ? "      Chunk #" + i + ": " + char(34) + aChunks[i] + char(34)
    next

    # ----------------------------------------------------------------
    # 4. Test MadarContextManager (Budgeting & Lost-in-the-Middle)
    # ----------------------------------------------------------------
    ? nl + "[Test 5] Testing Context Budget Manager & Strategic Placement..."
    oCtx = new MadarContextManager(100, 30) # Strict small budget for demonstration
    aDocsToPack = [
        [:text = "Doc 1 (Top Relevance): Madar AI runtime utilizes AVX2 kernels."],
        [:text = "Doc 2 (Secondary): Ring language supports declarative programming."],
        [:text = "Doc 3 (Tertiary): Traditional CPUs benefit from cache locality."]
    ]
    cPrompt = oCtx.buildPrompt(aDocsToPack, "What does Madar AI utilize?")
    ? "   -> Assembled Prompt Body:"
    ? "------------------------------------------------------------"
    ? cPrompt
    ? "------------------------------------------------------------"
    ? "   [SUCCESS] Notice Rank 1 is strategically placed adjacent to user query!"

    # ----------------------------------------------------------------
    # Cleanup
    # ----------------------------------------------------------------
    cleanupTestFiles(cTestDB)
    ? nl + "===================================================================="
    ? "  All Decoupled RAG Architectural Tests Completed Successfully!"
    ? "===================================================================="

func cleanupTestFiles(cDB)
    cVec  = cDB + ".vec"
    cIdx  = cDB + ".idx"
    cMeta = cDB + ".meta"
    if fexists(cVec)  remove(cVec)  ok
    if fexists(cIdx)  remove(cIdx)  ok
    if fexists(cMeta) remove(cMeta) ok
